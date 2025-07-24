// 该文件实现了 UITextField (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式文本监听能力。
//
// 主要功能：
// 1. 提供 rac_textSignal 方法，便于监听 UITextField 文本变化。
// 2. 提供 rac_newTextChannel 方法，便于实现双向绑定。
//
// 实现思路：
// - 通过 ReactiveObjC 的信号机制，将 UIControl 事件与信号流结合，实现响应式数据流。
//
// 适用场景：
// - 需要响应式监听输入框内容变化，或实现 MVVM 场景下的双向绑定。
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "UITextField+RACSignalSupport.h"
#import <ReactiveObjC/EXTKeyPathCoding.h>
#import <ReactiveObjC/EXTScope.h>
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACSignal+Operations.h"
#import "UIControl+RACSignalSupport.h"
#import "UIControl+RACSignalSupportPrivate.h"

@implementation UITextField (RACSignalSupport)

/**
 返回一个信号对象，用于监听 UITextField 的文本变化。
 @return RACSignal<NSString *>：每次文本变化都会发送最新文本。

 实现原理：
 1. 使用 RACSignal 的 defer 方法，初始发送当前 UITextField 实例。
 2. concat 操作符将 UIControlEventAllEditingEvents 事件转为信号流。
 3. map 操作符将事件对象映射为当前 text 属性。
 4. takeUntil 保证 UITextField 销毁时信号自动结束，防止内存泄漏。
 5. setNameWithFormat 便于调试。
*/
- (RACSignal *)rac_textSignal {
	@weakify(self);
	return [[[[[RACSignal
		defer:^{
			@strongify(self);
			// defer 保证订阅时获取最新 self
			return [RACSignal return:self];
		}]
		// 监听所有编辑事件
		concat:[self rac_signalForControlEvents:UIControlEventAllEditingEvents]]
		// 将事件对象映射为 text
		map:^(UITextField *x) {
			return x.text;
		}]
		// 当控件即将销毁时自动结束信号，防止内存泄漏
		takeUntil:self.rac_willDeallocSignal]
		// 设置信号名称，便于调试
		setNameWithFormat:@"%@ -rac_textSignal", RACDescription(self)];
}

/**
 创建一个 RACChannelTerminal，实现 UITextField 的 text 属性与信号的双向绑定。
 @return RACChannelTerminal<NSString *>：用于绑定和同步 text。

 实现原理：
 1. 通过 rac_channelForControlEvents 监听 UIControlEventAllEditingEvents 事件。
 2. keypath(self.text) 指定需要绑定的属性。
 3. nilValue 为空字符串，保证信号流畅通。
*/
- (RACChannelTerminal *)rac_newTextChannel {
	return [self rac_channelForControlEvents:UIControlEventAllEditingEvents key:@keypath(self.text) nilValue:@""];
}

@end
