//
//  RACEmptySequence.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "RACEmptySequence.h"

/**
 * @class RACEmptySequence
 * @brief 表示空序列的单例类。
 * @discussion 常用于链式操作的终止条件，或表示无元素的序列。
 */
@implementation RACEmptySequence

#pragma mark Lifecycle

/**
 * @brief 获取空序列单例。
 * @return 返回RACEmptySequence单例。
 * @discussion 使用dispatch_once保证全局唯一。
 */
+ (instancetype)empty {
	static id singleton;
	static dispatch_once_t pred;

	dispatch_once(&pred, ^{
		singleton = [[self alloc] init];
	});

	return singleton;
}

#pragma mark RACSequence

/**
 * @brief 空序列的head始终为nil。
 * @return nil。
 */
- (id)head {
	return nil;
}

/**
 * @brief 空序列的tail始终为nil。
 * @return nil。
 */
- (RACSequence *)tail {
	return nil;
}

/**
 * @brief 空序列bind时直接返回passthroughSequence或self。
 * @param bindBlock 绑定block。
 * @param passthroughSequence 透传序列。
 * @return passthroughSequence或self。
 */
- (RACSequence *)bind:(RACStreamBindBlock)bindBlock passingThroughValuesFromSequence:(RACSequence *)passthroughSequence {
	return passthroughSequence ?: self;
}

#pragma mark NSCoding

/**
 * @brief 编码时返回自身类。
 * @return 当前类。
 */
- (Class)classForCoder {
	// Empty sequences should be encoded as themselves, not array sequences.
	return self.class;
}

/**
 * @brief 解码时返回单例。
 * @param coder 解码器。
 * @return 单例对象。
 */
- (instancetype)initWithCoder:(NSCoder *)coder {
	// Return the singleton.
	return self.class.empty;
}

/**
 * @brief 编码空实现。
 * @param coder 编码器。
 */
- (void)encodeWithCoder:(NSCoder *)coder {
}

#pragma mark NSObject

/**
 * @brief 返回对象描述信息。
 * @return 包含类名、指针、name的字符串。
 */
- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p>{ name = %@ }", self.class, self, self.name];
}

/**
 * @brief 返回对象哈希值。
 * @return 指针哈希。
 */
- (NSUInteger)hash {
	// This hash isn't ideal, but it's better than -[RACSequence hash], which
	// would just be zero because we have no head.
	return (NSUInteger)(__bridge void *)self;
}

/**
 * @brief 判断是否与另一个序列相等。
 * @param seq 另一个序列。
 * @return YES表示相等，NO表示不等。
 */
- (BOOL)isEqual:(RACSequence *)seq {
	return (self == seq);
}

@end
