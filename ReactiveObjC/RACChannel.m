//
//  RACChannel.m
//  ReactiveObjC
//
//  Created by Uri Baghin on 01/01/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACChannel.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import "RACSignal+Operations.h"

/**
 * @class RACChannelTerminal
 * @brief RACChannel的终端，负责信号的发送与接收。
 * @discussion 每个RACChannel包含两个terminal，分别用于双向数据绑定。常用于MVVM等场景下的双向绑定。
 */
@interface RACChannelTerminal<ValueType> ()

/**
 * @brief 当前terminal接收到的所有值组成的信号。
 * @discussion 订阅该信号可获取所有通过此terminal发送的值。
 */
@property (nonatomic, strong, readonly) RACSignal<ValueType> *values;

/**
 * @brief 另一个terminal的订阅者。
 * @discussion 通过该订阅者将值发送到对端terminal，实现双向通信。
 */
@property (nonatomic, strong, readonly) id<RACSubscriber> otherTerminal;

/**
 * @brief 初始化方法。
 * @param values 当前terminal的信号。
 * @param otherTerminal 对端terminal的订阅者。
 * @return 返回RACChannelTerminal对象。
 */
- (instancetype)initWithValues:(RACSignal<ValueType> *)values otherTerminal:(id<RACSubscriber>)otherTerminal;

@end

/**
 * @class RACChannel
 * @brief 用于实现双向数据绑定的通道。
 * @discussion 包含两个terminal，分别用于数据的发送与接收，常用于ViewModel与View之间的双向绑定。
 */
@implementation RACChannel

/**
 * @brief 初始化RACChannel对象。
 * @return 返回RACChannel实例。
 * @discussion 创建两个RACReplaySubject分别作为leading和following terminal的信号源，并互相订阅以转发错误和完成事件。
 * @实现原理 分为三步：
 * 1. 创建两个RACReplaySubject，分别用于leading和following。
 * 2. 互相订阅ignoreValues信号，确保错误和完成事件能互通。
 * 3. 用这两个subject分别初始化两个RACChannelTerminal。
 */
- (instancetype)init {
	self = [super init];

	// 1. 创建两个subject
	// 我们不希望leadingSubject有初始值，但希望能转发错误和完成事件。
	RACReplaySubject *leadingSubject = [[RACReplaySubject replaySubjectWithCapacity:0] setNameWithFormat:@"leadingSubject"];
	RACReplaySubject *followingSubject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"followingSubject"];

	// 2. 互相转发错误和完成事件
	[[leadingSubject ignoreValues] subscribe:followingSubject];
	[[followingSubject ignoreValues] subscribe:leadingSubject];

	// 3. 初始化terminal
	_leadingTerminal = [[[RACChannelTerminal alloc] initWithValues:leadingSubject otherTerminal:followingSubject] setNameWithFormat:@"leadingTerminal"];
	_followingTerminal = [[[RACChannelTerminal alloc] initWithValues:followingSubject otherTerminal:leadingSubject] setNameWithFormat:@"followingTerminal"];

	return self;
}

@end

@implementation RACChannelTerminal

#pragma mark Lifecycle

/**
 * @brief 初始化RACChannelTerminal对象。
 * @param values 当前terminal的信号。
 * @param otherTerminal 对端terminal的订阅者。
 * @return 返回RACChannelTerminal实例。
 * @discussion 用于构建双向绑定的终端。
 * @实现原理 保存values和otherTerminal。
 */
- (instancetype)initWithValues:(RACSignal *)values otherTerminal:(id<RACSubscriber>)otherTerminal {
	NSCParameterAssert(values != nil);
	NSCParameterAssert(otherTerminal != nil);

	self = [super init];

	_values = values;
	_otherTerminal = otherTerminal;

	return self;
}

#pragma mark RACSignal

/**
 * @brief 订阅当前terminal的信号。
 * @param subscriber 订阅者。
 * @return 返回RACDisposable用于取消订阅。
 * @discussion 订阅后可收到所有通过此terminal发送的值。
 * @实现原理 实际订阅values信号。
 */
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	return [self.values subscribe:subscriber];
}

#pragma mark <RACSubscriber>

/**
 * @brief 发送下一个值到对端terminal。
 * @param value 需要发送的值。
 * @discussion 用于实现双向数据同步。
 * @实现原理 直接调用otherTerminal的sendNext:。
 */
- (void)sendNext:(id)value {
	[self.otherTerminal sendNext:value];
}

/**
 * @brief 发送错误到对端terminal。
 * @param error 错误对象。
 * @discussion 用于同步错误状态。
 * @实现原理 直接调用otherTerminal的sendError:。
 */
- (void)sendError:(NSError *)error {
	[self.otherTerminal sendError:error];
}

/**
 * @brief 发送完成事件到对端terminal。
 * @discussion 用于同步完成状态。
 * @实现原理 直接调用otherTerminal的sendCompleted。
 */
- (void)sendCompleted {
	[self.otherTerminal sendCompleted];
}

/**
 * @brief 订阅时的回调。
 * @param disposable 订阅的disposable。
 * @discussion 用于管理订阅的生命周期。
 * @实现原理 直接转发给otherTerminal。
 */
- (void)didSubscribeWithDisposable:(RACCompoundDisposable *)disposable {
	[self.otherTerminal didSubscribeWithDisposable:disposable];
}

@end
