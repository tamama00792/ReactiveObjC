//
//  RACErrorSignal.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACErrorSignal.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"

/**
 * @class RACErrorSignal
 * @brief 表示只发送错误事件的信号。
 * @discussion 常用于需要立即失败的信号场景。
 */
@interface RACErrorSignal ()

/**
 * @brief 订阅时发送的错误对象。
 */
@property (nonatomic, strong, readonly) NSError *error;

@end

@implementation RACErrorSignal

#pragma mark Lifecycle

/**
 * @brief 创建只发送错误的信号。
 * @param error 需要发送的错误对象。
 * @return 返回RACErrorSignal对象。
 */
+ (RACSignal *)error:(NSError *)error {
	RACErrorSignal *signal = [[self alloc] init];
	signal->_error = error;

#ifdef DEBUG
	[signal setNameWithFormat:@"+error: %@", error];
#else
	signal.name = @"+error:";
#endif

	return signal;
}

#pragma mark Subscription

/**
 * @brief 订阅错误信号，立即发送错误事件。
 * @param subscriber 订阅者。
 * @return 返回RACDisposable。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

	return [RACScheduler.subscriptionScheduler schedule:^{
		[subscriber sendError:self.error];
	}];
}

@end
