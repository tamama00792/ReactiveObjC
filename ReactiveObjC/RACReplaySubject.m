//
//  RACReplaySubject.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/14/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACReplaySubject.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACScheduler+Private.h"
#import "RACSubscriber.h"
#import "RACTuple.h"

// 无限容量的常量定义。
const NSUInteger RACReplaySubjectUnlimitedCapacity = NSUIntegerMax;

/**
 * @class RACReplaySubject
 * @brief 支持重放历史值的信号体，订阅者可收到所有历史事件。
 * @discussion 常用于缓存事件、保证新订阅者能收到全部或部分历史数据的场景。
 */
@interface RACReplaySubject ()

/**
 * @brief 缓存容量，超过后只保留最新capacity个值。
 */
@property (nonatomic, assign, readonly) NSUInteger capacity;

/**
 * @brief 已接收到的所有值。
 * @discussion 仅在@synchronized(self)下访问和修改。
 */
@property (nonatomic, strong, readonly) NSMutableArray *valuesReceived;

/**
 * @brief 是否已发送完成事件。
 * @discussion 仅在@synchronized(self)下访问和修改。
 */
@property (nonatomic, assign) BOOL hasCompleted;

/**
 * @brief 是否已发送错误事件。
 * @discussion 仅在@synchronized(self)下访问和修改。
 */
@property (nonatomic, assign) BOOL hasError;

/**
 * @brief 记录的错误对象。
 * @discussion 仅在@synchronized(self)下访问和修改。
 */
@property (nonatomic, strong) NSError *error;

@end


@implementation RACReplaySubject

#pragma mark Lifecycle

/**
 * @brief 创建指定容量的RACReplaySubject。
 * @param capacity 缓存容量。
 * @return 返回RACReplaySubject实例。
 */
+ (instancetype)replaySubjectWithCapacity:(NSUInteger)capacity {
	return [(RACReplaySubject *)[self alloc] initWithCapacity:capacity];
}

/**
 * @brief 创建无限容量的RACReplaySubject。
 * @return 返回RACReplaySubject实例。
 */
- (instancetype)init {
	return [self initWithCapacity:RACReplaySubjectUnlimitedCapacity];
}

/**
 * @brief 以指定容量初始化RACReplaySubject。
 * @param capacity 缓存容量。
 * @return 返回RACReplaySubject实例。
 * @discussion capacity为RACReplaySubjectUnlimitedCapacity时，内部数组不限制长度。
 */
- (instancetype)initWithCapacity:(NSUInteger)capacity {
	self = [super init];
	
	_capacity = capacity;
	_valuesReceived = (capacity == RACReplaySubjectUnlimitedCapacity ? [NSMutableArray array] : [NSMutableArray arrayWithCapacity:capacity]);
	
	return self;
}

#pragma mark RACSignal

/**
 * @brief 订阅信号，重放历史值并监听后续事件。
 * @param subscriber 订阅者。
 * @return 返回RACDisposable对象。
 * @discussion 先重放所有历史值，再根据当前状态发送完成/错误/继续订阅。
 * @实现原理 分为三步：
 * 1. 重放历史值。
 * 2. 若已完成/错误则发送对应事件。
 * 3. 否则继续订阅后续事件。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

	RACDisposable *schedulingDisposable = [RACScheduler.subscriptionScheduler schedule:^{
		@synchronized (self) {
			for (id value in self.valuesReceived) {
				if (compoundDisposable.disposed) return;

				[subscriber sendNext:(value == RACTupleNil.tupleNil ? nil : value)];
			}

			if (compoundDisposable.disposed) return;

			if (self.hasCompleted) {
				[subscriber sendCompleted];
			} else if (self.hasError) {
				[subscriber sendError:self.error];
			} else {
				RACDisposable *subscriptionDisposable = [super subscribe:subscriber];
				[compoundDisposable addDisposable:subscriptionDisposable];
			}
		}
	}];

	[compoundDisposable addDisposable:schedulingDisposable];

	return compoundDisposable;
}

#pragma mark RACSubscriber

/**
 * @brief 发送下一个值，缓存并转发给所有订阅者。
 * @param value 发送的值。
 * @discussion 超过容量时丢弃最早的值，nil用RACTupleNil占位。
 */
- (void)sendNext:(id)value {
	@synchronized (self) {
		[self.valuesReceived addObject:value ?: RACTupleNil.tupleNil];
		
		if (self.capacity != RACReplaySubjectUnlimitedCapacity && self.valuesReceived.count > self.capacity) {
			[self.valuesReceived removeObjectsInRange:NSMakeRange(0, self.valuesReceived.count - self.capacity)];
		}
		
		[super sendNext:value];
	}
}

/**
 * @brief 发送完成事件，所有订阅者收到completed。
 */
- (void)sendCompleted {
	@synchronized (self) {
		self.hasCompleted = YES;
		[super sendCompleted];
	}
}

/**
 * @brief 发送错误事件，所有订阅者收到error。
 * @param e 错误对象。
 */
- (void)sendError:(NSError *)e {
	@synchronized (self) {
		self.hasError = YES;
		self.error = e;
		[super sendError:e];
	}
}

@end
