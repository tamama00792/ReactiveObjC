//
//  UIBarButtonItem+RACCommandSupport.h
//  ReactiveObjC
//
//  Created by Kyle LeNeau on 3/27/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

@class RACCommand<__contravariant InputType, __covariant ValueType>;

NS_ASSUME_NONNULL_BEGIN

// 该分类为 UIBarButtonItem 提供了 RACCommand 支持，便于响应式编程场景下绑定按钮命令。
// 使用场景：当你需要在点击 UIBarButtonItem 时自动执行命令并绑定可用状态时，可通过该分类实现。
@interface UIBarButtonItem (RACCommandSupport)

/**
 绑定一个 RACCommand 到 UIBarButtonItem。
 适用场景：需要在点击时自动执行命令，并根据命令的 enabled 状态自动更新按钮可用性。
 @property rac_command 绑定的命令对象，类型为 RACCommand<UIBarButtonItem *, id>。
*/
@property (nonatomic, strong, nullable) RACCommand<__kindof UIBarButtonItem *, id> *rac_command;

@end

NS_ASSUME_NONNULL_END
