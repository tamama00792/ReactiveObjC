//
//  RACDelegateProxy.m
//  ReactiveObjC
//
//  Created by Cody Krieger on 5/19/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACDelegateProxy.h"
#import "NSObject+RACSelectorSignal.h"
#import <objc/runtime.h>

/**
 * @class RACDelegateProxy
 * @brief 用于动态代理协议方法并转为信号的代理对象。
 * @discussion 该类可拦截协议方法调用并将其转为RACSignal，常用于KVO、事件转信号等场景。
 */
@interface RACDelegateProxy () {
	// 保存代理协议指针，避免与方法名冲突。
	Protocol *_protocol;
}

@end

@implementation RACDelegateProxy

#pragma mark Lifecycle

/**
 * @brief 以协议初始化代理对象。
 * @param protocol 需要代理的协议。
 * @return 返回RACDelegateProxy实例。
 * @discussion 动态为类添加协议，并保存协议指针。
 */
- (instancetype)initWithProtocol:(Protocol *)protocol {
	NSCParameterAssert(protocol != NULL);

	self = [super init];

	class_addProtocol(self.class, protocol);

	_protocol = protocol;

	return self;
}

#pragma mark API

/**
 * @brief 获取指定selector对应的信号。
 * @param selector 需要监听的方法选择器。
 * @return 返回RACSignal对象。
 * @discussion 用于将协议方法调用转为信号。
 */
- (RACSignal *)signalForSelector:(SEL)selector {
	return [self rac_signalForSelector:selector fromProtocol:_protocol];
}

#pragma mark NSObject

/**
 * @brief 标记当前对象为代理。
 * @return 始终返回YES。
 */
- (BOOL)isProxy {
	return YES;
}

/**
 * @brief 转发方法调用到实际代理对象。
 * @param invocation 方法调用对象。
 * @discussion 用于将方法调用转发给真实代理。
 */
- (void)forwardInvocation:(NSInvocation *)invocation {
	[invocation invokeWithTarget:self.rac_proxiedDelegate];
}

/**
 * @brief 获取指定selector的方法签名。
 * @param selector 方法选择器。
 * @return 返回方法签名对象。
 * @discussion 优先查找可选方法，找不到再查找必选方法，均找不到则调用父类实现。
 */
- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector {
	// 查找可选实例方法描述。
	struct objc_method_description methodDescription = protocol_getMethodDescription(_protocol, selector, NO, YES);

	if (methodDescription.name == NULL) {
		// 查找必选实例方法描述。
		methodDescription = protocol_getMethodDescription(_protocol, selector, YES, YES);
		if (methodDescription.name == NULL) return [super methodSignatureForSelector:selector];
	}

	return [NSMethodSignature signatureWithObjCTypes:methodDescription.types];
}

/**
 * @brief 判断代理对象是否响应指定selector。
 * @param selector 方法选择器。
 * @return YES表示响应，NO表示不响应。
 * @discussion 优先判断真实代理对象，若不响应则调用父类实现。
 */
- (BOOL)respondsToSelector:(SEL)selector {
	// 加入自动释放池，防止代理对象在调用期间被释放。
	__autoreleasing id delegate = self.rac_proxiedDelegate;
	if ([delegate respondsToSelector:selector]) return YES;
    
	return [super respondsToSelector:selector];
}

@end
