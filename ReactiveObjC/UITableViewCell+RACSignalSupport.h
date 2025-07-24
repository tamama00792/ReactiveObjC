//
//  UITableViewCell+RACSignalSupport.h
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-07-22.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACSignal<__covariant ValueType>;
@class RACUnit;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UITableViewCell 提供了 RACSignal 支持，便于响应式编程场景下监听 cell 复用事件。
// 使用场景：当你需要监听 UITableViewCell 的复用事件并响应时，可通过该分类提供的信号实现。
@interface UITableViewCell (RACSignalSupport)

/**
 创建并返回一个信号，用于监听 cell 即将被复用的事件。
 适用场景：需要在 cell 复用前做清理或重置操作时使用。
 @return RACSignal<RACUnit *> 信号对象，每次 cell 即将被复用时发送 next 事件。
*/
@property (nonatomic, strong, readonly) RACSignal<RACUnit *> *rac_prepareForReuseSignal;

@end

NS_ASSUME_NONNULL_END
