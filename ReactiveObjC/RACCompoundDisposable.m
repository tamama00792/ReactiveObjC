//
//  RACCompoundDisposable.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//
//  本文件实现了RACCompoundDisposable类，用于管理多个RACDisposable对象的统一释放。
//  其内部通过互斥锁保证线程安全，并采用内联数组与动态数组结合的方式优化性能和内存使用。
//

#import "RACCompoundDisposable.h"
#import "RACCompoundDisposableProvider.h"
#import <pthread/pthread.h>

// The number of child disposables for which space will be reserved directly in
// `RACCompoundDisposable`.
//
// This number has been empirically determined to provide a good tradeoff
// between performance, memory usage, and `RACCompoundDisposable` instance size
// in a moderately complex GUI application.
//
// Profile any change!
#define RACCompoundDisposableInlineCount 2

// 用于创建一个可变的CFArray，存储disposable对象，采用指针比较以提升性能。
static CFMutableArrayRef RACCreateDisposablesArray(void) {
	// Compare values using only pointer equality.
	CFArrayCallBacks callbacks = kCFTypeArrayCallBacks;
	callbacks.equal = NULL;

	return CFArrayCreateMutable(NULL, 0, &callbacks);
}

@interface RACCompoundDisposable () {
	// Used for synchronization.
	pthread_mutex_t _mutex;

	#if RACCompoundDisposableInlineCount
	// A fast array to the first N of the receiver's disposables.
	//
	// Once this is full, `_disposables` will be created and used for additional
	// disposables.
	//
	// This array should only be manipulated while _mutex is held.
	RACDisposable *_inlineDisposables[RACCompoundDisposableInlineCount];
	#endif

	// Contains the receiver's disposables.
	//
	// This array should only be manipulated while _mutex is held. If
	// `_disposed` is YES, this may be NULL.
	CFMutableArrayRef _disposables;

	// Whether the receiver has already been disposed.
	//
	// This ivar should only be accessed while _mutex is held.
	BOOL _disposed;
}

@end

@implementation RACCompoundDisposable

#pragma mark Properties

// 判断当前RACCompoundDisposable是否已被释放。
// 通过加锁读取_disposed标志，保证线程安全。
- (BOOL)isDisposed {
	pthread_mutex_lock(&_mutex);
	BOOL disposed = _disposed;
	pthread_mutex_unlock(&_mutex);

	return disposed;
}

#pragma mark Lifecycle

// 创建一个空的RACCompoundDisposable实例。
+ (instancetype)compoundDisposable {
	return [[self alloc] initWithDisposables:nil];
}

// 使用指定的disposables数组创建RACCompoundDisposable实例。
+ (instancetype)compoundDisposableWithDisposables:(NSArray *)disposables {
	return [[self alloc] initWithDisposables:disposables];
}

// 初始化方法，初始化互斥锁。
- (instancetype)init {
	self = [super init];

	// 初始化互斥锁，保证多线程下的安全。
	const int result __attribute__((unused)) = pthread_mutex_init(&_mutex, NULL);
	NSCAssert(0 == result, @"Failed to initialize mutex with error %d.", result);

	return self;
}

// 使用传入的disposables数组初始化实例。
// 前RACCompoundDisposableInlineCount个对象存储在内联数组，剩余的存储在动态数组中。
- (instancetype)initWithDisposables:(NSArray *)otherDisposables {
	self = [self init];

	#if RACCompoundDisposableInlineCount
	[otherDisposables enumerateObjectsUsingBlock:^(RACDisposable *disposable, NSUInteger index, BOOL *stop) {
		self->_inlineDisposables[index] = disposable;

		// 达到内联数组上限后停止。
		if (index == RACCompoundDisposableInlineCount - 1) *stop = YES;
	}];
	#endif

	if (otherDisposables.count > RACCompoundDisposableInlineCount) {
		_disposables = RACCreateDisposablesArray();

		// 将多余的disposable存入动态数组。
		CFRange range = CFRangeMake(RACCompoundDisposableInlineCount, (CFIndex)otherDisposables.count - RACCompoundDisposableInlineCount);
		CFArrayAppendArray(_disposables, (__bridge CFArrayRef)otherDisposables, range);
	}

	return self;
}

// 通过block创建一个只包含一个disposable的RACCompoundDisposable。
- (instancetype)initWithBlock:(void (^)(void))block {
	RACDisposable *disposable = [RACDisposable disposableWithBlock:block];
	return [self initWithDisposables:@[ disposable ]];
}

// 析构函数，释放内联数组、动态数组和互斥锁。
- (void)dealloc {
	#if RACCompoundDisposableInlineCount
	for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
		_inlineDisposables[i] = nil;
	}
	#endif

	if (_disposables != NULL) {
		CFRelease(_disposables);
		_disposables = NULL;
	}

	const int result __attribute__((unused)) = pthread_mutex_destroy(&_mutex);
	NSCAssert(0 == result, @"Failed to destroy mutex with error %d.", result);
}

#pragma mark Addition and Removal

// 添加一个disposable到当前对象。
// 若已被释放，则立即释放传入的disposable。
// 否则优先存入内联数组，满后存入动态数组。
- (void)addDisposable:(RACDisposable *)disposable {
	NSCParameterAssert(disposable != self);
	if (disposable == nil || disposable.disposed) return;

	BOOL shouldDispose = NO;

	pthread_mutex_lock(&_mutex);
	{
		if (_disposed) {
			shouldDispose = YES;
		} else {
			#if RACCompoundDisposableInlineCount
			for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
				if (_inlineDisposables[i] == nil) {
					_inlineDisposables[i] = disposable;
					goto foundSlot;
				}
			}
			#endif

			if (_disposables == NULL) _disposables = RACCreateDisposablesArray();
			CFArrayAppendValue(_disposables, (__bridge void *)disposable);

			// 这里可插入调试钩子，追踪添加操作。

		#if RACCompoundDisposableInlineCount
		foundSlot:;
		#endif
		}
	}
	pthread_mutex_unlock(&_mutex);

	// 若已被释放，则在锁外释放传入的disposable，避免递归死锁。
	if (shouldDispose) [disposable dispose];
}

// 从当前对象移除指定的disposable。
// 仅在未释放时有效，优先从内联数组移除，再从动态数组移除。
- (void)removeDisposable:(RACDisposable *)disposable {
	if (disposable == nil) return;

	pthread_mutex_lock(&_mutex);
	{
		if (!_disposed) {
			#if RACCompoundDisposableInlineCount
			for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
				if (_inlineDisposables[i] == disposable) _inlineDisposables[i] = nil;
			}
			#endif

			if (_disposables != NULL) {
				CFIndex count = CFArrayGetCount(_disposables);
				for (CFIndex i = count - 1; i >= 0; i--) {
					const void *item = CFArrayGetValueAtIndex(_disposables, i);
					if (item == (__bridge void *)disposable) {
						CFArrayRemoveValueAtIndex(_disposables, i);
					}
				}

				// 这里可插入调试钩子，追踪移除操作。
			}
		}
	}
	pthread_mutex_unlock(&_mutex);
}

#pragma mark RACDisposable

// 静态函数，释放传入的disposable对象。
static void disposeEach(const void *value, void *context) {
	RACDisposable *disposable = (__bridge id)value;
	[disposable dispose];
}

// 释放当前RACCompoundDisposable管理的所有disposable。
// 先加锁设置_disposed标志，并取出所有disposable副本，随后在锁外依次释放，避免递归死锁。
- (void)dispose {
	#if RACCompoundDisposableInlineCount
	RACDisposable *inlineCopy[RACCompoundDisposableInlineCount];
	#endif

	CFArrayRef remainingDisposables = NULL;

	pthread_mutex_lock(&_mutex);
	{
		_disposed = YES;

		#if RACCompoundDisposableInlineCount
		for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
			inlineCopy[i] = _inlineDisposables[i];
			_inlineDisposables[i] = nil;
		}
		#endif

		remainingDisposables = _disposables;
		_disposables = NULL;
	}
	pthread_mutex_unlock(&_mutex);

	#if RACCompoundDisposableInlineCount
	// 在锁外释放内联数组中的disposable，防止递归死锁。
	for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
		[inlineCopy[i] dispose];
	}
	#endif

	if (remainingDisposables == NULL) return;

	CFIndex count = CFArrayGetCount(remainingDisposables);
	CFArrayApplyFunction(remainingDisposables, CFRangeMake(0, count), &disposeEach, NULL);
	CFRelease(remainingDisposables);
}

@end
