//
//  RACDynamicSignal.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-10-10.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACDynamicSignal.h"
#import <ReactiveObjC/EXTScope.h>
#import "RACCompoundDisposable.h"
#import "RACPassthroughSubscriber.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"
#import <libkern/OSAtomic.h>

/**
 * @class RACDynamicSignal
 * @brief 支持自定义订阅逻辑的信号类。
 * @discussion 适用于需要自定义订阅行为的场景，如手动管理订阅、资源等。
 */
@interface RACDynamicSignal ()

/**
 * @brief 每个订阅者调用的订阅回调block。
 * @discussion 订阅时会调用该block，返回一个RACDisposable用于资源释放。
 */
@property (nonatomic, copy, readonly) RACDisposable * (^didSubscribe)(id<RACSubscriber> subscriber);

@end

@implementation RACDynamicSignal

#pragma mark Lifecycle

/**
 * @brief 创建支持自定义订阅逻辑的信号。
 * @param didSubscribe 订阅回调block，参数为订阅者，返回RACDisposable。
 * @return 返回RACDynamicSignal对象。
 * @discussion 订阅时会调用didSubscribe，适合自定义信号源。
 */
+ (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe {
	RACDynamicSignal *signal = [[self alloc] init];
	signal->_didSubscribe = [didSubscribe copy];
	return [signal setNameWithFormat:@"+createSignal:"];
}

#pragma mark Managing Subscribers

/**
 * @brief 订阅信号。
 * @param subscriber 订阅者对象。
 * @return 返回RACDisposable用于取消订阅。
 * @discussion 内部会包装订阅者，并在订阅调度器上异步执行订阅逻辑。
 * @实现原理 分为三步：
 * 1. 创建RACCompoundDisposable用于统一管理资源。
 * 2. 包装订阅者，确保信号和资源绑定。
 * 3. 调用didSubscribe block并调度执行，返回disposable。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];

	if (self.didSubscribe != NULL) {
		RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
			RACDisposable *innerDisposable = self.didSubscribe(subscriber);
			[disposable addDisposable:innerDisposable];
		}];

		[disposable addDisposable:schedulingDisposable];
	}
	
	return disposable;
}

@end
