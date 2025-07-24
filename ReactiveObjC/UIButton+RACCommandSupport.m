// 该文件实现了 UIButton (RACCommandSupport) 分类，提供了基于 ReactiveObjC 的响应式按钮命令绑定能力。
//
// 主要功能：
// 1. 提供 rac_command 属性，便于绑定按钮命令。
//
// 实现思路：
// - 通过 KVO 绑定按钮 enabled 属性与命令 enabled 状态。
// - 通过 hijack target-action 机制，按钮点击时自动执行命令。
//
// 适用场景：
// - 需要响应式绑定按钮命令，自动管理按钮可用性。
//
//  Created by Ash Furrow on 2013-06-06.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UIButton+RACCommandSupport.h"
#import <ReactiveObjC/EXTKeyPathCoding.h>
#import "RACCommand.h"
#import "RACDisposable.h"
#import "RACSignal+Operations.h"
#import <objc/runtime.h>

static void *UIButtonRACCommandKey = &UIButtonRACCommandKey;
static void *UIButtonEnabledDisposableKey = &UIButtonEnabledDisposableKey;

@implementation UIButton (RACCommandSupport)

/**
 获取当前绑定的 RACCommand。
 @return RACCommand 对象。
*/
- (RACCommand *)rac_command {
	return objc_getAssociatedObject(self, UIButtonRACCommandKey);
}

/**
 设置并绑定 RACCommand 到 UIButton。
 @param command 需要绑定的命令对象。
 实现原理：
 1. 通过 objc_setAssociatedObject 绑定命令对象。
 2. 解绑旧的 enabled 绑定，防止重复绑定。
 3. 若命令不为空，则通过 KVO 绑定按钮 enabled 属性与命令 enabled 状态。
 4. 通过 hijack target-action 机制，按钮点击时自动执行命令。
*/
- (void)setRac_command:(RACCommand *)command {
	objc_setAssociatedObject(self, UIButtonRACCommandKey, command, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	
	// 解绑旧的 enabled 绑定，防止重复绑定
	RACDisposable *disposable = objc_getAssociatedObject(self, UIButtonEnabledDisposableKey);
	[disposable dispose];
	
	if (command == nil) return;
	
	// 绑定按钮 enabled 属性与命令 enabled 状态
	disposable = [command.enabled setKeyPath:@keypath(self.enabled) onObject:self];
	objc_setAssociatedObject(self, UIButtonEnabledDisposableKey, disposable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	
	// hijack target-action，按钮点击时自动执行命令
	[self rac_hijackActionAndTargetIfNeeded];
}

/**
 劫持按钮点击事件，确保点击时自动执行 rac_command。
*/
- (void)rac_hijackActionAndTargetIfNeeded {
	SEL hijackSelector = @selector(rac_commandPerformAction:);
	
	for (NSString *selector in [self actionsForTarget:self forControlEvent:UIControlEventTouchUpInside]) {
		if (hijackSelector == NSSelectorFromString(selector)) {
			return;
		}
	}
	
	[self addTarget:self action:hijackSelector forControlEvents:UIControlEventTouchUpInside];
}

/**
 按钮点击事件的实际执行方法，自动调用 rac_command。
 @param sender 事件发送者。
*/
- (void)rac_commandPerformAction:(id)sender {
	[self.rac_command execute:sender];
}

@end
