//
//  RACBlockTrampoline.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 10/21/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACBlockTrampoline.h"
#import "RACTuple.h"

/**
 * @class RACBlockTrampoline
 * @brief 用于动态调用任意参数个数Block的工具类。
 * @discussion 该类通过OC运行时机制，支持以元组方式传递参数并动态调用Block，常用于参数数量不定的场景。
 */
@interface RACBlockTrampoline ()

/**
 * @brief 被包装的Block对象。
 * @discussion 只读属性，保存需要被动态调用的Block。
 */
@property (nonatomic, readonly, copy) id block;
@end

@implementation RACBlockTrampoline

#pragma mark API

/**
 * @brief 以Block初始化RACBlockTrampoline实例。
 * @param block 需要被包装的Block。
 * @return 返回RACBlockTrampoline对象。
 * @discussion 用于将Block包装为可动态调用的对象。
 * @实现原理 直接拷贝Block并赋值。
 */
- (instancetype)initWithBlock:(id)block {
	self = [super init];

	_block = [block copy];

	return self;
}

/**
 * @brief 静态方法，动态调用Block并传递参数。
 * @param block 需要被调用的Block。
 * @param arguments 参数元组（RACTuple）。
 * @return Block的返回值。
 * @discussion 适用于参数数量不定的Block调用。
 * @实现原理 先用Block初始化trampoline对象，再调用invokeWithArguments:。
 */
+ (id)invokeBlock:(id)block withArguments:(RACTuple *)arguments {
	NSCParameterAssert(block != NULL);

	RACBlockTrampoline *trampoline = [(RACBlockTrampoline *)[self alloc] initWithBlock:block];
	return [trampoline invokeWithArguments:arguments];
}

/**
 * @brief 动态调用Block并传递参数。
 * @param arguments 参数元组（RACTuple）。
 * @return Block的返回值。
 * @discussion 适用于参数数量不定的Block调用。
 * @实现原理 分为三步：
 * 1. 根据参数个数获取对应的selector。
 * 2. 构造NSInvocation并设置参数。
 * 3. 调用并获取返回值。
 */
- (id)invokeWithArguments:(RACTuple *)arguments {
	// 1. 获取selector
	SEL selector = [self selectorForArgumentCount:arguments.count];
	NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:selector]];
	invocation.selector = selector;
	invocation.target = self;

	// 2. 设置参数
	for (NSUInteger i = 0; i < arguments.count; i++) {
		id arg = arguments[i];
		NSInteger argIndex = (NSInteger)(i + 2);
		[invocation setArgument:&arg atIndex:argIndex];
	}

	// 3. 调用并获取返回值
	[invocation invoke];
	
	__unsafe_unretained id returnVal;
	[invocation getReturnValue:&returnVal];
	return returnVal;
}

/**
 * @brief 根据参数个数返回对应的selector。
 * @param count 参数个数。
 * @return 对应的selector。
 * @discussion 用于动态选择Block调用方法。
 * @实现原理 通过switch语句映射参数个数到performWith:...方法，最多支持15个参数。
 */
- (SEL)selectorForArgumentCount:(NSUInteger)count {
	NSCParameterAssert(count > 0);

	switch (count) {
		case 0: return NULL;
		case 1: return @selector(performWith:);
		case 2: return @selector(performWith::);
		case 3: return @selector(performWith:::);
		case 4: return @selector(performWith::::);
		case 5: return @selector(performWith:::::);
		case 6: return @selector(performWith::::::);
		case 7: return @selector(performWith:::::::);
		case 8: return @selector(performWith::::::::);
		case 9: return @selector(performWith:::::::::);
		case 10: return @selector(performWith::::::::::);
		case 11: return @selector(performWith:::::::::::);
		case 12: return @selector(performWith::::::::::::);
		case 13: return @selector(performWith:::::::::::::);
		case 14: return @selector(performWith::::::::::::::);
		case 15: return @selector(performWith:::::::::::::::);
	}

	NSCAssert(NO, @"The argument count is too damn high! Only blocks of up to 15 arguments are currently supported.");
	return NULL;
}

/**
 * @brief 动态调用1~15个参数的Block。
 * @param obj1~obj15 依次为Block的参数。
 * @return Block的返回值。
 * @discussion 这些方法由selectorForArgumentCount:动态选择，分别对应不同参数个数的Block调用。
 * @实现原理 直接将参数传递给block并返回结果。
 */
- (id)performWith:(id)obj1 {
	id (^block)(id) = self.block;
	return block(obj1);
}

- (id)performWith:(id)obj1 :(id)obj2 {
	id (^block)(id, id) = self.block;
	return block(obj1, obj2);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 {
	id (^block)(id, id, id) = self.block;
	return block(obj1, obj2, obj3);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 {
	id (^block)(id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 {
	id (^block)(id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 {
	id (^block)(id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 {
	id (^block)(id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 {
	id (^block)(id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 {
	id (^block)(id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 {
	id (^block)(id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 :(id)obj11 {
	id (^block)(id, id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10, obj11);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 :(id)obj11 :(id)obj12 {
	id (^block)(id, id, id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10, obj11, obj12);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 :(id)obj11 :(id)obj12 :(id)obj13 {
	id (^block)(id, id, id, id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10, obj11, obj12, obj13);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 :(id)obj11 :(id)obj12 :(id)obj13 :(id)obj14 {
	id (^block)(id, id, id, id, id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10, obj11, obj12, obj13, obj14);
}

- (id)performWith:(id)obj1 :(id)obj2 :(id)obj3 :(id)obj4 :(id)obj5 :(id)obj6 :(id)obj7 :(id)obj8 :(id)obj9 :(id)obj10 :(id)obj11 :(id)obj12 :(id)obj13 :(id)obj14 :(id)obj15 {
	id (^block)(id, id, id, id, id, id, id, id, id, id, id, id, id, id, id) = self.block;
	return block(obj1, obj2, obj3, obj4, obj5, obj6, obj7, obj8, obj9, obj10, obj11, obj12, obj13, obj14, obj15);
}

@end
