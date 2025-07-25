//
//  RACDisposable.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACDisposable.h"
#import "RACScopedDisposable.h"
#import <libkern/OSAtomic.h>

/**
 * @class RACDisposable
 * @brief 用于封装资源释放逻辑的对象。
 * @discussion 常用于信号订阅、资源管理等场景，支持线程安全的一次性释放。
 */
@interface RACDisposable () {
	// 保存释放逻辑的block指针，或self指针（无释放逻辑），或NULL（已释放）。
	// 仅允许原子操作访问。
	void * volatile _disposeBlock;
}

@end

@implementation RACDisposable

#pragma mark Properties

/**
 * @brief 判断当前对象是否已被释放。
 * @return YES表示已释放，NO表示未释放。
 */
- (BOOL)isDisposed {
	return _disposeBlock == NULL;
}

#pragma mark Lifecycle

/**
 * @brief 默认初始化方法。
 * @return 返回新实例。
 * @discussion 初始化时将_disposeBlock指向self，表示无释放逻辑。
 */
- (instancetype)init {
	self = [super init];

	_disposeBlock = (__bridge void *)self;
	OSMemoryBarrier();

	return self;
}

/**
 * @brief 以block初始化RACDisposable。
 * @param block 释放时执行的block。
 * @return 返回新实例。
 */
- (instancetype)initWithBlock:(void (^)(void))block {
	NSCParameterAssert(block != nil);

	self = [super init];

	_disposeBlock = (void *)CFBridgingRetain([block copy]); 
	OSMemoryBarrier();

	return self;
}

/**
 * @brief 以block快速创建RACDisposable。
 * @param block 释放时执行的block。
 * @return 返回新实例。
 */
+ (instancetype)disposableWithBlock:(void (^)(void))block {
	return [(RACDisposable *)[self alloc] initWithBlock:block];
}

/**
 * @brief 析构函数，释放block资源。
 */
- (void)dealloc {
	if (_disposeBlock == NULL || _disposeBlock == (__bridge void *)self) return;

	CFRelease(_disposeBlock);
	_disposeBlock = NULL;
}

#pragma mark Disposal

/**
 * @brief 执行释放逻辑。
 * @discussion 线程安全，保证只执行一次释放逻辑。
 */
- (void)dispose {
	void (^disposeBlock)(void) = NULL;

	while (YES) {
		void *blockPtr = _disposeBlock;
		if (OSAtomicCompareAndSwapPtrBarrier(blockPtr, NULL, &_disposeBlock)) {
			if (blockPtr != (__bridge void *)self) {
				disposeBlock = CFBridgingRelease(blockPtr);
			}

			break;
		}
	}

	if (disposeBlock != nil) disposeBlock();
}

#pragma mark Scoped Disposables

/**
 * @brief 转为作用域自动释放的disposable。
 * @return 返回RACScopedDisposable对象。
 */
- (RACScopedDisposable *)asScopedDisposable {
	return [RACScopedDisposable scopedDisposableWithDisposable:self];
}

@end
