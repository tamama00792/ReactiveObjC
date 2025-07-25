//
//  RACEvent.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2013-01-07.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACEvent.h"

/**
 * @class RACEvent
 * @brief 表示信号流中的事件（next、error、completed）。
 * @discussion 用于统一封装Reactive流中的各种事件，便于事件流处理和调试。
 */
@interface RACEvent ()

/**
 * @brief 与事件关联的对象。
 * @discussion 对于error和value属性，分别为NSError或普通值。
 */
@property (nonatomic, strong, readonly) id object;

/**
 * @brief 以事件类型和对象初始化。
 * @param type 事件类型。
 * @param object 关联对象。
 * @return 返回RACEvent对象。
 */
- (instancetype)initWithEventType:(RACEventType)type object:(id)object;

@end

@implementation RACEvent

#pragma mark Properties

/**
 * @brief 判断事件是否为终止事件（completed或error）。
 * @return YES表示已结束，NO表示未结束。
 */
- (BOOL)isFinished {
	return self.eventType == RACEventTypeCompleted || self.eventType == RACEventTypeError;
}

/**
 * @brief 获取事件中的错误对象。
 * @return 若为error事件则返回NSError，否则为nil。
 */
- (NSError *)error {
	return (self.eventType == RACEventTypeError ? self.object : nil);
}

/**
 * @brief 获取事件中的值。
 * @return 若为next事件则返回值，否则为nil。
 */
- (id)value {
	return (self.eventType == RACEventTypeNext ? self.object : nil);
}

#pragma mark Lifecycle

/**
 * @brief 获取completed事件单例。
 * @return 返回completed事件对象。
 */
+ (instancetype)completedEvent {
	static dispatch_once_t pred;
	static id singleton;

	dispatch_once(&pred, ^{
		singleton = [[self alloc] initWithEventType:RACEventTypeCompleted object:nil];
	});

	return singleton;
}

/**
 * @brief 创建error事件。
 * @param error 错误对象。
 * @return 返回error事件对象。
 */
+ (instancetype)eventWithError:(NSError *)error {
	return [[self alloc] initWithEventType:RACEventTypeError object:error];
}

/**
 * @brief 创建next事件。
 * @param value 值对象。
 * @return 返回next事件对象。
 */
+ (instancetype)eventWithValue:(id)value {
	return [[self alloc] initWithEventType:RACEventTypeNext object:value];
}

/**
 * @brief 以事件类型和对象初始化。
 * @param type 事件类型。
 * @param object 关联对象。
 * @return 返回RACEvent对象。
 */
- (instancetype)initWithEventType:(RACEventType)type object:(id)object {
	self = [super init];

	_eventType = type;
	_object = object;

	return self;
}

#pragma mark NSCopying

/**
 * @brief 拷贝事件对象。
 * @param zone 内存区域。
 * @return 返回自身（事件对象不可变）。
 */
- (id)copyWithZone:(NSZone *)zone {
	return self;
}

#pragma mark NSObject

/**
 * @brief 返回事件描述信息。
 * @return 包含事件类型和内容的字符串。
 */
- (NSString *)description {
	NSString *eventDescription = nil;

	switch (self.eventType) {
		case RACEventTypeCompleted:
			eventDescription = @"completed";
			break;

		case RACEventTypeError:
			eventDescription = [NSString stringWithFormat:@"error = %@", self.object];
			break;

		case RACEventTypeNext:
			eventDescription = [NSString stringWithFormat:@"next = %@", self.object];
			break;

		default:
			NSCAssert(NO, @"Unrecognized event type: %i", (int)self.eventType);
	}

	return [NSString stringWithFormat:@"<%@: %p>{ %@ }", self.class, self, eventDescription];
}

/**
 * @brief 获取事件哈希值。
 * @return 哈希值。
 */
- (NSUInteger)hash {
	return self.eventType ^ [self.object hash];
}

/**
 * @brief 判断事件是否相等。
 * @param event 另一个事件对象。
 * @return YES表示相等，NO表示不等。
 */
- (BOOL)isEqual:(id)event {
	if (event == self) return YES;
	if (![event isKindOfClass:RACEvent.class]) return NO;
	if (self.eventType != [event eventType]) return NO;

	// Catches the nil case too.
	return self.object == [event object] || [self.object isEqual:[event object]];
}

@end
