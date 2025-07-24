//
//  MKAnnotationView+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Zak Remer on 3/31/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>

@class RACSignal<__covariant ValueType>;
@class RACUnit;

NS_ASSUME_NONNULL_BEGIN

/**
 * 该分类为 MKAnnotationView 提供了 RAC（ReactiveObjC）信号支持。
 * 主要用于在视图即将被重用时，发送信号通知订阅者。
 */
@interface MKAnnotationView (RACSignalSupport)

/**
 * 当 -prepareForReuse 方法被调用时，该信号会发送一个 RACUnit。
 *
 * 使用场景：
 * 适用于需要在 MKAnnotationView 重用时，取消订阅、清理资源或重置状态的场景。
 * 例如：
 * [[[self.cancelButton
 *   rac_signalForControlEvents:UIControlEventTouchUpInside]
 *   takeUntil:self.rac_prepareForReuseSignal]
 *   subscribeNext:^(UIButton *x) {
 *       // 处理按钮点击事件
 *   }];
 * 这样可以确保在视图重用时，相关的订阅会自动终止，避免内存泄漏或无效回调。
 */
@property (nonatomic, strong, readonly) RACSignal<RACUnit *> *rac_prepareForReuseSignal;

@end

NS_ASSUME_NONNULL_END
