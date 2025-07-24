// 该文件实现了 UIImagePickerController (RACSignalSupport) 分类，提供了基于 ReactiveObjC 的响应式图片选择事件监听能力。
//
// 主要功能：
// 1. 提供 rac_delegateProxy 属性，便于拦截和响应 delegate 事件。
// 2. 提供 rac_imageSelectedSignal 方法，便于监听图片选择和取消事件。
//
// 实现思路：
// - 通过 delegate 代理拦截 UIImagePickerControllerDelegate 的相关方法，将其转为信号流。
// - 使用信号流实现响应式数据绑定。
//
// 适用场景：
// - 需要响应式监听图片选择、取消事件，或拦截 delegate 事件。
//
//  Created by Timur Kuchkarov on 28.03.14.
//  Copyright (c) 2014 GitHub. All rights reserved.
//

#import "UIImagePickerController+RACSignalSupport.h"
#import "RACDelegateProxy.h"
#import "RACSignal+Operations.h"
#import "NSObject+RACDeallocating.h"
#import "NSObject+RACDescription.h"
#import <objc/runtime.h>

@implementation UIImagePickerController (RACSignalSupport)

/**
 内部方法：设置 delegate 为 RACDelegateProxy，拦截 delegate 方法。
 @param self 当前 UIImagePickerController 实例
 实现原理：
 1. 判断当前 delegate 是否已为 rac_delegateProxy，若是则无需处理。
 2. 若不是，则将原 delegate 赋值给 rac_delegateProxy 的 rac_proxiedDelegate 属性。
 3. 再将 rac_delegateProxy 赋值为当前 delegate，实现 delegate 方法的拦截和信号转发。
*/
static void RACUseDelegateProxy(UIImagePickerController *self) {
	if (self.delegate == self.rac_delegateProxy) return;
    // 保存原有 delegate，便于后续消息转发
	self.rac_delegateProxy.rac_proxiedDelegate = self.delegate;
    // 设置代理为 RACDelegateProxy，实现信号拦截
	self.delegate = (id)self.rac_delegateProxy;
}

/**
 获取 RACDelegateProxy 代理对象。
 @return RACDelegateProxy 代理对象。
 实现原理：
 1. 通过 objc_getAssociatedObject 获取已存在的代理对象。
 2. 若不存在，则新建一个基于 UIImagePickerControllerDelegate 协议的代理对象，并通过 objc_setAssociatedObject 绑定。
 3. 保证每个 UIImagePickerController 实例都有独立的代理对象。
*/
- (RACDelegateProxy *)rac_delegateProxy {
	RACDelegateProxy *proxy = objc_getAssociatedObject(self, _cmd);
	if (proxy == nil) {
		proxy = [[RACDelegateProxy alloc] initWithProtocol:@protocol(UIImagePickerControllerDelegate)];
		objc_setAssociatedObject(self, _cmd, proxy, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	}
    return proxy;
}

/**
 返回一个信号对象，用于监听用户选择图片的事件。
 @return RACSignal<NSDictionary *>：每次选择图片时发送图片信息字典，用户取消或控件销毁时信号自动完成。
 实现原理：
 1. 监听 imagePickerController:didFinishPickingMediaWithInfo: 事件，提取图片信息。
 2. 监听 imagePickerControllerDidCancel: 事件和控件销毁信号，作为 takeUntil 的终止条件。
 3. setNameWithFormat 便于调试。
 4. 最后调用 RACUseDelegateProxy，确保 delegate 被正确代理。
*/
- (RACSignal *)rac_imageSelectedSignal {
	RACSignal *pickerCancelledSignal = [[self.rac_delegateProxy
		signalForSelector:@selector(imagePickerControllerDidCancel:)]
		merge:self.rac_willDeallocSignal];
		
	RACSignal *imagePickerSignal = [[[[self.rac_delegateProxy
		signalForSelector:@selector(imagePickerController:didFinishPickingMediaWithInfo:)]
		reduceEach:^(UIImagePickerController *pickerController, NSDictionary *userInfo) {
			return userInfo;
		}]
		takeUntil:pickerCancelledSignal]
		setNameWithFormat:@"%@ -rac_imageSelectedSignal", RACDescription(self)];
    // 确保 delegate 被正确代理，实现信号拦截
	RACUseDelegateProxy(self);
    return imagePickerSignal;
}

@end
