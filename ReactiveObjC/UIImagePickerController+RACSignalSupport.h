//
//  UIImagePickerController+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Timur Kuchkarov on 28.03.14.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACDelegateProxy;
@class RACSignal<__covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

@interface UIImagePickerController (RACSignalSupport)

/**
 获取 RACDelegateProxy 代理对象。
 适用场景：需要拦截 delegate 方法或响应 delegate 事件时使用。
 @return RACDelegateProxy 代理对象。
*/
@property (nonatomic, strong, readonly) RACDelegateProxy *rac_delegateProxy;

/**
 创建一个信号，用于监听用户选择图片的事件。
 适用场景：需要响应用户选择图片或取消选择时使用。
 @return RACSignal<NSDictionary *>：每次选择图片时发送图片信息字典，用户取消或控件销毁时信号自动完成。
*/
- (RACSignal<NSDictionary *> *)rac_imageSelectedSignal;

@end

NS_ASSUME_NONNULL_END
