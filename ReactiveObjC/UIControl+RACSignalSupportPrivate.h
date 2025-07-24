//
//  UIControl+RACSignalSupportPrivate.h
//  ReactiveObjC
//
//  Created by Uri Baghin on 06/08/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACChannelTerminal;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UIControl 提供了 RACChannel 支持的私有接口，便于响应式编程场景下实现控件属性的双向绑定。
// 使用场景：当你需要将 UIControl 的属性与信号进行双向绑定时，可通过该分类实现。
@interface UIControl (RACSignalSupportPrivate)

/**
 为控件添加基于 RACChannel 的双向绑定接口。
 适用场景：需要将控件属性与信号进行双向绑定时使用。
 @param controlEvents 需要监听的 UIControlEvents 事件类型。
 @param key 需要绑定的属性名。
 @param nilValue 当信号接收到 nil 时设置的默认值。
 @return RACChannelTerminal：用于绑定和同步属性值。
*/
- (RACChannelTerminal *)rac_channelForControlEvents:(UIControlEvents)controlEvents key:(NSString *)key nilValue:(nullable id)nilValue;

@end

NS_ASSUME_NONNULL_END
