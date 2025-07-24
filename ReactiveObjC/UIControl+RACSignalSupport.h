//
//  UIControl+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Josh Abernathy on 4/17/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACSignal<__covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UIControl 提供了 RACSignal 支持，便于响应式编程场景下监听控件事件。
// 使用场景：当你需要监听 UIControl 的各种事件并响应时，可通过该分类提供的信号实现。
@interface UIControl (RACSignalSupport)

/**
 创建并返回一个信号对象，用于监听 UIControl 的指定事件。
 适用场景：需要响应式监听按钮点击、值变化等事件时使用。
 @param controlEvents 需要监听的 UIControlEvents 事件类型。
 @return RACSignal<UIControl *>：每次事件触发时发送当前控件自身。
*/
- (RACSignal<__kindof UIControl *> *)rac_signalForControlEvents:(UIControlEvents)controlEvents;

@end

NS_ASSUME_NONNULL_END
