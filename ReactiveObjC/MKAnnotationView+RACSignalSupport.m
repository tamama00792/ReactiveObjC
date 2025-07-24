//
//  MKAnnotationView+RACSignalSupport.m
//  ReactiveObjC
//
//  Created by Zak Remer on 3/31/15.
//  Copyright (c) 2015 GitHub. All rights reserved.
//

#import "MKAnnotationView+RACSignalSupport.h"
#import "NSObject+RACDescription.h"
#import "NSObject+RACSelectorSignal.h"
#import "RACSignal+Operations.h"
#import "RACUnit.h"
#import <objc/runtime.h>

@implementation MKAnnotationView (RACSignalSupport)

/// 返回一个信号，当 MKAnnotationView 调用 prepareForReuse 方法时发送事件。
/// 
/// 实现原理：
/// 1. 首先尝试从关联对象中获取已存在的信号，如果有则直接返回，避免重复创建。
/// 2. 如果没有，则通过 rac_signalForSelector: 监听 prepareForReuse 方法的调用。
/// 3. 使用 mapReplace: 将信号的所有事件替换为 RACUnit（表示无具体值，仅表示事件发生）。
/// 4. setNameWithFormat: 用于调试，给信号命名，便于追踪。
/// 5. 最后将信号通过 objc_setAssociatedObject 关联到当前对象，确保每个视图只创建一个信号实例。
/// 6. 返回该信号。
- (RACSignal *)rac_prepareForReuseSignal {
	// 从关联对象中获取信号，避免重复创建
	RACSignal *signal = objc_getAssociatedObject(self, _cmd);
	if (signal != nil) return signal;

	// 监听 prepareForReuse 方法的调用，并将事件映射为 RACUnit
	signal = [[[self
		rac_signalForSelector:@selector(prepareForReuse)]
		mapReplace:RACUnit.defaultUnit]
		setNameWithFormat:@"%@ -rac_prepareForReuseSignal", RACDescription(self)];

	// 将信号与当前对象进行关联，生命周期与视图一致
	objc_setAssociatedObject(self, _cmd, signal, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return signal;
}

@end
