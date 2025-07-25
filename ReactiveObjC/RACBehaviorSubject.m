//
//  RACBehaviorSubject.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACBehaviorSubject.h"
#import "RACDisposable.h"
#import "RACScheduler+Private.h"

/**
 * @class RACBehaviorSubject
 * @brief 带有当前值缓存的信号体，订阅者可立即收到最新值。
 * @discussion 该类常用于需要保存并立即推送最新值给新订阅者的场景，类似于Rx中的BehaviorSubject。
 */
@interface RACBehaviorSubject<ValueType> ()

/**
 * @brief 当前缓存的值。
 * @discussion 该属性仅应在@synchronized(self)保护下访问，用于保存最近一次sendNext:推送的值。
 */
@property (nonatomic, strong) ValueType currentValue;

@end

@implementation RACBehaviorSubject

#pragma mark Lifecycle

/**
 * @brief 创建一个带有默认值的RACBehaviorSubject实例。
 * @param value 默认值。
 * @return 返回一个RACBehaviorSubject对象。
 * @discussion 用于初始化时指定初始值，后续订阅者会立即收到该值。
 * @实现原理 先创建subject对象，再设置currentValue。
 */
+ (instancetype)behaviorSubjectWithDefaultValue:(id)value {
	RACBehaviorSubject *subject = [self subject];
	subject.currentValue = value;
	return subject;
}

#pragma mark RACSignal

/**
 * @brief 订阅信号。
 * @param subscriber 订阅者对象。
 * @return 返回一个RACDisposable对象用于取消订阅。
 * @discussion 新订阅者会立即收到当前缓存的值。
 * @实现原理 分为两部分：
 * 1. 调用父类的subscribe:方法，建立订阅关系。
 * 2. 在订阅调度器上异步推送currentValue给新订阅者。
 * 3. 返回一个组合的disposable，确保资源释放。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	RACDisposable *subscriptionDisposable = [super subscribe:subscriber];

	// 2. 异步推送当前值
	RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
		@synchronized (self) {
			[subscriber sendNext:self.currentValue];
		}
	}];
	
	// 3. 返回组合disposable
	return [RACDisposable disposableWithBlock:^{
		[subscriptionDisposable dispose];
		[schedulingDisposable dispose];
	}];
}

#pragma mark RACSubscriber

/**
 * @brief 推送新值给所有订阅者，并更新当前缓存值。
 * @param value 新值。
 * @discussion 每次调用会更新currentValue，并通过父类方法推送给所有订阅者。
 * @实现原理 在@synchronized(self)保护下，先更新currentValue，再调用父类sendNext:。
 */
- (void)sendNext:(id)value {
	@synchronized (self) {
		self.currentValue = value;
		[super sendNext:value];
	}
}

@end
