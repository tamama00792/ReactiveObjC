// 该文件实现了 UITextView (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式文本监听能力。
//
// 主要功能：
// 1. 提供 rac_delegateProxy 属性，便于拦截和响应 delegate 事件。
// 2. 提供 rac_textSignal 方法，便于监听 UITextView 文本变化。
//
// 实现思路：
// - 通过 delegate 代理拦截 UITextViewDelegate 的 textViewDidChange: 方法，将其转为信号流。
// - 使用信号流实现响应式数据绑定。
//
// 适用场景：
// - 需要响应式监听 UITextView 内容变化，或拦截 delegate 事件。
//
//  Created by Cody Krieger on 5/18/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import "UITextView+RACSignalSupport.h"
#import <ReactiveObjC/EXTScope.h>
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import "RACDelegateProxy.h"
#import "RACSignal+Operations.h"
#import "RACTuple.h"
#import <objc/runtime.h>

@implementation UITextView (RACSignalSupport)

/**
 内部方法：设置 delegate 为 RACDelegateProxy，拦截 delegate 方法。
 @param self 当前 UITextView 实例
 实现原理：
 1. 判断当前 delegate 是否已为 rac_delegateProxy，若是则无需处理。
 2. 若不是，则将原 delegate 赋值给 rac_delegateProxy 的 rac_proxiedDelegate 属性。
 3. 再将 rac_delegateProxy 赋值为当前 delegate，实现 delegate 方法的拦截和信号转发。
*/
static void RACUseDelegateProxy(UITextView *self) {
    if (self.delegate == self.rac_delegateProxy) return;

    // 保存原有 delegate，便于后续消息转发
    self.rac_delegateProxy.rac_proxiedDelegate = self.delegate;
    // 设置代理为 RACDelegateProxy，实现信号拦截
    self.delegate = (id)self.rac_delegateProxy;
}

/**
 获取 RACDelegateProxy 代理对象。
 @return RACDelegateProxy 代理对象。
 实现原理：
 1. 通过 objc_getAssociatedObject 获取已存在的代理对象。
 2. 若不存在，则新建一个基于 UITextViewDelegate 协议的代理对象，并通过 objc_setAssociatedObject 绑定。
 3. 保证每个 UITextView 实例都有独立的代理对象。
*/
- (RACDelegateProxy *)rac_delegateProxy {
	RACDelegateProxy *proxy = objc_getAssociatedObject(self, _cmd);
	if (proxy == nil) {
		proxy = [[RACDelegateProxy alloc] initWithProtocol:@protocol(UITextViewDelegate)];
		objc_setAssociatedObject(self, _cmd, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}

	return proxy;
}

/**
 返回一个信号对象，用于监听 UITextView 的文本变化。
 @return RACSignal<NSString *>：每次文本变化都会发送最新文本。
 实现原理：
 1. defer 初始发送当前 UITextView 实例（打包为 RACTuple）。
 2. concat 监听 textViewDidChange: 事件，将其转为信号流。
 3. reduceEach 提取 text 属性。
 4. takeUntil 保证 UITextView 销毁时信号自动结束，防止内存泄漏。
 5. setNameWithFormat 便于调试。
 6. 最后调用 RACUseDelegateProxy，确保 delegate 被正确代理。
*/
- (RACSignal *)rac_textSignal {
	@weakify(self);
	RACSignal *signal = [[[[[RACSignal
		defer:^{
			@strongify(self);
			// defer 保证订阅时获取最新 self
			return [RACSignal return:RACTuplePack(self)];
		}]
		// 监听 textViewDidChange: 事件
		concat:[self.rac_delegateProxy signalForSelector:@selector(textViewDidChange:)]]
		// 提取 text 属性
		reduceEach:^(UITextView *x) {
			return x.text;
		}]
		// 当控件即将销毁时自动结束信号，防止内存泄漏
		takeUntil:self.rac_willDeallocSignal]
		// 设置信号名称，便于调试
		setNameWithFormat:@"%@ -rac_textSignal", RACDescription(self)];

	// 确保 delegate 被正确代理，实现信号拦截
	RACUseDelegateProxy(self);

	return signal;
}

@end
