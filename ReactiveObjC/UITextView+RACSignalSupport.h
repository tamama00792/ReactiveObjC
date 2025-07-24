//
//  UITextView+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Cody Krieger on 5/18/12.
//  Copyright (c) 2012 Cody Krieger. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACDelegateProxy;
@class RACSignal<__covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

@interface UITextView (RACSignalSupport)

/**
 获取一个代理代理对象，当本分类中的方法被使用时会自动设置为 UITextView 的 delegate。
 适用场景：需要拦截 delegate 方法或响应 delegate 事件时使用。
 @return RACDelegateProxy 代理对象。
*/
@property (nonatomic, strong, readonly) RACDelegateProxy *rac_delegateProxy;

/**
 创建并返回一个信号，用于监听 UITextView 的文本变化。
 适用场景：需要实时获取 UITextView 内容变化时使用。
 @return RACSignal<NSString *> 信号对象，每次文本变化都会发送最新的文本内容，初始值为当前文本。
*/
- (RACSignal<NSString *> *)rac_textSignal;

@end

NS_ASSUME_NONNULL_END
