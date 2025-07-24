//
//  UIAlertView+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Henrik Hodne on 6/16/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACDelegateProxy;
@class RACSignal<__covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

@interface UIAlertView (RACSignalSupport)

/**
 获取 RACDelegateProxy 代理对象。
 适用场景：需要拦截 delegate 方法或响应 delegate 事件时使用。
 @return RACDelegateProxy 代理对象。
*/
@property (nonatomic, strong, readonly) RACDelegateProxy *rac_delegateProxy;

/**
 创建一个信号，用于监听 UIAlertView 的按钮点击事件。
 适用场景：需要响应用户点击按钮时使用。
 @return RACSignal<NSNumber *>：每次点击按钮时发送按钮索引，控件销毁时信号自动完成。
*/
- (RACSignal<NSNumber *> *)rac_buttonClickedSignal;

/**
 创建一个信号，用于监听 UIAlertView 的消失事件。
 适用场景：需要响应 UIAlertView 消失时使用。
 @return RACSignal<NSNumber *>：每次消失时发送按钮索引，控件销毁时信号自动完成。
*/
- (RACSignal<NSNumber *> *)rac_willDismissSignal;

@end

NS_ASSUME_NONNULL_END
