//
//  UIDatePicker+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Uri Baghin on 20/07/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACChannelTerminal<ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UIDatePicker 提供了 RACSignal 支持，便于响应式编程场景下监听日期选择变化。
// 使用场景：当你需要监听 UIDatePicker 的日期变化并响应时，可通过该分类提供的信号实现。
@interface UIDatePicker (RACSignalSupport)

/**
 创建一个 RACChannelTerminal，实现 UIDatePicker 的 date 属性与信号的双向绑定。
 适用场景：需要响应式监听日期变化，或实现 MVVM 场景下的双向绑定。
 @param nilValue 当信号接收到 nil 时设置的默认日期。
 @return RACChannelTerminal<NSDate *>：用于绑定和同步 date。
*/
- (RACChannelTerminal<NSDate *> *)rac_newDateChannelWithNilValue:(nullable NSDate *)nilValue;

@end

NS_ASSUME_NONNULL_END
