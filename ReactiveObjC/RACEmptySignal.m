//
//  RACEmptySignal.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACEmptySignal.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"

/**
 * @class RACEmptySignal
 * @brief 表示不发送任何值，仅发送完成事件的信号。
 * @discussion 常用于需要立即完成的信号场景。
 */
@implementation RACEmptySignal

#pragma mark Properties

/**
 * @brief 设置信号名称，仅DEBUG模式下可自定义。
 * @param name 信号名称。
 */
// 仅允许DEBUG下自定义名称，release下为单例
- (void)setName:(NSString *)name {
#ifdef DEBUG
	[super setName:name];
#endif
}

/**
 * @brief 获取信号名称。
 * @return DEBUG下返回super.name，release下返回+empty。
 */
- (NSString *)name {
#ifdef DEBUG
	return super.name;
#else
	return @"+empty";
#endif
}

#pragma mark Lifecycle

/**
 * @brief 获取空信号单例。
 * @return 返回RACEmptySignal对象。
 * @discussion DEBUG下每次新建，release下全局单例。
 */
+ (RACSignal *)empty {
#ifdef DEBUG
	// Create multiple instances of this class in DEBUG so users can set custom
	// names on each.
	return [[[self alloc] init] setNameWithFormat:@"+empty"];
#else
	static id singleton;
	static dispatch_once_t pred;

	dispatch_once(&pred, ^{
		singleton = [[self alloc] init];
	});

	return singleton;
#endif
}

#pragma mark Subscription

/**
 * @brief 订阅空信号，立即发送完成事件。
 * @param subscriber 订阅者。
 * @return 返回RACDisposable。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

	return [RACScheduler.subscriptionScheduler schedule:^{
		[subscriber sendCompleted];
	}];
}

@end
