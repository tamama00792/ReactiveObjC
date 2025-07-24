// 该文件实现了 UICollectionReusableView (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式复用事件监听能力。
//
// 主要功能：
// 1. 提供 rac_prepareForReuseSignal 方法，便于监听视图复用事件。
//
// 实现思路：
// - 通过信号机制，将 prepareForReuse 方法调用转为信号流。
//
// 适用场景：
// - 需要响应式监听 UICollectionReusableView 复用事件，做清理或重置操作。
//
//  Created by Kent Wong on 2013-10-04.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "UICollectionReusableView+RACSignalSupport.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACSelectorSignal.h"
#import "RACSignal+Operations.h"
#import "RACUnit.h"
#import <objc/runtime.h>

@implementation UICollectionReusableView (RACSignalSupport)

/**
 返回一个信号对象，用于监听视图即将被复用的事件。
 @return RACSignal<RACUnit *>：每次 prepareForReuse 被调用时发送 next。
 实现原理：
 1. 通过 objc_getAssociatedObject 获取已存在的信号，避免重复创建。
 2. 若不存在，则通过 rac_signalForSelector 监听 prepareForReuse 方法。
 3. mapReplace 将事件映射为 RACUnit，表示仅关心事件发生。
 4. setNameWithFormat 便于调试。
 5. 最后通过 objc_setAssociatedObject 绑定信号，保证每个实例唯一。
*/
- (RACSignal *)rac_prepareForReuseSignal {
	RACSignal *signal = objc_getAssociatedObject(self, _cmd);
	if (signal != nil) return signal;

	// 监听 prepareForReuse 方法调用
	signal = [[[self
		rac_signalForSelector:@selector(prepareForReuse)]
		// 只关心事件发生，不关心参数
		mapReplace:RACUnit.defaultUnit]
		// 设置信号名称，便于调试
		setNameWithFormat:@"%@ -rac_prepareForReuseSignal", RACDescription(self)];

	// 绑定信号到当前实例，避免重复创建
	objc_setAssociatedObject(self, _cmd, signal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return signal;
}

@end
