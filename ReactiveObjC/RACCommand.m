//
//  RACCommand.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/3/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACCommand.h"
#import <ReactiveObjC/EXTScope.h>
#import "NSArray+RACSequenceAdditions.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACPropertySubscribing.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACScheduler.h"
#import "RACSequence.h"
#import "RACSignal+Operations.h"
#import <libkern/OSAtomic.h>

NSErrorDomain const RACCommandErrorDomain = @"RACCommandErrorDomain";
NSString * const RACUnderlyingCommandErrorKey = @"RACUnderlyingCommandErrorKey";

@interface RACCommand () {
	// Atomic backing variable for `allowsConcurrentExecution`.
	volatile uint32_t _allowsConcurrentExecution;
}

/// A subject that sends added execution signals.
@property (nonatomic, strong, readonly) RACSubject *addedExecutionSignalsSubject;

/// A subject that sends the new value of `allowsConcurrentExecution` whenever it changes.
@property (nonatomic, strong, readonly) RACSubject *allowsConcurrentExecutionSubject;

// `enabled`, but without a hop to the main thread.
//
// Values from this signal may arrive on any thread.
@property (nonatomic, strong, readonly) RACSignal *immediateEnabled;

// The signal block that the receiver was initialized with.
@property (nonatomic, copy, readonly) RACSignal * (^signalBlock)(id input);

@end

@implementation RACCommand

// MARK: - 属性方法

/**
 返回当前命令是否允许并发执行。
 原理：通过原子变量 _allowsConcurrentExecution 控制，非0表示允许并发。
*/
- (BOOL)allowsConcurrentExecution {
	return _allowsConcurrentExecution != 0;
}

/**
 设置命令是否允许并发执行。
 原理：使用 OSAtomic 原子操作设置 _allowsConcurrentExecution，保证线程安全，并通过 allowsConcurrentExecutionSubject 通知变更。
*/
- (void)setAllowsConcurrentExecution:(BOOL)allowed {
	if (allowed) {
		OSAtomicOr32Barrier(1, &_allowsConcurrentExecution);
	} else {
		OSAtomicAnd32Barrier(0, &_allowsConcurrentExecution);
	}

	[self.allowsConcurrentExecutionSubject sendNext:@(_allowsConcurrentExecution)];
}

// MARK: - 生命周期

/**
 禁止使用默认初始化方法，强制使用 -initWithSignalBlock:。
*/
- (instancetype)init {
	NSCAssert(NO, @"Use -initWithSignalBlock: instead");
	return nil;
}

/**
 通过 signalBlock 初始化命令。
 signalBlock：执行命令时调用的 block，返回一个 RACSignal。
 内部实现：调用带 enabled 参数的初始化方法，enabled 传 nil。
*/
- (instancetype)initWithSignalBlock:(RACSignal<id> * (^)(id input))signalBlock {
	return [self initWithEnabled:nil signalBlock:signalBlock];
}

/**
 析构方法。
 原理：命令销毁时，向相关 subject 发送完成信号，释放资源。
*/
- (void)dealloc {
	[_addedExecutionSignalsSubject sendCompleted];
	[_allowsConcurrentExecutionSubject sendCompleted];
}

/**
 指定初始化方法。
 enabledSignal：外部传入的可用性信号，决定命令是否可用。
 signalBlock：执行命令时调用的 block，返回一个 RACSignal。
 实现原理：
 1. 初始化 subject 和 signalBlock。
 2. 构建 executionSignals，收集所有执行产生的信号。
 3. 构建 errors 信号，收集所有执行过程中的错误。
 4. 构建 executing 信号，标记当前是否有正在执行的任务。
 5. 构建 enabled 信号，结合外部 enabledSignal 和内部并发控制，决定命令是否可用。
*/
- (instancetype)initWithEnabled:(RACSignal *)enabledSignal signalBlock:(RACSignal<id> * (^)(id input))signalBlock {
	NSCParameterAssert(signalBlock != nil);

	self = [super init];

	_addedExecutionSignalsSubject = [RACSubject new];
	_allowsConcurrentExecutionSubject = [RACSubject new];
	_signalBlock = [signalBlock copy];

	// 构建 executionSignals，收集所有执行产生的信号，遇到错误时转为空信号，保证外部订阅不会因错误中断。
	_executionSignals = [[[self.addedExecutionSignalsSubject
		map:^(RACSignal *signal) {
			return [signal catchTo:[RACSignal empty]];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		setNameWithFormat:@"%@ -executionSignals", self];
	
	// 构建 errors 信号，收集所有执行过程中的错误，使用 multicast 保证后续订阅者也能收到之前的错误。
	RACMulticastConnection *errorsConnection = [[[self.addedExecutionSignalsSubject
		flattenMap:^(RACSignal *signal) {
			return [[signal
				ignoreValues]
				catch:^(NSError *error) {
					return [RACSignal return:error];
				}];
		}]
		deliverOn:RACScheduler.mainThreadScheduler]
		publish];
	
	_errors = [errorsConnection.signal setNameWithFormat:@"%@ -errors", self];
	[errorsConnection connect];

	// 构建 executing 信号，标记当前是否有正在执行的任务。
	RACSignal *immediateExecuting = [[[[self.addedExecutionSignalsSubject
		flattenMap:^(RACSignal *signal) {
			return [[[signal
				catchTo:[RACSignal empty]]
				then:^{
					return [RACSignal return:@-1];
				}]
				startWith:@1];
		}]
		scanWithStart:@0 reduce:^(NSNumber *running, NSNumber *next) {
			return @(running.integerValue + next.integerValue);
		}]
		map:^(NSNumber *count) {
			return @(count.integerValue > 0);
		}]
		startWith:@NO];

	_executing = [[[[[immediateExecuting
		deliverOn:RACScheduler.mainThreadScheduler]
		// 保证主线程下的初始值
		startWith:@NO]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -executing", self];
	
	// moreExecutionsAllowed 用于控制并发执行。
	RACSignal *moreExecutionsAllowed = [RACSignal
		if:[self.allowsConcurrentExecutionSubject startWith:@NO]
		then:[RACSignal return:@YES]
		else:[immediateExecuting not]];
	
	// enabledSignal 为空时默认可用，否则加上初始值 YES。
	if (enabledSignal == nil) {
		enabledSignal = [RACSignal return:@YES];
	} else {
		enabledSignal = [enabledSignal startWith:@YES];
	}
	
	// immediateEnabled 结合外部 enabledSignal 和并发控制，决定命令是否可用。
	_immediateEnabled = [[[[RACSignal
		combineLatest:@[ enabledSignal, moreExecutionsAllowed ]]
		and]
		takeUntil:self.rac_willDeallocSignal]
		replayLast];
	
	// enabled 信号，主线程下输出，保证 UI 可用性同步。
	_enabled = [[[[[self.immediateEnabled
		take:1]
		concat:[[self.immediateEnabled skip:1] deliverOn:RACScheduler.mainThreadScheduler]]
		distinctUntilChanged]
		replayLast]
		setNameWithFormat:@"%@ -enabled", self];

	return self;
}

// MARK: - 执行方法

/**
 执行命令。
 input：传入的参数。
 原理：
 1. 检查 immediateEnabled 是否允许执行，不允许则返回错误信号。
 2. 调用 signalBlock 生成执行信号。
 3. 使用 RACMulticastConnection 保证信号多次订阅只执行一次。
 4. 将执行信号发送到 addedExecutionSignalsSubject，供外部监听。
 5. 返回执行信号。
*/
- (RACSignal *)execute:(id)input {
	// `immediateEnabled` 保证订阅时立即有值，这里用 -first 获取当前可用性。
	BOOL enabled = [[self.immediateEnabled first] boolValue];
	if (!enabled) {
		NSError *error = [NSError errorWithDomain:RACCommandErrorDomain code:RACCommandErrorNotEnabled userInfo:@{
			NSLocalizedDescriptionKey: NSLocalizedString(@"The command is disabled and cannot be executed", nil),
			RACUnderlyingCommandErrorKey: self
		}];

		return [RACSignal error:error];
	}

	RACSignal *signal = self.signalBlock(input);
	NSCAssert(signal != nil, @"nil signal returned from signal block for value: %@", input);

	// 主线程订阅，保证执行状态及时更新。
	RACMulticastConnection *connection = [[signal
		subscribeOn:RACScheduler.mainThreadScheduler]
		multicast:[RACReplaySubject subject]];
	
	[self.addedExecutionSignalsSubject sendNext:connection.signal];

	[connection connect];
	return [connection.signal setNameWithFormat:@"%@ -execute: %@", self, RACDescription(input)];
}

@end
