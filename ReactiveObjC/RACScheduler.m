//
//  RACScheduler.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 4/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//
//  本文件实现了RACScheduler调度器的核心逻辑，负责任务的调度、递归调度、主线程/后台线程调度等功能。
//
//  主要原理：
//  - 通过不同的子类实现不同的调度策略（如立即、主线程、全局队列等）。
//  - 通过线程字典保存当前调度器，实现任务嵌套调度时的上下文切换。
//  - 支持递归调度和延迟调度。
//

#import "RACScheduler.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACImmediateScheduler.h"
#import "RACScheduler+Private.h"
#import "RACSubscriptionScheduler.h"
#import "RACTargetQueueScheduler.h"

// 当前线程调度器的线程字典key。
NSString * const RACSchedulerCurrentSchedulerKey = @"RACSchedulerCurrentSchedulerKey";

/**
 * @class RACScheduler
 * @brief ReactiveObjC的调度器基类，负责任务调度、递归调度、主线程/后台线程调度等。
 * @discussion 通过不同子类实现不同调度策略，支持递归、延迟、定时等多种调度方式。
 */
@interface RACScheduler ()
/**
 * @brief 调度器名称。
 */
@property (nonatomic, readonly, copy) NSString *name;
@end

@implementation RACScheduler

#pragma mark NSObject

/**
 * @brief 返回调度器的描述信息。
 * @return 包含类名、内存地址和调度器名称的字符串。
 */
- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p> %@", self.class, self, self.name];
}

#pragma mark Initializers

/**
 * @brief 初始化方法，根据传入的name参数设置调度器名称。
 * @param name 调度器名称。
 * @return 返回RACScheduler实例。
 * @discussion 若name为nil，则自动生成一个匿名调度器名称。
 */
- (instancetype)initWithName:(NSString *)name {
	self = [super init];

	if (name == nil) {
		_name = [NSString stringWithFormat:@"org.reactivecocoa.ReactiveObjC.%@.anonymousScheduler", self.class];
	} else {
		_name = [name copy];
	}

	return self;
}

#pragma mark Schedulers

/**
 * @brief 获取立即执行的调度器（单例）。
 * @return 返回RACImmediateScheduler实例。
 * @discussion 只会初始化一次，始终返回同一个RACImmediateScheduler实例。
 */
+ (RACScheduler *)immediateScheduler {
	static dispatch_once_t onceToken;
	static RACScheduler *immediateScheduler;
	dispatch_once(&onceToken, ^{
		immediateScheduler = [[RACImmediateScheduler alloc] init];
	});
	
	return immediateScheduler;
}

/**
 * @brief 获取主线程调度器（单例）。
 * @return 返回RACTargetQueueScheduler实例。
 * @discussion 只会初始化一次，始终返回同一个RACTargetQueueScheduler实例，目标队列为主线程队列。
 */
+ (RACScheduler *)mainThreadScheduler {
	static dispatch_once_t onceToken;
	static RACScheduler *mainThreadScheduler;
	dispatch_once(&onceToken, ^{
		mainThreadScheduler = [[RACTargetQueueScheduler alloc] initWithName:@"org.reactivecocoa.ReactiveObjC.RACScheduler.mainThreadScheduler" targetQueue:dispatch_get_main_queue()];
	});
	
	return mainThreadScheduler;
}

/**
 * @brief 根据优先级和名称创建一个全局队列调度器。
 * @param priority GCD优先级。
 * @param name 调度器名称。
 * @return 返回RACTargetQueueScheduler实例。
 * @discussion 使用GCD的全局队列，适合后台任务。
 */
+ (RACScheduler *)schedulerWithPriority:(RACSchedulerPriority)priority name:(NSString *)name {
	return [[RACTargetQueueScheduler alloc] initWithName:name targetQueue:dispatch_get_global_queue(priority, 0)];
}

/**
 * @brief 根据优先级创建一个全局队列调度器，名称为默认值。
 * @param priority GCD优先级。
 * @return 返回RACTargetQueueScheduler实例。
 */
+ (RACScheduler *)schedulerWithPriority:(RACSchedulerPriority)priority {
	return [self schedulerWithPriority:priority name:@"org.reactivecocoa.ReactiveObjC.RACScheduler.backgroundScheduler"];
}

/**
 * @brief 获取默认优先级的调度器。
 * @return 返回RACTargetQueueScheduler实例。
 */
+ (RACScheduler *)scheduler {
	return [self schedulerWithPriority:RACSchedulerPriorityDefault];
}

/**
 * @brief 获取订阅调度器（单例）。
 * @return 返回RACSubscriptionScheduler实例。
 * @discussion 只会初始化一次，始终返回同一个RACSubscriptionScheduler实例。
 */
+ (RACScheduler *)subscriptionScheduler {
	static dispatch_once_t onceToken;
	static RACScheduler *subscriptionScheduler;
	dispatch_once(&onceToken, ^{
		subscriptionScheduler = [[RACSubscriptionScheduler alloc] init];
	});

	return subscriptionScheduler;
}

/**
 * @brief 判断当前是否在主线程。
 * @return YES表示在主线程，NO表示不在主线程。
 * @discussion 通过比较当前NSOperationQueue和主队列，或判断当前线程是否为主线程。
 */
+ (BOOL)isOnMainThread {
	return [NSOperationQueue.currentQueue isEqual:NSOperationQueue.mainQueue] || [NSThread isMainThread];
}

/**
 * @brief 获取当前线程的调度器。
 * @return 返回当前线程的RACScheduler实例。
 * @discussion 优先从线程字典获取当前调度器，如果没有且在主线程，则返回主线程调度器，否则返回nil。
 */
+ (RACScheduler *)currentScheduler {
	RACScheduler *scheduler = NSThread.currentThread.threadDictionary[RACSchedulerCurrentSchedulerKey];
	if (scheduler != nil) return scheduler;
	if ([self.class isOnMainThread]) return RACScheduler.mainThreadScheduler;

	return nil;
}

#pragma mark Scheduling

/**
 * @brief 调度一个block立即执行。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 该方法为抽象方法，需由子类实现。
 */
- (RACDisposable *)schedule:(void (^)(void))block {
	NSCAssert(NO, @"%@ must be implemented by subclasses.", NSStringFromSelector(_cmd));
	return nil;
}

/**
 * @brief 调度一个block在指定时间后执行。
 * @param date 目标时间。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 该方法为抽象方法，需由子类实现。
 */
- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	NSCAssert(NO, @"%@ must be implemented by subclasses.", NSStringFromSelector(_cmd));
	return nil;
}

/**
 * @brief 调度一个block在延迟delay秒后执行。
 * @param delay 延迟秒数。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 内部调用after:schedule:，将当前时间加上delay作为目标时间。
 */
- (RACDisposable *)afterDelay:(NSTimeInterval)delay schedule:(void (^)(void))block {
	return [self after:[NSDate dateWithTimeIntervalSinceNow:delay] schedule:block];
}

/**
 * @brief 调度一个block在指定时间后重复执行，间隔为interval，leeway为系统允许的最大误差。
 * @param date 首次执行时间。
 * @param interval 重复间隔。
 * @param leeway 系统允许的最大误差。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 该方法为抽象方法，需由子类实现。
 */
- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	NSCAssert(NO, @"%@ must be implemented by subclasses.", NSStringFromSelector(_cmd));
	return nil;
}

/**
 * @brief 递归调度block。
 * @param recursiveBlock 递归调度的block。
 * @return 返回RACDisposable对象。
 * @discussion 通过RACCompoundDisposable管理递归调度的生命周期，防止内存泄漏。
 */
- (RACDisposable *)scheduleRecursiveBlock:(RACSchedulerRecursiveBlock)recursiveBlock {
	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

	[self scheduleRecursiveBlock:[recursiveBlock copy] addingToDisposable:disposable];
	return disposable;
}

/**
 * @brief 递归调度block，并将调度Disposable添加到外部传入的disposable中。
 * @param recursiveBlock 递归调度的block。
 * @param disposable 外部传入的RACCompoundDisposable。
 * @discussion
 * 实现原理：
 * 1. 每次递归调度时，创建一个新的RACCompoundDisposable用于管理本次调度。
 * 2. 通过schedule方法异步调度递归block。
 * 3. 使用NSLock保证递归调度的线程安全。
 * 4. 支持同步和异步递归调度，防止栈溢出。
 */
- (void)scheduleRecursiveBlock:(RACSchedulerRecursiveBlock)recursiveBlock addingToDisposable:(RACCompoundDisposable *)disposable {
	@autoreleasepool {
		RACCompoundDisposable *selfDisposable = [RACCompoundDisposable compoundDisposable];
		[disposable addDisposable:selfDisposable];

		// 这里不能使用__weak修饰符，因为在MRC下不支持。此处为ARC下的写法。
		__weak RACDisposable *weakSelfDisposable = selfDisposable;

		RACDisposable *schedulingDisposable = [self schedule:^{
			@autoreleasepool {
				// 当前递归已被调度，移除本次disposable。
				[disposable removeDisposable:weakSelfDisposable];
			}

			if (disposable.disposed) return;

			void (^reallyReschedule)(void) = ^{
				if (disposable.disposed) return;
				[self scheduleRecursiveBlock:recursiveBlock addingToDisposable:disposable];
			};

			// 保护下面的变量，保证递归调度的线程安全。
			// 由于Clang警告，这里加__block修饰。
			__block NSLock *lock = [[NSLock alloc] init];
			lock.name = [NSString stringWithFormat:@"%@ %s", self, sel_getName(_cmd)];

			__block NSUInteger rescheduleCount = 0;

			// 标记同步执行是否结束，若为YES则后续递归立即执行。
			__block BOOL rescheduleImmediately = NO;

			@autoreleasepool {
				recursiveBlock(^{
					[lock lock];
					BOOL immediate = rescheduleImmediately;
					if (!immediate) ++rescheduleCount;
					[lock unlock];

					if (immediate) reallyReschedule();
				});
			}

			[lock lock];
			NSUInteger synchronousCount = rescheduleCount;
			rescheduleImmediately = YES;
			[lock unlock];

			for (NSUInteger i = 0; i < synchronousCount; i++) {
				reallyReschedule();
			}
		}];

		[selfDisposable addDisposable:schedulingDisposable];
	}
}

/**
 * @brief 以当前调度器身份执行block。
 * @param block 需要执行的block。
 * @discussion
 * 实现原理：
 * 1. 将当前调度器保存到线程字典，便于嵌套调度时获取。
 * 2. block执行完毕后恢复原有调度器，保证线程上下文正确。
 */
- (void)performAsCurrentScheduler:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	// 如果使用并发队列，可能会并发进入此方法，需保证线程字典正确恢复。

	RACScheduler *previousScheduler = RACScheduler.currentScheduler;
	NSThread.currentThread.threadDictionary[RACSchedulerCurrentSchedulerKey] = self;

	@autoreleasepool {
		block();
	}

	if (previousScheduler != nil) {
		NSThread.currentThread.threadDictionary[RACSchedulerCurrentSchedulerKey] = previousScheduler;
	} else {
		[NSThread.currentThread.threadDictionary removeObjectForKey:RACSchedulerCurrentSchedulerKey];
	}
}

@end
