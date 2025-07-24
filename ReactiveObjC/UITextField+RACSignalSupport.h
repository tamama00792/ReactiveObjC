//
//  UITextField+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACChannelTerminal<ValueType>;
@class RACSignal<__covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UITextField 提供了 RACSignal 支持，便于响应式编程场景下监听文本变化。
// 使用场景：当你需要监听 UITextField 的文本变化并响应时，可通过该分类提供的信号实现。
@interface UITextField (RACSignalSupport)

/**
 创建并返回一个信号，用于监听 UITextField 的文本变化。
 适用场景：需要实时获取输入框内容变化时使用。
 @return RACSignal<NSString *> 信号对象，每次文本变化都会发送最新的文本内容，初始值为当前文本。
*/
- (RACSignal<NSString *> *)rac_textSignal;

/**
 创建一个新的 RACChannel 绑定到接收者。
 适用场景：需要实现双向绑定时使用。
 @return RACChannelTerminal<NSString *> 终端对象，当 UITextField 触发 UIControlEventAllEditingEvents 事件时，发送当前文本；接收到新值时会自动设置到文本框。
*/
- (RACChannelTerminal<NSString *> *)rac_newTextChannel;

@end

NS_ASSUME_NONNULL_END
