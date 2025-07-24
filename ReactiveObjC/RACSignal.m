//
//  RACSignal.m
//  ReactiveObjC
//
//  Created by Josh Abernathy on 3/15/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSignal.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACDynamicSignal.h"
#import "RACEmptySignal.h"
#import "RACErrorSignal.h"
#import "RACMulticastConnection.h"
#import "RACReplaySubject.h"
#import "RACReturnSignal.h"
#import "RACScheduler.h"
#import "RACSerialDisposable.h"
#import "RACSignal+Operations.h"
#import "RACSubject.h"
#import "RACSubscriber+Private.h"
#import "RACTuple.h"
#import <libkern/OSAtomic.h>

@implementation RACSignal

#pragma mark Lifecycle

// 创建一个信号，订阅时会调用 didSubscribe block。
// 实现原理：实际调用 RACDynamicSignal 的 createSignal 方法，将 didSubscribe block 传递下去，RACDynamicSignal 负责信号的具体实现。
+ (RACSignal *)createSignal:(RACDisposable * (^)(id<RACSubscriber> subscriber))didSubscribe {
	return [RACDynamicSignal createSignal:didSubscribe];
}

// 创建一个只会发送 error 的信号。
// 实现原理：调用 RACErrorSignal 的 error: 方法，返回一个只会发送 error 事件的信号。
+ (RACSignal *)error:(NSError *)error {
	return [RACErrorSignal error:error];
}

// 创建一个永远不会发送任何事件的信号。
// 实现原理：创建一个信号，订阅时什么都不做，返回 nil，不会发送任何事件。
+ (RACSignal *)never {
	return [[self createSignal:^ RACDisposable * (id<RACSubscriber> subscriber) {
		return nil;
	}] setNameWithFormat:@"+never"];
}

// 立即在指定调度器上执行 block，并返回对应的信号。
// 实现原理：先通过 startLazilyWithScheduler 创建信号，然后主动订阅一次，确保 block 立即执行。
+ (RACSignal *)startEagerlyWithScheduler:(RACScheduler *)scheduler block:(void (^)(id<RACSubscriber> subscriber))block {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(block != NULL);

	RACSignal *signal = [self startLazilyWithScheduler:scheduler block:block];
	// Subscribe to force the lazy signal to call its block.
	[[signal publish] connect];
	return [signal setNameWithFormat:@"+startEagerlyWithScheduler: %@ block:", scheduler];
}

// 延迟在指定调度器上执行 block，只有订阅时才会执行。
// 实现原理：通过 multicast 机制，只有真正有订阅者时才会执行 block，且 block 只会执行一次。
+ (RACSignal *)startLazilyWithScheduler:(RACScheduler *)scheduler block:(void (^)(id<RACSubscriber> subscriber))block {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(block != NULL);

	RACMulticastConnection *connection = [[RACSignal
		createSignal:^ id (id<RACSubscriber> subscriber) {
			block(subscriber);
			return nil;
		}]
		multicast:[RACReplaySubject subject]];
	
	return [[[RACSignal
		createSignal:^ id (id<RACSubscriber> subscriber) {
			[connection.signal subscribe:subscriber];
			[connection connect];
			return nil;
		}]
		subscribeOn:scheduler]
		setNameWithFormat:@"+startLazilyWithScheduler: %@ block:", scheduler];
}

#pragma mark NSObject

// 返回信号的描述信息。
// 实现原理：格式化输出类名、内存地址和 name 属性。
- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p> name: %@", self.class, self, self.name];
}

@end

@implementation RACSignal (RACStream)

// 创建一个空信号，不会发送任何值，只会发送 completed。
// 实现原理：调用 RACEmptySignal 的 empty 方法，返回一个只发送 completed 的信号。
+ (RACSignal *)empty {
	return [RACEmptySignal empty];
}

// 创建一个只发送一个值并完成的信号。
// 实现原理：调用 RACReturnSignal 的 return: 方法，返回一个只发送 value 并 completed 的信号。
+ (RACSignal *)return:(id)value {
	return [RACReturnSignal return:value];
}

// 绑定操作，将信号的每个值通过 block 转换为新的信号，并将所有信号合并输出。
// 实现原理：对每个输入值，调用 bindingBlock 得到新的信号并订阅，将所有信号的值合并输出，所有信号完成后才发送 completed。
- (RACSignal *)bind:(RACSignalBindBlock (^)(void))block {
	NSCParameterAssert(block != NULL);

	/*
	 * -bind: should:
	 * 
	 * 1. Subscribe to the original signal of values.
	 * 2. Any time the original signal sends a value, transform it using the binding block.
	 * 3. If the binding block returns a signal, subscribe to it, and pass all of its values through to the subscriber as they're received.
	 * 4. If the binding block asks the bind to terminate, complete the _original_ signal.
	 * 5. When _all_ signals complete, send completed to the subscriber.
	 * 
	 * If any signal sends an error at any point, send that to the subscriber.
	 */

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		RACSignalBindBlock bindingBlock = block();

		__block volatile int32_t signalCount = 1;   // indicates self

		RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

		void (^completeSignal)(RACDisposable *) = ^(RACDisposable *finishedDisposable) {
			if (OSAtomicDecrement32Barrier(&signalCount) == 0) {
				[subscriber sendCompleted];
				[compoundDisposable dispose];
			} else {
				[compoundDisposable removeDisposable:finishedDisposable];
			}
		};

		void (^addSignal)(RACSignal *) = ^(RACSignal *signal) {
			OSAtomicIncrement32Barrier(&signalCount);

			RACSerialDisposable *selfDisposable = [[RACSerialDisposable alloc] init];
			[compoundDisposable addDisposable:selfDisposable];

			RACDisposable *disposable = [signal subscribeNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[compoundDisposable dispose];
				[subscriber sendError:error];
			} completed:^{
				@autoreleasepool {
					completeSignal(selfDisposable);
				}
			}];

			selfDisposable.disposable = disposable;
		};

		@autoreleasepool {
			RACSerialDisposable *selfDisposable = [[RACSerialDisposable alloc] init];
			[compoundDisposable addDisposable:selfDisposable];

			RACDisposable *bindingDisposable = [self subscribeNext:^(id x) {
				// Manually check disposal to handle synchronous errors.
				if (compoundDisposable.disposed) return;

				BOOL stop = NO;
				id signal = bindingBlock(x, &stop);

				@autoreleasepool {
					if (signal != nil) addSignal(signal);
					if (signal == nil || stop) {
						[selfDisposable dispose];
						completeSignal(selfDisposable);
					}
				}
			} error:^(NSError *error) {
				[compoundDisposable dispose];
				[subscriber sendError:error];
			} completed:^{
				@autoreleasepool {
					completeSignal(selfDisposable);
				}
			}];

			selfDisposable.disposable = bindingDisposable;
		}

		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -bind:", self.name];
}

// 连接操作，将当前信号和另一个信号顺序连接，前者完成后订阅后者。
// 实现原理：先订阅当前信号，收到 completed 后再订阅下一个信号。
- (RACSignal *)concat:(RACSignal *)signal {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		RACCompoundDisposable *compoundDisposable = [[RACCompoundDisposable alloc] init];

		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			RACDisposable *concattedDisposable = [signal subscribe:subscriber];
			[compoundDisposable addDisposable:concattedDisposable];
		}];

		[compoundDisposable addDisposable:sourceDisposable];
		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -concat: %@", self.name, signal];
}

// 拉链操作，将两个信号的值一一配对成元组输出。
// 实现原理：分别缓存两个信号的值，只有两个信号各有一个值时才组合成元组输出，任一信号完成且缓存为空时发送 completed。
- (RACSignal *)zipWith:(RACSignal *)signal {
	NSCParameterAssert(signal != nil);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block BOOL selfCompleted = NO;
		NSMutableArray *selfValues = [NSMutableArray array];

		__block BOOL otherCompleted = NO;
		NSMutableArray *otherValues = [NSMutableArray array];

		void (^sendCompletedIfNecessary)(void) = ^{
			@synchronized (selfValues) {
				BOOL selfEmpty = (selfCompleted && selfValues.count == 0);
				BOOL otherEmpty = (otherCompleted && otherValues.count == 0);
				if (selfEmpty || otherEmpty) [subscriber sendCompleted];
			}
		};

		void (^sendNext)(void) = ^{
			@synchronized (selfValues) {
				if (selfValues.count == 0) return;
				if (otherValues.count == 0) return;

				RACTuple *tuple = RACTuplePack(selfValues[0], otherValues[0]);
				[selfValues removeObjectAtIndex:0];
				[otherValues removeObjectAtIndex:0];

				[subscriber sendNext:tuple];
				sendCompletedIfNecessary();
			}
		};

		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			@synchronized (selfValues) {
				[selfValues addObject:x ?: RACTupleNil.tupleNil];
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (selfValues) {
				selfCompleted = YES;
				sendCompletedIfNecessary();
			}
		}];

		RACDisposable *otherDisposable = [signal subscribeNext:^(id x) {
			@synchronized (selfValues) {
				[otherValues addObject:x ?: RACTupleNil.tupleNil];
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (selfValues) {
				otherCompleted = YES;
				sendCompletedIfNecessary();
			}
		}];

		return [RACDisposable disposableWithBlock:^{
			[selfDisposable dispose];
			[otherDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -zipWith: %@", self.name, signal];
}

@end

@implementation RACSignal (Subscription)

// 订阅信号，必须由子类实现。
// 实现原理：基类抛出断言，实际由子类实现具体订阅逻辑。
- (RACDisposable *)subscribe:(id<RACSubscriber>)subscriber {
	NSCAssert(NO, @"This method must be overridden by subclasses");
	return nil;
}

// 只订阅 next 事件。
// 实现原理：创建一个只处理 next 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock {
	NSCParameterAssert(nextBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:NULL];
	return [self subscribe:o];
}

// 订阅 next 和 completed 事件。
// 实现原理：创建一个处理 next 和 completed 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:NULL completed:completedBlock];
	return [self subscribe:o];
}

// 订阅 next、error 和 completed 事件。
// 实现原理：创建一个处理 next、error、completed 的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

// 只订阅 error 事件。
// 实现原理：创建一个只处理 error 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeError:(void (^)(NSError *error))errorBlock {
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:NULL];
	return [self subscribe:o];
}

// 只订阅 completed 事件。
// 实现原理：创建一个只处理 completed 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeCompleted:(void (^)(void))completedBlock {
	NSCParameterAssert(completedBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:NULL completed:completedBlock];
	return [self subscribe:o];
}

// 订阅 next 和 error 事件。
// 实现原理：创建一个处理 next 和 error 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeNext:(void (^)(id x))nextBlock error:(void (^)(NSError *error))errorBlock {
	NSCParameterAssert(nextBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:nextBlock error:errorBlock completed:NULL];
	return [self subscribe:o];
}

// 订阅 error 和 completed 事件。
// 实现原理：创建一个处理 error 和 completed 事件的 RACSubscriber，并调用 subscribe: 方法。
- (RACDisposable *)subscribeError:(void (^)(NSError *))errorBlock completed:(void (^)(void))completedBlock {
	NSCParameterAssert(completedBlock != NULL);
	NSCParameterAssert(errorBlock != NULL);
	
	RACSubscriber *o = [RACSubscriber subscriberWithNext:NULL error:errorBlock completed:completedBlock];
	return [self subscribe:o];
}

@end

@implementation RACSignal (Debugging)

// 打印所有事件（next、error、completed）。
// 实现原理：依次调用 logNext、logError、logCompleted，对每种事件分别打印日志。
- (RACSignal *)logAll {
	return [[[self logNext] logError] logCompleted];
}

// 打印 next 事件。
// 实现原理：通过 doNext 拦截 next 事件并打印日志。
- (RACSignal *)logNext {
	return [[self doNext:^(id x) {
		NSLog(@"%@ next: %@", self, x);
	}] setNameWithFormat:@"%@", self.name];
}

// 打印 error 事件。
// 实现原理：通过 doError 拦截 error 事件并打印日志。
- (RACSignal *)logError {
	return [[self doError:^(NSError *error) {
		NSLog(@"%@ error: %@", self, error);
	}] setNameWithFormat:@"%@", self.name];
}

// 打印 completed 事件。
// 实现原理：通过 doCompleted 拦截 completed 事件并打印日志。
- (RACSignal *)logCompleted {
	return [[self doCompleted:^{
		NSLog(@"%@ completed", self);
	}] setNameWithFormat:@"%@", self.name];
}

@end

@implementation RACSignal (Testing)

static const NSTimeInterval RACSignalAsynchronousWaitTimeout = 10;

// 异步获取第一个值，或返回默认值。
// 实现原理：订阅信号，获取第一个 next 事件的值，超时或 error 时返回默认值或错误。
- (id)asynchronousFirstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error {
	return [self asynchronousFirstOrDefault:defaultValue success:success error:error timeout:RACSignalAsynchronousWaitTimeout];
}

// 异步获取第一个值，或返回默认值，可设置超时时间。
// 实现原理：同上，允许自定义超时时间。
- (id)asynchronousFirstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error timeout:(NSTimeInterval)timeout {
	NSCAssert([NSThread isMainThread], @"%s should only be used from the main thread", __func__);

	__block id result = defaultValue;
	__block BOOL done = NO;

	// Ensures that we don't pass values across thread boundaries by reference.
	__block NSError *localError;
	__block BOOL localSuccess = YES;

	[[[[self
		take:1]
		timeout:timeout onScheduler:[RACScheduler scheduler]]
		deliverOn:RACScheduler.mainThreadScheduler]
		subscribeNext:^(id x) {
			result = x;
			done = YES;
		} error:^(NSError *e) {
			if (!done) {
				localSuccess = NO;
				localError = e;
				done = YES;
			}
		} completed:^{
			done = YES;
		}];
	
	do {
		[NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
	} while (!done);

	if (success != NULL) *success = localSuccess;
	if (error != NULL) *error = localError;

	return result;
}

// 等待信号完成，返回是否成功，可设置超时时间。
// 实现原理：通过 ignoreValues 忽略所有 next，只关心 completed 或 error，超时后返回结果。
- (BOOL)asynchronouslyWaitUntilCompleted:(NSError **)error timeout:(NSTimeInterval)timeout {
	BOOL success = NO;
	[[self ignoreValues] asynchronousFirstOrDefault:nil success:&success error:error timeout:timeout];
	return success;
}

// 等待信号完成，返回是否成功，默认超时时间。
// 实现原理：调用上一个方法，使用默认超时时间。
- (BOOL)asynchronouslyWaitUntilCompleted:(NSError **)error {
	return [self asynchronouslyWaitUntilCompleted:error timeout:RACSignalAsynchronousWaitTimeout];
}

@end
