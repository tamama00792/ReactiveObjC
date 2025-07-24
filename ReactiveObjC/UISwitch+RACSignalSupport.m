// 该文件实现了 UISwitch (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式开关状态监听能力。
//
// 主要功能：
// 1. 提供 rac_newOnChannel 方法，便于监听 UISwitch 状态变化，实现双向绑定。
//
// 实现思路：
// - 通过信号机制，将 UIControl 事件与 on 属性绑定，实现响应式数据流。
//
// 适用场景：
// - 需要响应式监听 UISwitch 状态变化，或实现 MVVM 场景下的双向绑定。
//
//  Created by Uri Baghin on 20/07/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UISwitch+RACSignalSupport.h"
#import <ReactiveObjC/EXTKeyPathCoding.h>
#import "UIControl+RACSignalSupportPrivate.h"

@implementation UISwitch (RACSignalSupport)

/**
 创建一个 RACChannelTerminal，实现 UISwitch 的 on 属性与信号的双向绑定。
 @return RACChannelTerminal<NSNumber *>：用于绑定和同步 on 状态。
 实现原理：
 1. 通过 rac_channelForControlEvents 监听 UIControlEventValueChanged 事件。
 2. keypath(self.on) 指定需要绑定的属性。
 3. nilValue 为 @NO，保证信号流畅通。
*/
- (RACChannelTerminal *)rac_newOnChannel {
	return [self rac_channelForControlEvents:UIControlEventValueChanged key:@keypath(self.on) nilValue:@NO];
}

@end
