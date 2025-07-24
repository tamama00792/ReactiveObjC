//
//  UIRefreshControl+RACCommandSupport.h
//  ReactiveObjC
//
//  Created by Dave Lee on 2013-10-17.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACCommand<__contravariant InputType, __covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UIRefreshControl 提供了 RACCommand 支持，便于响应式编程场景下绑定刷新命令。
// 使用场景：当你需要在下拉刷新时自动执行命令并处理结束逻辑时，可通过该分类实现。
@interface UIRefreshControl (RACCommandSupport)

/**
 绑定一个 RACCommand 到 UIRefreshControl。
 适用场景：需要在用户触发刷新时自动执行命令，并在命令完成或出错后自动结束刷新动画。
 @property rac_command 绑定的命令对象，类型为 RACCommand<UIRefreshControl *, id>。
*/
@property (nonatomic, strong, nullable) RACCommand<__kindof UIRefreshControl *, id> *rac_command;

@end

NS_ASSUME_NONNULL_END
