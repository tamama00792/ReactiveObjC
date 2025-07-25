//
//  RACDynamicSequence.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACDynamicSequence.h"
#import <libkern/OSAtomic.h>

// Determines how RACDynamicSequences will be deallocated before the next one is
// shifted onto the autorelease pool.
//
// This avoids stack overflows when deallocating long chains of dynamic
// sequences.
#define DEALLOC_OVERFLOW_GUARD 100

/**
 * @class RACDynamicSequence
 * @brief 支持惰性求值和依赖注入的动态序列。
 * @discussion 适用于链式、递归、无限序列等场景，支持依赖延迟初始化。
 */
@interface RACDynamicSequence () {
	// 已求值的head缓存。
	// 仅当headBlock为nil时有效。
	// 仅在@synchronized(self)下访问。
	id _head;

	// 已求值的tail缓存。
	// 仅当tailBlock为nil时有效。
	// 仅在@synchronized(self)下访问。
	RACSequence *_tail;

	// 已求值的依赖对象。
	// 仅当hasDependency为YES且dependencyBlock为nil时有效。
	// 仅在@synchronized(self)下访问。
	id _dependency;
}

/**
 * @brief 计算head的block。
 * @discussion 求值后应置为nil。类型随hasDependency而变。
 */
@property (nonatomic, strong) id headBlock;

/**
 * @brief 计算tail的block。
 * @discussion 求值后应置为nil。类型随hasDependency而变。
 */
@property (nonatomic, strong) id tailBlock;

/**
 * @brief 是否有依赖block。
 */
@property (nonatomic, assign) BOOL hasDependency;

/**
 * @brief 依赖的延迟初始化block。
 * @discussion 求值后应置为nil。
 */
@property (nonatomic, strong) id (^dependencyBlock)(void);

@end

@implementation RACDynamicSequence

#pragma mark Lifecycle

/**
 * @brief 以headBlock和tailBlock创建动态序列。
 * @param headBlock 计算head的block。
 * @param tailBlock 计算tail的block。
 * @return 返回RACDynamicSequence对象。
 * @discussion 不带依赖的惰性序列。
 */
+ (RACSequence *)sequenceWithHeadBlock:(id (^)(void))headBlock tailBlock:(RACSequence<id> *(^)(void))tailBlock {
	NSCParameterAssert(headBlock != nil);

	RACDynamicSequence *seq = [[RACDynamicSequence alloc] init];
	seq.headBlock = [headBlock copy];
	seq.tailBlock = [tailBlock copy];
	seq.hasDependency = NO;
	return seq;
}

/**
 * @brief 以依赖block、headBlock和tailBlock创建动态序列。
 * @param dependencyBlock 依赖的延迟初始化block。
 * @param headBlock 计算head的block，参数为依赖对象。
 * @param tailBlock 计算tail的block，参数为依赖对象。
 * @return 返回RACDynamicSequence对象。
 * @discussion 支持依赖注入的惰性序列。
 */
+ (RACSequence *)sequenceWithLazyDependency:(id (^)(void))dependencyBlock headBlock:(id (^)(id dependency))headBlock tailBlock:(RACSequence *(^)(id dependency))tailBlock {
	NSCParameterAssert(dependencyBlock != nil);
	NSCParameterAssert(headBlock != nil);

	RACDynamicSequence *seq = [[RACDynamicSequence alloc] init];
	seq.headBlock = [headBlock copy];
	seq.tailBlock = [tailBlock copy];
	seq.dependencyBlock = [dependencyBlock copy];
	seq.hasDependency = YES;
	return seq;
}

/**
 * @brief 析构函数，防止递归释放导致栈溢出。
 * @discussion 超过阈值时将tail放入自动释放池，避免递归。
 */
- (void)dealloc {
	static volatile int32_t directDeallocCount = 0;

	if (OSAtomicIncrement32(&directDeallocCount) >= DEALLOC_OVERFLOW_GUARD) {
		OSAtomicAdd32(-DEALLOC_OVERFLOW_GUARD, &directDeallocCount);

		// 将tail放入自动释放池，防止递归。
		__autoreleasing RACSequence *tail __attribute__((unused)) = _tail;
	}
	
	_tail = nil;
}

#pragma mark RACSequence

/**
 * @brief 获取序列的head。
 * @return 返回head元素。
 * @discussion 支持依赖注入和惰性求值，线程安全。
 * @实现原理 分为两种情况：有依赖和无依赖，均在@synchronized(self)下求值并缓存。
 */
- (id)head {
	@synchronized (self) {
		id untypedHeadBlock = self.headBlock;
		if (untypedHeadBlock == nil) return _head;

		if (self.hasDependency) {
			if (self.dependencyBlock != nil) {
				_dependency = self.dependencyBlock();
				self.dependencyBlock = nil;
			}

			id (^headBlock)(id) = untypedHeadBlock;
			_head = headBlock(_dependency);
		} else {
			id (^headBlock)(void) = untypedHeadBlock;
			_head = headBlock();
		}

		self.headBlock = nil;
		return _head;
	}
}

/**
 * @brief 获取序列的tail。
 * @return 返回tail序列。
 * @discussion 支持依赖注入和惰性求值，线程安全。
 * @实现原理 分为两种情况：有依赖和无依赖，均在@synchronized(self)下求值并缓存。
 */
- (RACSequence *)tail {
	@synchronized (self) {
		id untypedTailBlock = self.tailBlock;
		if (untypedTailBlock == nil) return _tail;

		if (self.hasDependency) {
			if (self.dependencyBlock != nil) {
				_dependency = self.dependencyBlock();
				self.dependencyBlock = nil;
			}

			RACSequence * (^tailBlock)(id) = untypedTailBlock;
			_tail = tailBlock(_dependency);
		} else {
			RACSequence * (^tailBlock)(void) = untypedTailBlock;
			_tail = tailBlock();
		}

		if (_tail.name == nil) _tail.name = self.name;

		self.tailBlock = nil;
		return _tail;
	}
}

#pragma mark NSObject

/**
 * @brief 返回对象描述信息。
 * @return 包含类名、指针、name、head、tail的字符串。
 */
- (NSString *)description {
	id head = @"(unresolved)";
	id tail = @"(unresolved)";

	@synchronized (self) {
		if (self.headBlock == nil) head = _head;
		if (self.tailBlock == nil) {
			tail = _tail;
			if (tail == self) tail = @"(self)";
		}
	}

	return [NSString stringWithFormat:@"<%@: %p>{ name = %@, head = %@, tail = %@ }", self.class, self, self.name, head, tail];
}

@end
