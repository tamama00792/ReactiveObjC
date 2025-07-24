//
//  RACSubject.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/9/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubject.h"
#import <ReactiveObjC/EXTScope.h>
#import "RACCompoundDisposable.h"
#import "RACPassthroughSubscriber.h"

// RACSubject 是 ReactiveObjC 中的热信号（Hot Signal）实现，允许手动发送事件给所有订阅者。
// 该类实现了 RACSubscriber 协议，可以主动发送 next、error、completed 事件。
@interface RACSubject ()

// 当前所有订阅者的集合。
// 仅在同步 self 时使用。
@property (nonatomic, strong, readonly) NSMutableArray *subscribers;

// 记录当前 subject 对其他信号的所有订阅。
@property (nonatomic, strong, readonly) RACCompoundDisposable *disposable;

// 枚举所有订阅者，并对每个订阅者执行 block。
- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block;

@end

@implementation RACSubject

#pragma mark Lifecycle

// 创建并返回一个新的 RACSubject 实例。
// 返回值：RACSubject 实例。
// 原理：直接调用 init 方法。
// 用于外部创建 subject。
//
// 示例：RACSubject *subject = [RACSubject subject];
//
// 英文注释保留。
//
//
//
+ (instancetype)subject {
	return [[self alloc] init];
}

// 初始化方法，创建订阅者数组和复合可释放对象。
// _disposable 用于统一管理所有订阅的释放。
// _subscribers 用于存储所有当前的订阅者。
- (instancetype)init {
	self = [super init];
	if (self == nil) return nil;

	_disposable = [RACCompoundDisposable compoundDisposable];
	_subscribers = [[NSMutableArray alloc] initWithCapacity:1];
	
	return self;
}

// 析构方法，释放所有资源，通知所有订阅者已完成。
- (void)dealloc {
	[self.disposable dispose];
}

#pragma mark Subscription

// 订阅当前 subject。
// 参数 subscriber：订阅者对象，必须实现 RACSubscriber 协议。
// 返回值：RACDisposable，可用于取消订阅。
// 实现原理：
// 1. 创建一个复合可释放对象 disposable。
// 2. 用 RACPassthroughSubscriber 包装原始 subscriber，便于统一管理。
// 3. 将 subscriber 加入 subscribers 数组（线程安全）。
// 4. 当 disposable 被释放时，从 subscribers 数组中移除对应的 subscriber。
// 5. 返回 disposable，外部可通过其取消订阅。
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCParameterAssert(subscriber != nil);

	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
	subscriber = [[RACPassthroughSubscriber alloc] initWithSubscriber:subscriber signal:self disposable:disposable];

	NSMutableArray *subscribers = self.subscribers;
	@synchronized (subscribers) {
		[subscribers addObject:subscriber];
	}
	
	[disposable addDisposable:[RACDisposable disposableWithBlock:^{ 
		@synchronized (subscribers) {
			// Since newer subscribers are generally shorter-lived, search
			// starting from the end of the list.
			NSUInteger index = [subscribers indexOfObjectWithOptions:NSEnumerationReverse passingTest:^ BOOL (id<RACSubscriber> obj, NSUInteger index, BOOL *stop) {
				return obj == subscriber;
			}];

			if (index != NSNotFound) [subscribers removeObjectAtIndex:index];
		}
	}]];

	return disposable;
}

// 枚举所有当前订阅者，并对每个订阅者执行 block。
// 参数 block：对每个订阅者执行的操作。
// 实现原理：
// 1. 线程安全地复制 subscribers 数组。
// 2. 遍历副本，依次执行 block。
- (void)enumerateSubscribersUsingBlock:(void (^)(id<RACSubscriber> subscriber))block {
	NSArray *subscribers;
	@synchronized (self.subscribers) {
		subscribers = [self.subscribers copy];
	}

	for (id<RACSubscriber> subscriber in subscribers) {
		block(subscriber);
	}
}

#pragma mark RACSubscriber

// 发送 next 事件给所有订阅者。
// 参数 value：要发送的数据。
// 实现原理：遍历所有订阅者，调用 sendNext。
- (void)sendNext:(id)value {
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendNext:value];
	}];
}

// 发送 error 事件给所有订阅者，并释放所有资源。
// 参数 error：错误对象。
// 实现原理：
// 1. 先释放所有订阅资源。
// 2. 遍历所有订阅者，调用 sendError。
- (void)sendError:(NSError *)error {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendError:error];
	}];
}

// 发送 completed 事件给所有订阅者，并释放所有资源。
// 实现原理：
// 1. 先释放所有订阅资源。
// 2. 遍历所有订阅者，调用 sendCompleted。
- (void)sendCompleted {
	[self.disposable dispose];
	
	[self enumerateSubscribersUsingBlock:^(id<RACSubscriber> subscriber) {
		[subscriber sendCompleted];
	}];
}

// 记录外部信号的订阅 disposable，便于统一管理和释放。
// 参数 d：外部信号的 disposable。
// 实现原理：
// 1. 将 d 加入 subject 的 disposable。
// 2. 当 d 被释放时，从 subject 的 disposable 中移除。
- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)d {
	if (d.disposed) return;
	[self.disposable addDisposable:d];

	@weakify(self, d);
	[d addDisposable:[RACDisposable disposableWithBlock:^{ 
		@strongify(self, d);
		[self.disposable removeDisposable:d];
	}]];
}

@end
