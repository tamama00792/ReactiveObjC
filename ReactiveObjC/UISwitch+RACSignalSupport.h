//
//  UISwitch+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Uri Baghin on 20/07/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACChannelTerminal<ValueType>;

NS_ASSUME_NONNULL_BEGIN

@interface UISwitch (RACSignalSupport)

/**
 创建并返回一个信号，用于监听 UISwitch 的开关状态变化。
 适用场景：需要实时获取 UISwitch 状态变化时使用。
 @return RACSignal<NSNumber *> 信号对象，每次开关状态变化都会发送最新的状态（@YES/@NO）。
*/
@property (nonatomic, strong, readonly) RACSignal<NSNumber *> *rac_newOnChannel;

@end

NS_ASSUME_NONNULL_END
