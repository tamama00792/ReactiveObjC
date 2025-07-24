//
//  RACStream.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-31.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACStream.h"
#import "NSObject+RACDescription.h"
#import "RACBlockTrampoline.h"
#import "RACTuple.h"

// RACStream 是 ReactiveObjC 中流式操作的抽象基类，定义了流的基本操作和组合方式。
@implementation RACStream

#pragma mark Lifecycle

// 初始化方法，设置默认 name 为空字符串。
- (instancetype)init {
	self = [super init];

	self.name = @"";
	return self;
}

#pragma mark Abstract methods

// 返回一个空流。该方法为抽象方法，必须由子类实现。
+ (__kindof RACStream *)empty {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

// 绑定操作，将 block 应用于流中的每个元素。该方法为抽象方法，必须由子类实现。
- (__kindof RACStream *)bind:(RACStreamBindBlock (^)(void))block {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

// 返回一个只包含 value 的流。该方法为抽象方法，必须由子类实现。
+ (__kindof RACStream *)return:(id)value {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

// 将当前流与另一个流串联。该方法为抽象方法，必须由子类实现。
- (__kindof RACStream *)concat:(RACStream *)stream {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

// 将当前流与另一个流按元素配对。该方法为抽象方法，必须由子类实现。
- (__kindof RACStream *)zipWith:(RACStream *)stream {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

#pragma mark Naming

// 设置流的 name 属性，仅在环境变量 RAC_DEBUG_SIGNAL_NAMES 存在时生效。
- (instancetype)setNameWithFormat:(NSString *)format, ... {
	if (getenv("RAC_DEBUG_SIGNAL_NAMES") == NULL) return self;

	NSCParameterAssert(format != nil);

	va_list args;
	va_start(args, format);

	NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	self.name = str;
	return self;
}

@end

// MARK: - RACStream 操作扩展
@implementation RACStream (Operations)

// flattenMap: 将流中的每个元素通过 block 转换为新的流，并将所有流合并为一个流。
- (__kindof RACStream *)flattenMap:(__kindof RACStream * (^)(id value))block {
	Class class = self.class;

	return [[self bind:^{
		// 返回一个 block，每次处理流中的一个元素。
		return ^(id value, BOOL *stop) {
			id stream = block(value) ?: [class empty];
			NSCAssert([stream isKindOfClass:RACStream.class], @"-flattenMap: 返回的不是 RACStream 类型: %@", stream);

			return stream;
		};
	}] setNameWithFormat:@"[%@] -flattenMap:", self.name];
}

// flatten: 将流中的元素（本身为流）合并为一个流。
- (__kindof RACStream *)flatten {
	return [[self flattenMap:^(id value) {
		return value;
	}] setNameWithFormat:@"[%@] -flatten", self.name];
}

// map: 对流中的每个元素应用 block，并返回新的流。
- (__kindof RACStream *)map:(id (^)(id value))block {
	NSCParameterAssert(block != nil);

	Class class = self.class;
	
	return [[self flattenMap:^(id value) {
		return [class return:block(value)];
	}] setNameWithFormat:@"[%@] -map:", self.name];
}

// mapReplace: 用 object 替换流中的每个元素。
- (__kindof RACStream *)mapReplace:(id)object {
	return [[self map:^(id _) {
		return object;
	}] setNameWithFormat:@"[%@] -mapReplace: %@", self.name, RACDescription(object)];
}

// combinePreviousWithStart:reduce: 结合前一个和当前元素，生成新值。
- (__kindof RACStream *)combinePreviousWithStart:(id)start reduce:(id (^)(id previous, id next))reduceBlock {
	NSCParameterAssert(reduceBlock != NULL);
	return [[[self
		scanWithStart:RACTuplePack(start)
		reduce:^(RACTuple *previousTuple, id next) {
			id value = reduceBlock(previousTuple[0], next);
			return RACTuplePack(next, value);
		}]
		map:^(RACTuple *tuple) {
			return tuple[1];
		}]
		setNameWithFormat:@"[%@] -combinePreviousWithStart: %@ reduce:", self.name, RACDescription(start)];
}

// filter: 过滤流中的元素，仅保留 block 返回 YES 的元素。
- (__kindof RACStream *)filter:(BOOL (^)(id value))block {
	NSCParameterAssert(block != nil);

	Class class = self.class;
	
	return [[self flattenMap:^ id (id value) {
		if (block(value)) {
			return [class return:value];
		} else {
			return class.empty;
		}
	}] setNameWithFormat:@"[%@] -filter:", self.name];
}

// ignore: 忽略等于 value 的元素。
- (__kindof RACStream *)ignore:(id)value {
	return [[self filter:^ BOOL (id innerValue) {
		return innerValue != value && ![innerValue isEqual:value];
	}] setNameWithFormat:@"[%@] -ignore: %@", self.name, RACDescription(value)];
}

// reduceEach: 对流中的 RACTuple 元素应用 reduceBlock。
- (__kindof RACStream *)reduceEach:(RACReduceBlock)reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	__weak RACStream *stream __attribute__((unused)) = self;
	return [[self map:^(RACTuple *t) {
		NSCAssert([t isKindOfClass:RACTuple.class], @"流 %@ 的元素不是 RACTuple: %@", stream, t);
		return [RACBlockTrampoline invokeBlock:reduceBlock withArguments:t];
	}] setNameWithFormat:@"[%@] -reduceEach:", self.name];
}

// startWith: 在流前面插入一个元素。
- (__kindof RACStream *)startWith:(id)value {
	return [[[self.class return:value]
		concat:self]
		setNameWithFormat:@"[%@] -startWith: %@", self.name, RACDescription(value)];
}

// skip: 跳过前 skipCount 个元素。
- (__kindof RACStream *)skip:(NSUInteger)skipCount {
	Class class = self.class;
	
	return [[self bind:^{
		__block NSUInteger skipped = 0;

		return ^(id value, BOOL *stop) {
			if (skipped >= skipCount) return [class return:value];

			skipped++;
			return class.empty;
		};
	}] setNameWithFormat:@"[%@] -skip: %lu", self.name, (unsigned long)skipCount];
}

// take: 只取前 count 个元素。
- (__kindof RACStream *)take:(NSUInteger)count {
	Class class = self.class;
	
	if (count == 0) return class.empty;

	return [[self bind:^{
		__block NSUInteger taken = 0;

		return ^ id (id value, BOOL *stop) {
			if (taken < count) {
				++taken;
				if (taken == count) *stop = YES;
				return [class return:value];
			} else {
				return nil;
			}
		};
	}] setNameWithFormat:@"[%@] -take: %lu", self.name, (unsigned long)count];
}

// join: 将多个流合并为一个流，并通过 block 组合。
+ (__kindof RACStream *)join:(id<NSFastEnumeration>)streams block:(RACStream * (^)(id, id))block {
	RACStream *current = nil;

	// 依次将输入流合并为更大的元组流。
	for (RACStream *stream in streams) {
		// 第一个流，直接包装为 RACTuple。
		if (current == nil) {
			current = [stream map:^(id x) {
				return RACTuplePack(x);
			}];

			continue;
		}

		current = block(current, stream);
	}

	if (current == nil) return [self empty];

	return [current map:^(RACTuple *xs) {
		// 解包嵌套元组，生成最终的 RACTuple。
		NSMutableArray *values = [[NSMutableArray alloc] init];

		while (xs != nil) {
			[values insertObject:xs.last ?: RACTupleNil.tupleNil atIndex:0];
			xs = (xs.count > 1 ? xs.first : nil);
		}

		return [RACTuple tupleWithObjectsFromArray:values];
	}];
}

// zip: 将多个流按顺序配对组合为元组流。
+ (__kindof RACStream *)zip:(id<NSFastEnumeration>)streams {
	return [[self join:streams block:^(RACStream *left, RACStream *right) {
		return [left zipWith:right];
	}] setNameWithFormat:@"+zip: %@", streams];
}

// zip:reduce: 将多个流配对后应用 reduceBlock 生成新流。
+ (__kindof RACStream *)zip:(id<NSFastEnumeration>)streams reduce:(RACGenericReduceBlock)reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	RACStream *result = [self zip:streams];

	// 兼容旧版本 reduceBlock 为空的情况。
	if (reduceBlock != nil) result = [result reduceEach:reduceBlock];

	return [result setNameWithFormat:@"+zip: %@ reduce:", streams];
}

// concat: 将多个流顺序串联为一个流。
+ (__kindof RACStream *)concat:(id<NSFastEnumeration>)streams {
	RACStream *result = self.empty;
	for (RACStream *stream in streams) {
		result = [result concat:stream];
	}

	return [result setNameWithFormat:@"+concat: %@", streams];
}

// scanWithStart:reduce: 累加操作，对流中的每个元素应用 reduceBlock。
- (__kindof RACStream *)scanWithStart:(id)startingValue reduce:(id (^)(id running, id next))reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	return [[self
		scanWithStart:startingValue
		reduceWithIndex:^(id running, id next, NSUInteger index) {
			return reduceBlock(running, next);
		}]
		setNameWithFormat:@"[%@] -scanWithStart: %@ reduce:", self.name, RACDescription(startingValue)];
}

// scanWithStart:reduceWithIndex: 带索引的累加操作。
- (__kindof RACStream *)scanWithStart:(id)startingValue reduceWithIndex:(id (^)(id, id, NSUInteger))reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	Class class = self.class;

	return [[self bind:^{
		__block id running = startingValue;
		__block NSUInteger index = 0;

		return ^(id value, BOOL *stop) {
			running = reduceBlock(running, value, index++);
			return [class return:running];
		};
	}] setNameWithFormat:@"[%@] -scanWithStart: %@ reduceWithIndex:", self.name, RACDescription(startingValue)];
}

// takeUntilBlock: 满足 predicate 时停止取值。
- (__kindof RACStream *)takeUntilBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	Class class = self.class;
	
	return [[self bind:^{
		return ^ id (id value, BOOL *stop) {
			if (predicate(value)) return nil;

			return [class return:value];
		};
	}] setNameWithFormat:@"[%@] -takeUntilBlock:", self.name];
}

// takeWhileBlock: 只要 predicate 返回 YES 就持续取值。
- (__kindof RACStream *)takeWhileBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	return [[self takeUntilBlock:^ BOOL (id x) {
		return !predicate(x);
	}] setNameWithFormat:@"[%@] -takeWhileBlock:", self.name];
}

// skipUntilBlock: 满足 predicate 前跳过所有元素。
- (__kindof RACStream *)skipUntilBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	Class class = self.class;
	
	return [[self bind:^{
		__block BOOL skipping = YES;

		return ^ id (id value, BOOL *stop) {
			if (skipping) {
				if (predicate(value)) {
					skipping = NO;
				} else {
					return class.empty;
				}
			}

			return [class return:value];
		};
	}] setNameWithFormat:@"[%@] -skipUntilBlock:", self.name];
}

// skipWhileBlock: 只要 predicate 返回 YES 就跳过。
- (__kindof RACStream *)skipWhileBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	return [[self skipUntilBlock:^ BOOL (id x) {
		return !predicate(x);
	}] setNameWithFormat:@"[%@] -skipWhileBlock:", self.name];
}

// distinctUntilChanged: 过滤掉连续重复的元素。
- (__kindof RACStream *)distinctUntilChanged {
	Class class = self.class;

	return [[self bind:^{
		__block id lastValue = nil;
		__block BOOL initial = YES;

		return ^(id x, BOOL *stop) {
			if (!initial && (lastValue == x || [x isEqual:lastValue])) return [class empty];

			initial = NO;
			lastValue = x;
			return [class return:x];
		};
	}] setNameWithFormat:@"[%@] -distinctUntilChanged", self.name];
}

@end
