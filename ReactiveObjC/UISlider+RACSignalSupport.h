//
//  UISlider+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Uri Baghin on 20/07/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACChannelTerminal<ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UISlider 提供了 RACSignal 支持，便于响应式编程场景下监听滑块值变化。
// 使用场景：当你需要监听 UISlider 的值变化并响应时，可通过该分类提供的信号实现。
@interface UISlider (RACSignalSupport)

/**
 创建一个 RACChannelTerminal，实现 UISlider 的 value 属性与信号的双向绑定。
 适用场景：需要响应式监听滑块值变化，或实现 MVVM 场景下的双向绑定。
 @param nilValue 当信号接收到 nil 时设置的默认值。
 @return RACChannelTerminal<NSNumber *>：用于绑定和同步 value。
*/
- (RACChannelTerminal<NSNumber *> *)rac_newValueChannelWithNilValue:(nullable NSNumber *)nilValue;

@end

NS_ASSUME_NONNULL_END
