//
//  UICollectionReusableView+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Kent Wong on 2013-10-04.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACSignal<__covariant ValueType>;
@class RACUnit;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UICollectionReusableView 提供了 RACSignal 支持，便于响应式编程场景下监听视图复用事件。
// 使用场景：当你需要监听 UICollectionReusableView 的复用事件并响应时，可通过该分类提供的信号实现。
@interface UICollectionReusableView (RACSignalSupport)

/**
 创建并返回一个信号，用于监听视图即将被复用的事件。
 适用场景：需要在视图复用前做清理或重置操作时使用。
 @return RACSignal<RACUnit *> 信号对象，每次视图即将被复用时发送 next 事件。
*/
@property (nonatomic, strong, readonly) RACSignal<RACUnit *> *rac_prepareForReuseSignal;

@end

NS_ASSUME_NONNULL_END
