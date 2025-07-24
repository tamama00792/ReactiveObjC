//
//  RACSerialDisposable.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-07-22.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACSerialDisposable.h"
#import <pthread/pthread.h>

@interface RACSerialDisposable () {
	// The receiver's `disposable`. This variable must only be referenced while
	// _mutex is held.
	RACDisposable * _disposable;

	// YES if the receiver has been disposed. This variable must only be accessed
	// while _mutex is held.
	BOOL _disposed;

	// A mutex to protect access to _disposable and _disposed.
	pthread_mutex_t _mutex;
}

@end

@implementation RACSerialDisposable

//  RACSerialDisposable 是一个串行可释放对象，内部通过互斥锁保证线程安全，确保同一时刻只有一个可释放对象被持有。
//  其主要作用是管理一个可变的 RACDisposable 实例，并在自身被释放时自动释放内部持有的 disposable。

#pragma mark Properties

/**
 判断当前对象是否已被释放。
 原理：通过互斥锁保护 _disposed 变量，保证多线程下的可见性和一致性。
 实现：加锁后读取 _disposed 状态，解锁后返回。
*/
- (BOOL)isDisposed {
	pthread_mutex_lock(&_mutex);
	const BOOL disposed = _disposed;
	pthread_mutex_unlock(&_mutex);

	return disposed;
}

/**
 获取当前持有的 disposable。
 原理：通过互斥锁保护 _disposable 变量，保证线程安全。
 实现：加锁后读取 _disposable，解锁后返回。
*/
- (RACDisposable *)disposable {
	pthread_mutex_lock(&_mutex);
	RACDisposable * const result = _disposable;
	pthread_mutex_unlock(&_mutex);

	return result;
}

/**
 设置新的 disposable。
 原理：通过 swapInDisposable 方法原子性地替换内部 disposable，保证线程安全。
 实现：直接调用 swapInDisposable: 方法。
*/
- (void)setDisposable:(RACDisposable *)disposable {
	[self swapInDisposable:disposable];
}

#pragma mark Lifecycle

/**
 工厂方法，创建并初始化一个 RACSerialDisposable，并设置初始的 disposable。
 原理：先分配并初始化对象，再赋值 disposable 属性。
*/
+ (instancetype)serialDisposableWithDisposable:(RACDisposable *)disposable {
	RACSerialDisposable *serialDisposable = [[self alloc] init];
	serialDisposable.disposable = disposable;
	return serialDisposable;
}

/**
 初始化方法，初始化互斥锁。
 原理：调用 pthread_mutex_init 初始化互斥锁，保证后续对内部状态的访问线程安全。
*/
- (instancetype)init {
	self = [super init];
	if (self == nil) return nil;

	const int result __attribute__((unused)) = pthread_mutex_init(&_mutex, NULL);
	NSCAssert(0 == result, @"Failed to initialize mutex with error %d", result);

	return self;
}

/**
 以 block 方式初始化，内部会创建一个带 block 的 RACDisposable。
 原理：先调用 init 初始化互斥锁，再将 block 封装为 RACDisposable 赋值给 disposable 属性。
*/
- (instancetype)initWithBlock:(void (^)(void))block {
	self = [self init];
	if (self == nil) return nil;

	self.disposable = [RACDisposable disposableWithBlock:block];

	return self;
}

/**
 析构方法，销毁互斥锁。
 原理：调用 pthread_mutex_destroy 释放互斥锁资源，防止内存泄漏。
*/
- (void)dealloc {
	const int result __attribute__((unused)) = pthread_mutex_destroy(&_mutex);
	NSCAssert(0 == result, @"Failed to destroy mutex with error %d", result);
}

#pragma mark Inner Disposable

/**
 原子性地替换内部的 disposable，并返回旧的 disposable。
 原理：加锁后判断对象是否已被释放，若未释放则替换 _disposable 并返回旧值，若已释放则立即释放新传入的 disposable。
 实现：保证替换和释放操作的原子性，防止竞态条件。
*/
- (RACDisposable *)swapInDisposable:(RACDisposable *)newDisposable {
	RACDisposable *existingDisposable;
	BOOL alreadyDisposed;

	pthread_mutex_lock(&_mutex);
	alreadyDisposed = _disposed;
	if (!alreadyDisposed) {
		existingDisposable = _disposable;
		_disposable = newDisposable;
	}
	pthread_mutex_unlock(&_mutex);

	if (alreadyDisposed) {
		[newDisposable dispose];
		return nil;
	}

	return existingDisposable;
}

#pragma mark Disposal

/**
 释放当前对象，并释放内部持有的 disposable。
 原理：加锁后将 _disposed 置为 YES，并清空 _disposable，解锁后释放原有的 disposable。
 实现：保证 dispose 操作的幂等性和线程安全。
*/
- (void)dispose {
	RACDisposable *existingDisposable;

	pthread_mutex_lock(&_mutex);
	if (!_disposed) {
		existingDisposable = _disposable;
		_disposed = YES;
		_disposable = nil;
	}
	pthread_mutex_unlock(&_mutex);
	
	[existingDisposable dispose];
}

@end
