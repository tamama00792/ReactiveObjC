//
//  RACArraySequence.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACArraySequence.h"

/**
 * @class RACArraySequence
 * @brief 用于对NSArray进行惰性序列化的类，实现了RACSequence协议。
 * @discussion 该类将一个NSArray包装为一个可惰性遍历的序列，支持链式操作、惰性求值等函数式编程特性。常用于需要对数组进行流式处理、组合、变换等场景。
 */
@interface RACArraySequence ()

/**
 * @brief 从父类重新声明并标记为已废弃，防止误用`array`字段。
 * @discussion 推荐使用backingArray字段来访问底层数组。
 */
@property (nonatomic, copy, readonly) NSArray *array __attribute__((deprecated));

/**
 * @brief 被序列化的原始NSArray。
 * @discussion 该字段保存了需要被惰性遍历的数组内容。
 */
@property (nonatomic, copy, readonly) NSArray *backingArray;

/**
 * @brief 序列起始的数组下标。
 * @discussion 用于标记当前序列在backingArray中的起始位置，实现惰性遍历。
 */
@property (nonatomic, assign, readonly) NSUInteger offset;

@end

@implementation RACArraySequence

#pragma mark Lifecycle

/**
 * @brief 通过数组和偏移量创建一个RACArraySequence实例。
 * @param array 需要被序列化的NSArray。
 * @param offset 序列起始的数组下标。
 * @return 返回一个新的RACArraySequence对象。
 * @discussion 该方法用于生成以指定offset为起点的惰性序列。如果offset等于数组长度，则返回空序列。
 * @实现原理 首先断言offset合法，然后根据offset判断是否返回空序列，否则初始化一个RACArraySequence对象并设置其backingArray和offset。
 */
+ (RACSequence *)sequenceWithArray:(NSArray *)array offset:(NSUInteger)offset {
	NSCParameterAssert(offset <= array.count);

	if (offset == array.count) return self.empty;

	RACArraySequence *seq = [[self alloc] init];
	seq->_backingArray = [array copy];
	seq->_offset = offset;
	return seq;
}

#pragma mark RACSequence

/**
 * @brief 获取当前序列的第一个元素。
 * @return 返回序列的第一个元素。
 * @discussion 用于惰性获取序列的头部元素。
 * @实现原理 直接返回backingArray中offset位置的元素。
 */
- (id)head {
	return self.backingArray[self.offset];
}

/**
 * @brief 获取当前序列的尾部（去除第一个元素后的子序列）。
 * @return 返回去除第一个元素后的RACSequence对象。
 * @discussion 用于链式遍历序列。
 * @实现原理 通过递增offset，递归生成新的RACArraySequence对象。
 */
- (RACSequence *)tail {
	RACSequence *sequence = [self.class sequenceWithArray:self.backingArray offset:self.offset + 1];
	sequence.name = self.name;
	return sequence;
}

#pragma mark NSFastEnumeration

/**
 * @brief 支持for...in语法的快速遍历。
 * @param state 枚举状态。
 * @param stackbuf 用于存放遍历元素的缓冲区。
 * @param len 缓冲区长度。
 * @return 返回本次填充的元素个数。
 * @discussion 允许RACArraySequence对象被for...in遍历。
 * @实现原理 分三部分：
 * 1. 检查遍历是否结束。
 * 2. 初始化state。
 * 3. 从backingArray中按offset和len填充stackbuf。
 */
- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(__unsafe_unretained id[])stackbuf count:(NSUInteger)len {
	NSCParameterAssert(len > 0);

	// 1. 检查是否遍历结束
	if (state->state >= self.backingArray.count) {
		// Enumeration has completed.
		return 0;
	}

	// 2. 初始化state
	if (state->state == 0) {
		state->state = self.offset;

		// Since a sequence doesn't mutate, this just needs to be set to
		// something non-NULL.
		state->mutationsPtr = state->extra;
	}

	state->itemsPtr = stackbuf;

	NSUInteger startIndex = state->state;
	NSUInteger index = 0;

	// 3. 填充stackbuf
	for (id value in self.backingArray) {
		// 跳过offset之前的元素
		if (index < startIndex) {
			++index;
			continue;
		}

		stackbuf[index - startIndex] = value;

		++index;
		if (index - startIndex >= len) break;
	}

	NSCAssert(index > startIndex, @"Final index (%lu) should be greater than start index (%lu)", (unsigned long)index, (unsigned long)startIndex);

	state->state = index;
	return index - startIndex;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
/**
 * @brief 获取当前序列对应的子数组。
 * @return 返回从offset开始的子数组。
 * @discussion 该方法已废弃，建议直接使用backingArray。
 * @实现原理 通过subarrayWithRange获取offset到末尾的子数组。
 */
- (NSArray *)array {
	return [self.backingArray subarrayWithRange:NSMakeRange(self.offset, self.backingArray.count - self.offset)];
}
#pragma clang diagnostic pop

#pragma mark NSCoding

/**
 * @brief 通过NSCoder解码初始化对象。
 * @param coder 用于解码的NSCoder对象。
 * @return 返回解码后的RACArraySequence对象。
 * @discussion 用于序列化/反序列化场景。
 * @实现原理 先调用父类解码，再解码backingArray，offset默认为0。
 */
- (instancetype)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self == nil) return nil;

	_backingArray = [coder decodeObjectForKey:@"array"];
	_offset = 0;

	return self;
}

/**
 * @brief 对象编码方法。
 * @param coder 用于编码的NSCoder对象。
 * @discussion 主要由父类RACSequence处理编码逻辑。
 */
- (void)encodeWithCoder:(NSCoder *)coder {
	// Encoding is handled in RACSequence.
	[super encodeWithCoder:coder];
}

#pragma mark NSObject

/**
 * @brief 返回对象的描述信息。
 * @return 返回包含类名、指针、name和backingArray的字符串。
 * @discussion 便于调试和日志输出。
 */
- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p>{ name = %@, array = %@ }", self.class, self, self.name, self.backingArray];
}

@end
