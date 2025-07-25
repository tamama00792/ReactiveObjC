//
//  RACEagerSequence.m
//  ReactiveObjC
//
//  Created by Uri Baghin on 02/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACEagerSequence.h"
#import "NSObject+RACDescription.h"
#import "RACArraySequence.h"

/**
 * @class RACEagerSequence
 * @brief 立即求值的序列，所有元素在创建时即被计算。
 * @discussion 适用于需要立即遍历、不可变、支持链式操作的场景。
 */
@implementation RACEagerSequence

#pragma mark RACStream

/**
 * @brief 创建只包含一个元素的RACEagerSequence。
 * @param value 序列的唯一元素。
 * @return 返回包含value的RACEagerSequence。
 */
+ (RACSequence *)return:(id)value {
	return [[self sequenceWithArray:@[ value ] offset:0] setNameWithFormat:@"+return: %@", RACDescription(value)];
}

/**
 * @brief 对序列中的每个元素应用bindBlock，并将结果拼接为新序列。
 * @param block 返回RACSequenceBindBlock的block。
 * @return 返回拼接后的新RACEagerSequence。
 * @discussion 适用于链式变换、flatMap等场景。
 * @实现原理 先遍历当前数组，对每个元素应用bindBlock，结果展开后加入新数组，遇到stop时提前终止。
 */
- (RACSequence *)bind:(RACSequenceBindBlock (^)(void))block {
	NSCParameterAssert(block != nil);
	RACStreamBindBlock bindBlock = block();
	NSArray *currentArray = self.array;
	NSMutableArray *resultArray = [NSMutableArray arrayWithCapacity:currentArray.count];
	
	for (id value in currentArray) {
		BOOL stop = NO;
		RACSequence *boundValue = (id)bindBlock(value, &stop);
		if (boundValue == nil) break;

		for (id x in boundValue) {
			[resultArray addObject:x];
		}

		if (stop) break;
	}
	
	return [[self.class sequenceWithArray:resultArray offset:0] setNameWithFormat:@"[%@] -bind:", self.name];
}

/**
 * @brief 拼接另一个序列到当前序列后面。
 * @param sequence 需要拼接的序列。
 * @return 返回拼接后的新RACEagerSequence。
 * @discussion 适用于序列合并、追加等场景。
 * @实现原理 直接拼接两个数组，生成新序列。
 */
- (RACSequence *)concat:(RACSequence *)sequence {
	NSCParameterAssert(sequence != nil);
	NSCParameterAssert([sequence isKindOfClass:RACSequence.class]);

	NSArray *array = [self.array arrayByAddingObjectsFromArray:sequence.array];
	return [[self.class sequenceWithArray:array offset:0] setNameWithFormat:@"[%@] -concat: %@", self.name, sequence];
}

#pragma mark Extended methods

/**
 * @brief 返回自身，表示当前为eager序列。
 * @return self。
 */
- (RACSequence *)eagerSequence {
	return self;
}

/**
 * @brief 转为惰性序列。
 * @return 返回RACArraySequence对象。
 */
- (RACSequence *)lazySequence {
	return [RACArraySequence sequenceWithArray:self.array offset:0];
}

/**
 * @brief 从右向左折叠序列。
 * @param start 初始值。
 * @param reduce 折叠函数。
 * @return 折叠结果。
 * @discussion 递归调用父类实现，保证每一步都用eagerSequence包装rest。
 */
- (id)foldRightWithStart:(id)start reduce:(id (^)(id, RACSequence *rest))reduce {
	return [super foldRightWithStart:start reduce:^(id first, RACSequence *rest) {
		return reduce(first, rest.eagerSequence);
	}];
}

@end
