//
//  RACQueueScheduler.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACQueueScheduler.h"
#import "RACDisposable.h"
#import "RACQueueScheduler+Subclass.h"
#import "RACScheduler+Private.h"

/**
 * @class RACQueueScheduler
 * @brief 基于GCD队列的调度器，支持异步、延迟、定时任务调度。
 * @discussion 适用于需要在指定队列上调度任务的场景，如后台并发、串行队列等。
 */
@implementation RACQueueScheduler

#pragma mark Lifecycle

/**
 * @brief 以名称和GCD队列初始化调度器。
 * @param name 调度器名称。
 * @param queue GCD队列。
 * @return 返回RACQueueScheduler实例。
 */
- (instancetype)initWithName:(NSString *)name queue:(dispatch_queue_t)queue {
	NSCParameterAssert(queue != NULL);

	self = [super initWithName:name];

	_queue = queue;
#if !OS_OBJECT_USE_OBJC
	dispatch_retain(_queue);
#endif

	return self;
}

#if !OS_OBJECT_USE_OBJC

/**
 * @brief 析构函数，释放GCD队列资源（非ARC下）。
 */
- (void)dealloc {
	if (_queue != NULL) {
		dispatch_release(_queue);
		_queue = NULL;
	}
}

#endif

#pragma mark Date Conversions

/**
 * @brief 将NSDate转换为dispatch_time_t（wall time）。
 * @param date 目标时间。
 * @return dispatch_time_t类型的wall time。
 */
+ (dispatch_time_t)wallTimeWithDate:(NSDate *)date {
	NSCParameterAssert(date != nil);

	double seconds = 0;
	double frac = modf(date.timeIntervalSince1970, &seconds);

	struct timespec walltime = {
		.tv_sec = (time_t)fmin(fmax(seconds, LONG_MIN), LONG_MAX),
		.tv_nsec = (long)fmin(fmax(frac * NSEC_PER_SEC, LONG_MIN), LONG_MAX)
	};

	return dispatch_walltime(&walltime, 0);
}

#pragma mark RACScheduler

/**
 * @brief 异步调度block到队列执行。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 任务会异步提交到队列，支持取消。
 */
- (RACDisposable *)schedule:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	RACDisposable *disposable = [[RACDisposable alloc] init];

	dispatch_async(self.queue, ^{
		if (disposable.disposed) return;
		[self performAsCurrentScheduler:block];
	});

	return disposable;
}

/**
 * @brief 延迟调度block到队列执行。
 * @param date 目标时间。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 到达目标时间后异步提交到队列，支持取消。
 */
- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	NSCParameterAssert(date != nil);
	NSCParameterAssert(block != NULL);

	RACDisposable *disposable = [[RACDisposable alloc] init];

	dispatch_after([self.class wallTimeWithDate:date], self.queue, ^{
		if (disposable.disposed) return;
		[self performAsCurrentScheduler:block];
	});

	return disposable;
}

/**
 * @brief 定时重复调度block到队列执行。
 * @param date 首次执行时间。
 * @param interval 重复间隔（秒）。
 * @param leeway 系统允许的最大误差（秒）。
 * @param block 需要调度执行的block。
 * @return 返回RACDisposable对象。
 * @discussion 使用GCD定时器，支持取消。
 */
- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	NSCParameterAssert(date != nil);
	NSCParameterAssert(interval > 0.0 && interval < INT64_MAX / NSEC_PER_SEC);
	NSCParameterAssert(leeway >= 0.0 && leeway < INT64_MAX / NSEC_PER_SEC);
	NSCParameterAssert(block != NULL);

	uint64_t intervalInNanoSecs = (uint64_t)(interval * NSEC_PER_SEC);
	uint64_t leewayInNanoSecs = (uint64_t)(leeway * NSEC_PER_SEC);

	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
	dispatch_source_set_timer(timer, [self.class wallTimeWithDate:date], intervalInNanoSecs, leewayInNanoSecs);
	dispatch_source_set_event_handler(timer, block);
	dispatch_resume(timer);

	return [RACDisposable disposableWithBlock:^{
		dispatch_source_cancel(timer);
	}];
}

@end
