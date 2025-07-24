// 该文件实现了 UISlider (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式滑块值监听能力。
//
// 主要功能：
// 1. 提供 rac_newValueChannelWithNilValue 方法，便于监听 UISlider 值变化，实现双向绑定。
//
// 实现思路：
// - 通过信号机制，将 UIControl 事件与 value 属性绑定，实现响应式数据流。
//
// 适用场景：
// - 需要响应式监听 UISlider 值变化，或实现 MVVM 场景下的双向绑定。
//
//  Created by Uri Baghin on 20/07/2013.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UISlider+RACSignalSupport.h"
#import <ReactiveObjC/EXTKeyPathCoding.h>
#import "UIControl+RACSignalSupportPrivate.h"

@implementation UISlider (RACSignalSupport)

/**
 创建一个 RACChannelTerminal，实现 UISlider 的 value 属性与信号的双向绑定。
 @param nilValue 当信号接收到 nil 时设置的默认值。
 @return RACChannelTerminal<NSNumber *>：用于绑定和同步 value。
 实现原理：
 1. 通过 rac_channelForControlEvents 监听 UIControlEventValueChanged 事件。
 2. keypath(self.value) 指定需要绑定的属性。
 3. nilValue 为参数传入值，保证信号流畅通。
*/
- (RACChannelTerminal *)rac_newValueChannelWithNilValue:(NSNumber *)nilValue {
	return [self rac_channelForControlEvents:UIControlEventValueChanged key:@keypath(self.value) nilValue:nilValue];
}

@end
