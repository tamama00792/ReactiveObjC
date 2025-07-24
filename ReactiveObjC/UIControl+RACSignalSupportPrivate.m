// 该文件实现了 UIControl (RACSignalSupportPrivate) 分类，提供了基于 ReactiveObjC 的控件属性双向绑定能力。
//
// 主要功能：
// 1. 提供 rac_channelForControlEvents 方法，实现控件属性与信号的双向绑定。
//
// 实现思路：
// - 通过 RACChannel，将控件属性变化和信号流进行同步，实现数据的双向流动。
//
// 适用场景：
// - 需要将 UIControl 的属性与信号进行双向绑定，实现 MVVM 等响应式架构。
//
//  Created by Uri Baghin on 06/08/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UIControl+RACSignalSupportPrivate.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACLifting.h"
#import "RACChannel.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"
#import "UIControl+RACSignalSupport.h"

@implementation UIControl (RACSignalSupportPrivate)

/**
 为控件添加基于 RACChannel 的双向绑定接口。
 @param controlEvents 需要监听的 UIControlEvents 事件类型。
 @param key 需要绑定的属性名。
 @param nilValue 当信号接收到 nil 时设置的默认值。
 @return RACChannelTerminal：用于绑定和同步属性值。
 实现原理：
 1. 创建 RACChannel，包含 leadingTerminal 和 followingTerminal。
 2. 监听控件事件，将属性值通过信号发送到 channel。
 3. 监听 channel 的 followingTerminal，将信号值同步设置到控件属性。
 4. 支持 nilValue，保证信号流畅通。
 5. 控件销毁时自动 sendCompleted，防止内存泄漏。
*/
- (RACChannelTerminal *)rac_channelForControlEvents:(UIControlEvents)controlEvents key:(NSString *)key nilValue:(id)nilValue {
	NSCParameterAssert(key.length > 0);
	key = [key copy];
	RACChannel *channel = [[RACChannel alloc] init];

	// 控件销毁时自动 sendCompleted
	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[channel.followingTerminal sendCompleted];
	}]];

	// 监听控件事件，将属性值通过信号发送到 channel
	RACSignal *eventSignal = [[[self
		rac_signalForControlEvents:controlEvents]
		mapReplace:key]
		takeUntil:[[channel.followingTerminal
			ignoreValues]
			catchTo:RACSignal.empty]];
	[[self
		rac_liftSelector:@selector(valueForKey:) withSignals:eventSignal, nil]
		subscribe:channel.followingTerminal];

	// 监听 channel 的 followingTerminal，将信号值同步设置到控件属性
	RACSignal *valuesSignal = [channel.followingTerminal
		map:^(id value) {
			return value ?: nilValue;
		}];
	[self rac_liftSelector:@selector(setValue:forKey:) withSignals:valuesSignal, [RACSignal return:key], nil];

	return channel.leadingTerminal;
}

@end
