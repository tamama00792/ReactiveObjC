//
//  RACSubscriptionScheduler.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubscriptionScheduler.h"
#import "RACScheduler+Private.h"

@interface RACSubscriptionScheduler ()

// 一个私有的后台调度器，当 +currentScheduler 未知时用于订阅。
@property (nonatomic, strong, readonly) RACScheduler *backgroundScheduler;

@end

@implementation RACSubscriptionScheduler

#pragma mark Lifecycle

// 初始化方法，设置调度器名称，并初始化后台调度器。
- (instancetype)init {
	self = [super initWithName:@"org.reactivecocoa.ReactiveObjC.RACScheduler.subscriptionScheduler"];

	// 创建一个新的后台调度器实例，用于在没有当前调度器时执行任务。
	_backgroundScheduler = [RACScheduler scheduler];

	return self;
}

#pragma mark RACScheduler

// 调度一个 block。如果当前没有调度器，则使用后台调度器异步执行，否则直接执行。
- (RACDisposable *)schedule:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	// 如果当前没有调度器，则在后台调度器上调度 block。
	if (RACScheduler.currentScheduler == nil) return [self.backgroundScheduler schedule:block];

	// 如果有当前调度器，则直接同步执行 block。
	block();
	return nil;
}

// 在指定时间后调度一个 block。如果没有当前调度器，则使用后台调度器。
- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	// 选择当前调度器或后台调度器。
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date schedule:block];
}

// 在指定时间后重复调度 block。如果没有当前调度器，则使用后台调度器。
- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	// 选择当前调度器或后台调度器。
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date repeatingEvery:interval withLeeway:leeway schedule:block];
}

@end
