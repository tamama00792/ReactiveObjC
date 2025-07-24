//
//  RACSequence.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACSequence.h"
#import "RACArraySequence.h"
#import "RACDynamicSequence.h"
#import "RACEagerSequence.h"
#import "RACEmptySequence.h"
#import "RACScheduler.h"
#import "RACSignal.h"
#import "RACSubscriber.h"
#import "RACTuple.h"
#import "RACUnarySequence.h"

// 一个用于遍历序列的枚举器。
@interface RACSequenceEnumerator : NSEnumerator

// 当前正在枚举的序列。
//
// 此属性会随着枚举器的耗尽而变化。应当只在对 self 加锁的情况下访问。
@property (nonatomic, strong) RACSequence *sequence;

@end

@interface RACSequence ()

// 执行一次惰性绑定迭代，将 current 中的值传递下去，直到序列耗尽，然后递归地绑定接收者中的剩余值。
//
// 返回一个新序列，包含 current，然后是对接收者剩余值应用 block 后的所有结果。
- (RACSequence *)bind:(RACSequenceBindBlock)block passingThroughValuesFromSequence:(RACSequence *)current;

@end

@implementation RACSequenceEnumerator

// 获取下一个对象。
//
// 原理：通过同步锁保护 sequence 属性，获取当前序列的 head，并将 sequence 更新为 tail，实现惰性遍历。
- (id)nextObject {
	id object = nil;
	
	@synchronized (self) {
		object = self.sequence.head;
		self.sequence = self.sequence.tail;
	}
	
	return object;
}

@end

@implementation RACSequence

#pragma mark Lifecycle

// 创建一个带有 headBlock 和 tailBlock 的序列。
//
// 原理：通过传入的 block 延迟生成 head 和 tail，实现惰性序列。
+ (RACSequence *)sequenceWithHeadBlock:(id (^)(void))headBlock tailBlock:(RACSequence<id> *(^)(void))tailBlock {
	return [[RACDynamicSequence sequenceWithHeadBlock:headBlock tailBlock:tailBlock] setNameWithFormat:@"+sequenceWithHeadBlock:tailBlock:"];
}

#pragma mark Class cluster primitives

// 获取序列的第一个元素。
//
// 原理：抽象方法，需子类实现。用于惰性获取序列头部。
- (id)head {
	NSCAssert(NO, @"%s must be overridden by subclasses", __func__);
	return nil;
}

// 获取序列的剩余部分（去掉 head 后的序列）。
//
// 原理：抽象方法，需子类实现。用于惰性获取序列尾部。
- (RACSequence *)tail {
	NSCAssert(NO, @"%s must be overridden by subclasses", __func__);
	return nil;
}

#pragma mark RACStream

// 返回一个空序列。
//
// 原理：直接返回 RACEmptySequence 的单例。
+ (RACSequence *)empty {
	return RACEmptySequence.empty;
}

// 返回一个只包含 value 的序列。
//
// 原理：通过 RACUnarySequence 实现单元素序列。
+ (RACSequence *)return:(id)value {
	return [RACUnarySequence return:value];
}

// 对序列进行绑定操作。
//
// 原理：将 block 应用于序列的每个元素，返回新的序列。实现了 Monad 的 bind 操作。
- (RACSequence *)bind:(RACSequenceBindBlock (^)(void))block {
	RACSequenceBindBlock bindBlock = block();
	return [[self bind:bindBlock passingThroughValuesFromSequence:nil] setNameWithFormat:@"[%@] -bind:", self.name];
}

// bind 的内部实现，支持惰性传递。
//
// 原理：通过 while 循环和递归，惰性地将 bindBlock 应用于每个元素，避免中间集合和装箱，提高性能。
- (RACSequence *)bind:(RACSequenceBindBlock)bindBlock passingThroughValuesFromSequence:(RACSequence *)passthroughSequence {
	// Store values calculated in the dependency here instead, avoiding any kind
	// of temporary collection and boxing.
	//
	// This relies on the implementation of RACDynamicSequence synchronizing
	// access to its head, tail, and dependency, and we're only doing it because
	// we really need the performance.
	__block RACSequence *valuesSeq = self;
	__block RACSequence *current = passthroughSequence;
	__block BOOL stop = NO;

	RACSequence *sequence = [RACDynamicSequence sequenceWithLazyDependency:^ id {
		while (current.head == nil) {
			if (stop) return nil;

			// We've exhausted the current sequence, create a sequence from the
			// next value.
			id value = valuesSeq.head;

			if (value == nil) {
				// We've exhausted all the sequences.
				stop = YES;
				return nil;
			}

			current = (id)bindBlock(value, &stop);
			if (current == nil) {
				stop = YES;
				return nil;
			}

			valuesSeq = valuesSeq.tail;
		}

		NSCAssert([current isKindOfClass:RACSequence.class], @"-bind: block returned an object that is not a sequence: %@", current);
		return nil;
	} headBlock:^(id _) {
		return current.head;
	} tailBlock:^ id (id _) {
		if (stop) return nil;

		return [valuesSeq bind:bindBlock passingThroughValuesFromSequence:current.tail];
	}];

	sequence.name = self.name;
	return sequence;
}

// 拼接两个序列。
//
// 原理：将 self 和 sequence 组成一个数组序列，然后 flatten 展平成一个新序列。
- (RACSequence *)concat:(RACSequence *)sequence {
	NSCParameterAssert(sequence != nil);

	return [[[RACArraySequence sequenceWithArray:@[ self, sequence ] offset:0]
		flatten]
		setNameWithFormat:@"[%@] -concat: %@", self.name, sequence];
}

// 将两个序列按顺序配对，生成元组序列。
//
// 原理：递归地将 self 和 sequence 的 head 组成元组，tail 继续 zip，直到任一序列耗尽。
- (RACSequence *)zipWith:(RACSequence *)sequence {
	NSCParameterAssert(sequence != nil);

	return [[RACSequence
		sequenceWithHeadBlock:^ id {
			if (self.head == nil || sequence.head == nil) return nil;
			return RACTuplePack(self.head, sequence.head);
		} tailBlock:^ id {
			if (self.tail == nil || [[RACSequence empty] isEqual:self.tail]) return nil;
			if (sequence.tail == nil || [[RACSequence empty] isEqual:sequence.tail]) return nil;

			return [self.tail zipWith:sequence.tail];
		}]
		setNameWithFormat:@"[%@] -zipWith: %@", self.name, sequence];
}

#pragma mark Extended methods

// 将序列转为数组。
//
// 原理：遍历序列，将每个元素添加到可变数组，最后返回不可变副本。
- (NSArray *)array {
	NSMutableArray *array = [NSMutableArray array];
	for (id obj in self) {
		[array addObject:obj];
	}

	return [array copy];
}

// 返回一个枚举器用于遍历序列。
//
// 原理：返回自定义的 RACSequenceEnumerator，支持惰性遍历。
- (NSEnumerator *)objectEnumerator {
	RACSequenceEnumerator *enumerator = [[RACSequenceEnumerator alloc] init];
	enumerator.sequence = self;
	return enumerator;
}

// 将序列转为信号。
//
// 原理：使用默认调度器，将序列的每个元素通过信号发送出去。
- (RACSignal *)signal {
	return [[self signalWithScheduler:[RACScheduler scheduler]] setNameWithFormat:@"[%@] -signal", self.name];
}

// 使用指定调度器将序列转为信号。
//
// 原理：递归调度，每次发送序列的 head，直到序列耗尽，最后发送完成。
- (RACSignal *)signalWithScheduler:(RACScheduler *)scheduler {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block RACSequence *sequence = self;

		return [scheduler scheduleRecursiveBlock:^(void (^reschedule)(void)) {
			if (sequence.head == nil) {
				[subscriber sendCompleted];
				return;
			}

			[subscriber sendNext:sequence.head];

			sequence = sequence.tail;
			reschedule();
		}];
	}] setNameWithFormat:@"[%@] -signalWithScheduler: %@", self.name, scheduler];
}

// 从左到右折叠序列。
//
// 原理：遍历序列，将每个元素与累加器通过 reduce 合并，最终返回累加结果。
- (id)foldLeftWithStart:(id)start reduce:(id (^)(id, id))reduce {
	NSCParameterAssert(reduce != NULL);

	if (self.head == nil) return start;
	
	for (id value in self) {
		start = reduce(start, value);
	}
	
	return start;
}

// 从右到左折叠序列。
//
// 原理：递归地将序列的 head 与 tail 的折叠结果通过 reduce 合并，适合惰性序列。
- (id)foldRightWithStart:(id)start reduce:(id (^)(id, RACSequence *))reduce {
	NSCParameterAssert(reduce != NULL);

	if (self.head == nil) return start;
	
	RACSequence *rest = [RACSequence sequenceWithHeadBlock:^{
		if (self.tail) {
			return [self.tail foldRightWithStart:start reduce:reduce];
		} else {
			return start;
		}
	} tailBlock:nil];
	
	return reduce(self.head, rest);
}

// 判断序列中是否有元素满足条件。
//
// 原理：调用 objectPassingTest，找到第一个满足 block 的元素。
- (BOOL)any:(BOOL (^)(id))block {
	NSCParameterAssert(block != NULL);

	return [self objectPassingTest:block] != nil;
}

// 判断序列中所有元素是否都满足条件。
//
// 原理：使用 foldLeftWithStart，累加所有元素的判断结果。
- (BOOL)all:(BOOL (^)(id))block {
	NSCParameterAssert(block != NULL);
	
	NSNumber *result = [self foldLeftWithStart:@YES reduce:^(NSNumber *accumulator, id value) {
		return @(accumulator.boolValue && block(value));
	}];
	
	return result.boolValue;
}

// 返回第一个满足条件的元素。
//
// 原理：通过 filter 过滤后取 head。
- (id)objectPassingTest:(BOOL (^)(id))block {
	NSCParameterAssert(block != NULL);

	return [self filter:block].head;
}

// 转为 eager（立即求值）序列。
//
// 原理：将当前序列转为数组，再用 RACEagerSequence 包装。
- (RACSequence *)eagerSequence {
	return [RACEagerSequence sequenceWithArray:self.array offset:0];
}

// 转为 lazy（惰性求值）序列。
//
// 原理：直接返回 self。
- (RACSequence *)lazySequence {
	return self;
}

#pragma mark NSCopying

// 返回自身，序列不可变。
- (id)copyWithZone:(NSZone *)zone {
	return self;
}

#pragma mark NSCoding

// 序列归档时的类。
//
// 原理：大多数序列归档为 RACArraySequence。
- (Class)classForCoder {
	return RACArraySequence.class;
}

// 反归档初始化。
//
// 原理：如果不是 RACArraySequence，则用 RACArraySequence 解码。
- (id)initWithCoder:(NSCoder *)coder {
	if (![self isKindOfClass:RACArraySequence.class]) return [[RACArraySequence alloc] initWithCoder:coder];

	// 解码由 RACArraySequence 处理。
	return [super init];
}

// 编码序列。
//
// 原理：将序列转为数组后编码。
- (void)encodeWithCoder:(NSCoder *)coder {
	[coder encodeObject:self.array forKey:@"array"];
}

#pragma mark NSFastEnumeration

// 支持 for...in 快速遍历。
//
// 原理：通过 state->state 记录当前序列，遍历时惰性获取 head 和 tail，直到序列耗尽。
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id *)stackbuf count:(NSUInteger)len {
	if (state->state == ULONG_MAX) {
		// 枚举已完成。
		return 0;
	}

	// 需要在多次调用时遍历序列本身，用 state->state 记录当前 head。
	RACSequence *(^getSequence)(void) = ^{
		return (__bridge RACSequence *)(void *)state->state;
	};

	void (^setSequence)(RACSequence *) = ^(RACSequence *sequence) {
		// 释放旧序列并保留新序列。
		CFBridgingRelease((void *)state->state);

		state->state = (unsigned long)CFBridgingRetain(sequence);
	};

	void (^complete)(void) = ^{
		// 释放存储的序列。
		setSequence(nil);
		state->state = ULONG_MAX;
	};

	if (state->state == 0) {
		// 序列不可变，只需设置为非 NULL。
		state->mutationsPtr = state->extra;

		setSequence(self);
	}

	state->itemsPtr = stackbuf;

	NSUInteger enumeratedCount = 0;
	while (enumeratedCount < len) {
		RACSequence *seq = getSequence();

		// 因为序列中的对象可能是惰性生成的，需防止被提前释放。
		__autoreleasing id obj = seq.head;
		if (obj == nil) {
			complete();
			break;
		}

		stackbuf[enumeratedCount++] = obj;

		if (seq.tail == nil) {
			complete();
			break;
		}

		setSequence(seq.tail);
	}

	return enumeratedCount;
}

#pragma mark NSObject

// 计算哈希值。
//
// 原理：直接返回 head 的哈希。
- (NSUInteger)hash {
	return [self.head hash];
}

// 判断两个序列是否相等。
//
// 原理：逐个比较 head，直到任一序列耗尽。
- (BOOL)isEqual:(RACSequence *)seq {
	if (self == seq) return YES;
	if (![seq isKindOfClass:RACSequence.class]) return NO;

	for (id<NSObject> selfObj in self) {
		id<NSObject> seqObj = seq.head;

		// 处理 nil 情况。
		if (![seqObj isEqual:selfObj]) return NO;

		seq = seq.tail;
	}

	// self 已耗尽，参数也应耗尽。
	return (seq.head == nil);
}

@end
