//
//  RACTargetQueueScheduler.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 6/6/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACTargetQueueScheduler.h"
#import "RACQueueScheduler+Subclass.h"

@implementation RACTargetQueueScheduler

#pragma mark Lifecycle

// 初始化方法，创建一个以指定 targetQueue 为目标的串行调度队列。
// name: 调度器名称，如果为 nil，则会根据 targetQueue 的 label 自动生成一个默认名称。
// targetQueue: 目标 GCD 队列，所有调度的任务最终会被分发到该队列上。
- (instancetype)initWithName:(NSString *)name targetQueue:(dispatch_queue_t)targetQueue {
	// 断言 targetQueue 不为 NULL，保证后续操作的安全性。
	NSCParameterAssert(targetQueue != NULL);

	// 如果没有传入名称，则根据 targetQueue 的 label 生成一个默认名称。
	if (name == nil) {
		name = [NSString stringWithFormat:@"org.reactivecocoa.ReactiveObjC.RACTargetQueueScheduler(%s)", dispatch_queue_get_label(targetQueue)];
	}

	// 创建一个串行队列，名称为 name。
	dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
	// 如果队列创建失败，返回 nil。
	if (queue == NULL) return nil;

	// 设置新建队列的目标队列为 targetQueue，
	// 这样该队列上的任务最终会被分发到 targetQueue 上执行，
	// 可用于实现优先级继承或队列分组等高级调度策略。
	dispatch_set_target_queue(queue, targetQueue);

	// 调用父类 RACQueueScheduler 的初始化方法，
	// 以 name 和新建的 queue 进行初始化。
	return [super initWithName:name queue:queue];
}

@end
