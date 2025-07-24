// 该文件实现了 UIControl (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式控件事件监听能力。
//
// 主要功能：
// 1. 提供 rac_signalForControlEvents 方法，便于监听 UIControl 的各种事件。
//
// 实现思路：
// - 通过信号机制，将 UIControl 事件与信号流结合，实现响应式数据流。
//
// 适用场景：
// - 需要响应式监听按钮点击、值变化等事件。
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "UIControl+RACSignalSupport.h"
#import <ReactiveObjC/EXTScope.h>
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACSignal.h"
#import "RACSubscriber.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"

@implementation UIControl (RACSignalSupport)

/**
 创建并返回一个信号对象，用于监听 UIControl 的指定事件。
 @param controlEvents 需要监听的 UIControlEvents 事件类型。
 @return RACSignal<UIControl *>：每次事件触发时发送当前控件自身。
 实现原理：
 1. createSignal 创建信号，订阅时为控件添加 target-action。
 2. 事件发生时，subscriber 通过 sendNext: 接收事件。
 3. 控件销毁时自动 sendCompleted，防止内存泄漏。
 4. 取消订阅时移除 target-action，保证资源释放。
 5. setNameWithFormat 便于调试。
*/
- (RACSignal *)rac_signalForControlEvents:(UIControlEvents)controlEvents {
	@weakify(self);

	return [[RACSignal
		createSignal:^(id<RACSubscriber> subscriber) {
			@strongify(self);

			// 添加 target-action，事件发生时发送信号
			[self addTarget:subscriber action:@selector(sendNext:) forControlEvents:controlEvents];

			// 控件销毁时自动 sendCompleted
			RACDisposable *disposable = [RACDisposable disposableWithBlock:^{
				[subscriber sendCompleted];
			}];
			[self.rac_deallocDisposable addDisposable:disposable];

			// 取消订阅时移除 target-action，释放资源
			return [RACDisposable disposableWithBlock:^{
				@strongify(self);
				[self.rac_deallocDisposable removeDisposable:disposable];
				[self removeTarget:subscriber action:@selector(sendNext:) forControlEvents:controlEvents];
			}];
		}]
		// 设置信号名称，便于调试
		setNameWithFormat:@"%@ -rac_signalForControlEvents: %lx", RACDescription(self), (unsigned long)controlEvents];
}

@end
