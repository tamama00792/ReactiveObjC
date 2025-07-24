//
//  RACSubscriber.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/1/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubscriber.h"
#import "RACSubscriber+Private.h"
#import <ReactiveObjC/EXTScope.h>
#import "RACCompoundDisposable.h"

@interface RACSubscriber ()

// 这些回调只应在对 self 加锁的情况下访问。
@property (nonatomic, copy) void (^next)(id value); // 处理 sendNext: 事件的回调
@property (nonatomic, copy) void (^error)(NSError *error); // 处理 sendError: 事件的回调
@property (nonatomic, copy) void (^completed)(void); // 处理 sendCompleted 事件的回调

@property (nonatomic, strong, readonly) RACCompoundDisposable *disposable; // 管理资源释放的复合 Disposable

@end

@implementation RACSubscriber

#pragma mark Lifecycle

// 工厂方法，创建一个带有 next、error、completed 回调的订阅者对象
+ (instancetype)subscriberWithNext:(void (^)(id x))next error:(void (^)(NSError *error))error completed:(void (^)(void))completed {
	RACSubscriber *subscriber = [[self alloc] init];

	subscriber->_next = [next copy];
	subscriber->_error = [error copy];
	subscriber->_completed = [completed copy];

	return subscriber;
}

// 初始化方法，设置资源释放逻辑
- (instancetype)init {
	self = [super init];

	@unsafeify(self);

	// 创建一个 Disposable，当订阅者释放时自动清理回调，防止循环引用
	RACDisposable *selfDisposable = [RACDisposable disposableWithBlock:^{
		@strongify(self);

		@synchronized (self) {
			self.next = nil;
			self.error = nil;
			self.completed = nil;
		}
	}];

	// 创建复合 Disposable 并添加自清理 Disposable
	_disposable = [RACCompoundDisposable compoundDisposable];
	[_disposable addDisposable:selfDisposable];

	return self;
}

// 析构方法，释放所有资源
- (void)dealloc {
	[self.disposable dispose];
}

#pragma mark RACSubscriber

// 发送下一个值给订阅者
- (void)sendNext:(id)value {
	@synchronized (self) {
		// 拷贝回调，保证线程安全
		void (^nextBlock)(id) = [self.next copy];
		if (nextBlock == nil) return;

		nextBlock(value);
	}
}

// 发送错误事件并释放资源
- (void)sendError:(NSError *)e {
	@synchronized (self) {
		void (^errorBlock)(NSError *) = [self.error copy];
		// 发送错误时，先释放所有资源
		[self.disposable dispose];

		if (errorBlock == nil) return;
		errorBlock(e);
	}
}

// 发送完成事件并释放资源
- (void)sendCompleted {
	@synchronized (self) {
		void (^completedBlock)(void) = [self.completed copy];
		// 发送完成时，先释放所有资源
		[self.disposable dispose];

		if (completedBlock == nil) return;
		completedBlock();
	}
}

// 订阅时传入外部 Disposable，统一管理资源释放
- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)otherDisposable {
	if (otherDisposable.disposed) return;

	RACCompoundDisposable *selfDisposable = self.disposable;
	[selfDisposable addDisposable:otherDisposable];

	@unsafeify(otherDisposable);

	// 当外部 Disposable 终止时，从自身的复合 Disposable 中移除，避免内存泄漏
	[otherDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		@strongify(otherDisposable);
		[selfDisposable removeDisposable:otherDisposable];
	}]];
}

@end
