//
//  RACSignal+Operations.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-09-06.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

/**
 * RACSignal+Operations.m
 * 
 * 这个文件是 ReactiveObjC 框架中信号操作的核心实现文件
 * 包含了所有 RACSignal 的操作方法，如 map、filter、combineLatest 等
 * 
 * 主要功能：
 * 1. 提供信号的各种转换操作（map、filter、flattenMap等）
 * 2. 提供信号的组合操作（combineLatest、merge、concat等）
 * 3. 提供信号的时间控制操作（delay、throttle、timeout等）
 * 4. 提供信号的错误处理操作（catch、retry等）
 * 5. 提供信号的调度操作（deliverOn、subscribeOn等）
 */

#import "RACSignal+Operations.h"
#import "NSObject+RACDeallocating.h"      // 对象销毁时的清理操作
#import "NSObject+RACDescription.h"       // 对象描述功能
#import "RACBlockTrampoline.h"           // 块调用桥接器
#import "RACCommand.h"                    // 命令模式实现
#import "RACCompoundDisposable.h"        // 复合可释放对象
#import "RACDisposable.h"                // 可释放对象基类
#import "RACEvent.h"                     // 事件封装
#import "RACGroupedSignal.h"             // 分组信号
#import "RACMulticastConnection+Private.h" // 多播连接私有接口
#import "RACReplaySubject.h"             // 重放主题
#import "RACScheduler.h"                 // 调度器
#import "RACSerialDisposable.h"          // 串行可释放对象
#import "RACSignalSequence.h"            // 信号序列
#import "RACStream+Private.h"            // 流私有接口
#import "RACSubject.h"                   // 主题
#import "RACSubscriber+Private.h"        // 订阅者私有接口
#import "RACSubscriber.h"                // 订阅者
#import "RACTuple.h"                     // 元组
#import "RACUnit.h"                      // 单位类型
#import <libkern/OSAtomic.h>            // 原子操作
#import <objc/runtime.h>                 // 运行时

/**
 * RACSignal 错误域常量
 * 用于标识信号相关的错误类型
 */
NSErrorDomain const RACSignalErrorDomain = @"RACSignalErrorDomain";

/**
 * subscribeForever 静态函数
 * 
 * 功能：永久订阅给定的信号，当信号完成或出错时会自动重新订阅
 * 
 * 参数说明：
 * @param signal 要订阅的信号
 * @param next 处理下一个值的块
 * @param error 处理错误的块，接收错误对象和可释放对象
 * @param completed 处理完成事件的块，接收可释放对象
 * 
 * 返回值：RACDisposable 对象，用于取消订阅
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理所有订阅
 * 2. 通过递归调度器实现自动重新订阅
 * 3. 当信号完成或出错时，如果可释放对象未被释放，则重新订阅
 * 4. 使用弱引用避免循环引用
 */
static RACDisposable *subscribeForever (RACSignal *signal, void (^next)(id), void (^error)(NSError *, RACDisposable *), void (^completed)(RACDisposable *)) {
	// 复制块以避免在异步环境中被释放
	next = [next copy];
	error = [error copy];
	completed = [completed copy];

	// 创建复合可释放对象来管理所有订阅
	RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

	// 定义递归块，用于处理重新订阅逻辑
	RACSchedulerRecursiveBlock recursiveBlock = ^(void (^recurse)(void)) {
		// 为当前订阅创建独立的可释放对象
		RACCompoundDisposable *selfDisposable = [RACCompoundDisposable compoundDisposable];
		[compoundDisposable addDisposable:selfDisposable];

		// 使用弱引用避免循环引用
		__weak RACDisposable *weakSelfDisposable = selfDisposable;

		// 订阅信号
		RACDisposable *subscriptionDisposable = [signal subscribeNext:next error:^(NSError *e) {
			@autoreleasepool {
				// 调用错误处理块
				error(e, compoundDisposable);
				// 从复合可释放对象中移除当前订阅
				[compoundDisposable removeDisposable:weakSelfDisposable];
			}

			// 递归调用，重新订阅
			recurse();
		} completed:^{
			@autoreleasepool {
				// 调用完成处理块
				completed(compoundDisposable);
				// 从复合可释放对象中移除当前订阅
				[compoundDisposable removeDisposable:weakSelfDisposable];
			}

			// 递归调用，重新订阅
			recurse();
		}];

		// 将订阅的可释放对象添加到当前可释放对象中
		[selfDisposable addDisposable:subscriptionDisposable];
	};

	// 立即订阅一次，然后使用递归调度进行任何进一步的重新订阅
	recursiveBlock(^{
		// 获取当前调度器，如果没有则创建新的
		RACScheduler *recursiveScheduler = RACScheduler.currentScheduler ?: [RACScheduler scheduler];

		// 使用递归调度器安排递归块
		RACDisposable *schedulingDisposable = [recursiveScheduler scheduleRecursiveBlock:recursiveBlock];
		[compoundDisposable addDisposable:schedulingDisposable];
	});

	return compoundDisposable;
}

@implementation RACSignal (Operations)

/**
 * doNext 方法
 * 
 * 功能：在信号发送下一个值之前执行副作用操作，但不改变信号的值流
 * 
 * 参数说明：
 * @param block 要执行的副作用块，接收信号发送的值
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 日志记录：在值发送前打印日志
 * 2. 调试：观察信号的值流
 * 3. 副作用操作：如更新UI状态、保存数据等
 * 
 * 实现原理：
 * 1. 创建新的信号
 * 2. 订阅原信号
 * 3. 在发送值给订阅者之前先执行副作用块
 * 4. 保持原信号的值流不变
 */
- (RACSignal *)doNext:(void (^)(id x))block {
	NSCParameterAssert(block != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			// 先执行副作用操作
			block(x);
			// 然后发送值给订阅者
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}] setNameWithFormat:@"[%@] -doNext:", self.name];
}

/**
 * doError 方法
 * 
 * 功能：在信号发送错误之前执行副作用操作
 * 
 * 参数说明：
 * @param block 要执行的副作用块，接收错误对象
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 错误日志记录
 * 2. 错误统计
 * 3. 错误处理前的准备工作
 * 
 * 实现原理：
 * 1. 创建新的信号
 * 2. 订阅原信号
 * 3. 在发送错误给订阅者之前先执行副作用块
 * 4. 保持原信号的错误流不变
 */
- (RACSignal *)doError:(void (^)(NSError *error))block {
	NSCParameterAssert(block != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			// 先执行副作用操作
			block(error);
			// 然后发送错误给订阅者
			[subscriber sendError:error];
		} completed:^{
			[subscriber sendCompleted];
		}];
	}] setNameWithFormat:@"[%@] -doError:", self.name];
}

/**
 * doCompleted 方法
 * 
 * 功能：在信号完成之前执行副作用操作
 * 
 * 参数说明：
 * @param block 要执行的副作用块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 完成时的清理工作
 * 2. 完成时的状态更新
 * 3. 完成时的日志记录
 * 
 * 实现原理：
 * 1. 创建新的信号
 * 2. 订阅原信号
 * 3. 在发送完成事件给订阅者之前先执行副作用块
 * 4. 保持原信号的完成流不变
 */
- (RACSignal *)doCompleted:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			// 先执行副作用操作
			block();
			// 然后发送完成事件给订阅者
			[subscriber sendCompleted];
		}];
	}] setNameWithFormat:@"[%@] -doCompleted:", self.name];
}

/**
 * throttle 方法（简化版本）
 * 
 * 功能：对信号进行节流操作，限制信号发送值的频率
 * 
 * 参数说明：
 * @param interval 节流时间间隔（秒）
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 防止按钮快速点击
 * 2. 限制网络请求频率
 * 3. 优化UI更新频率
 * 
 * 实现原理：
 * 调用带谓词的 throttle 方法，对所有值都进行节流
 */
- (RACSignal *)throttle:(NSTimeInterval)interval {
	return [[self throttle:interval valuesPassingTest:^(id _) {
		return YES;
	}] setNameWithFormat:@"[%@] -throttle: %f", self.name, (double)interval];
}

/**
 * throttle 方法（完整版本）
 * 
 * 功能：对信号进行节流操作，只对满足条件的值进行节流
 * 
 * 参数说明：
 * @param interval 节流时间间隔（秒）
 * @param predicate 谓词块，决定哪些值需要节流
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 只对特定类型的值进行节流
 * 2. 根据业务逻辑决定是否节流
 * 3. 更精细的节流控制
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理订阅
 * 2. 使用串行可释放对象管理延迟操作
 * 3. 通过谓词判断是否需要节流
 * 4. 使用延迟调度器实现节流效果
 * 5. 通过同步锁保证线程安全
 */
- (RACSignal *)throttle:(NSTimeInterval)interval valuesPassingTest:(BOOL (^)(id next))predicate {
	NSCParameterAssert(interval >= 0);
	NSCParameterAssert(predicate != nil);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理所有订阅
		RACCompoundDisposable *compoundDisposable = [RACCompoundDisposable compoundDisposable];

		// 设置调度器，确保调度的块按顺序执行
		RACScheduler *scheduler = [RACScheduler scheduler];

		// 当前缓冲的 next 事件信息
		__block id nextValue = nil;           // 缓冲的值
		__block BOOL hasNextValue = NO;       // 是否有缓冲值
		RACSerialDisposable *nextDisposable = [[RACSerialDisposable alloc] init];

		/**
		 * flushNext 块
		 * 
		 * 功能：刷新缓冲的值
		 * 
		 * 参数说明：
		 * @param send 是否发送缓冲的值给订阅者
		 * 
		 * 实现逻辑：
		 * 1. 释放当前的延迟操作
		 * 2. 如果有缓冲值且需要发送，则发送给订阅者
		 * 3. 清空缓冲状态
		 */
		void (^flushNext)(BOOL send) = ^(BOOL send) {
			@synchronized (compoundDisposable) {
				// 释放当前的延迟操作
				[nextDisposable.disposable dispose];

				// 如果没有缓冲值，直接返回
				if (!hasNextValue) return;
				
				// 如果需要发送，则发送缓冲的值
				if (send) [subscriber sendNext:nextValue];

				// 清空缓冲状态
				nextValue = nil;
				hasNextValue = NO;
			}
		};

		// 订阅原信号
		RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
			// 获取延迟调度器
			RACScheduler *delayScheduler = RACScheduler.currentScheduler ?: scheduler;
			// 判断当前值是否需要节流
			BOOL shouldThrottle = predicate(x);

			@synchronized (compoundDisposable) {
				// 刷新之前的缓冲值（不发送）
				flushNext(NO);
				
				// 如果不需要节流，直接发送
				if (!shouldThrottle) {
					[subscriber sendNext:x];
					return;
				}

				// 需要节流，缓冲当前值
				nextValue = x;
				hasNextValue = YES;
				
				// 设置延迟操作，在指定时间后发送缓冲的值
				nextDisposable.disposable = [delayScheduler afterDelay:interval schedule:^{
					flushNext(YES);
				}];
			}
		} error:^(NSError *error) {
			[compoundDisposable dispose];
			[subscriber sendError:error];
		} completed:^{
			// 完成时发送所有缓冲的值
			flushNext(YES);
			[subscriber sendCompleted];
		}];

		[compoundDisposable addDisposable:subscriptionDisposable];
		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -throttle: %f valuesPassingTest:", self.name, (double)interval];
}

/**
 * delay 方法
 * 
 * 功能：延迟信号的所有事件（next、completed）发送
 * 
 * 参数说明：
 * @param interval 延迟时间间隔（秒）
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 模拟网络延迟
 * 2. 避免UI更新过于频繁
 * 3. 实现动画效果
 * 
 * 实现原理：
 * 1. 创建复合可释放对象管理所有订阅
 * 2. 使用调度器延迟执行所有事件
 * 3. 保持原信号的事件顺序和时间间隔
 * 4. 通过同步锁保证线程安全
 */
- (RACSignal *)delay:(NSTimeInterval)interval {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理所有订阅
		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

		// 设置调度器，确保调度的块按顺序执行
		RACScheduler *scheduler = [RACScheduler scheduler];

		/**
		 * schedule 块
		 * 
		 * 功能：延迟执行指定的块
		 * 
		 * 参数说明：
		 * @param block 要延迟执行的块
		 * 
		 * 实现逻辑：
		 * 1. 获取当前调度器或使用默认调度器
		 * 2. 在指定延迟后执行块
		 * 3. 将调度器的可释放对象添加到复合可释放对象中
		 */
		void (^schedule)(dispatch_block_t) = ^(dispatch_block_t block) {
			RACScheduler *delayScheduler = RACScheduler.currentScheduler ?: scheduler;
			RACDisposable *schedulerDisposable = [delayScheduler afterDelay:interval schedule:block];
			[disposable addDisposable:schedulerDisposable];
		};

		// 订阅原信号
		RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
			// 延迟发送下一个值
			schedule(^{
				[subscriber sendNext:x];
			});
		} error:^(NSError *error) {
			// 错误立即发送，不延迟
			[subscriber sendError:error];
		} completed:^{
			// 延迟发送完成事件
			schedule(^{
				[subscriber sendCompleted];
			});
		}];

		[disposable addDisposable:subscriptionDisposable];
		return disposable;
	}] setNameWithFormat:@"[%@] -delay: %f", self.name, (double)interval];
}

/**
 * repeat 方法
 * 
 * 功能：当信号完成时自动重新订阅，实现无限重复
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 轮询操作（如定时检查服务器状态）
 * 2. 重试机制
 * 3. 持续监控
 * 
 * 实现原理：
 * 1. 使用 subscribeForever 静态函数
 * 2. 当信号完成时自动重新订阅
 * 3. 当信号出错时停止重复并传递错误
 * 4. 通过递归调度器实现自动重新订阅
 */
- (RACSignal *)repeat {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return subscribeForever(self,
			^(id x) {
				// 直接传递下一个值
				[subscriber sendNext:x];
			},
			^(NSError *error, RACDisposable *disposable) {
				// 出错时停止重复并传递错误
				[disposable dispose];
				[subscriber sendError:error];
			},
			^(RACDisposable *disposable) {
				// 完成时继续重新订阅（不传递完成事件）
				// 这里不调用 [subscriber sendCompleted]，因为要重复
			});
	}] setNameWithFormat:@"[%@] -repeat", self.name];
}

/**
 * catch 方法
 * 
 * 功能：捕获信号中的错误，并用新的信号替换错误
 * 
 * 参数说明：
 * @param catchBlock 错误处理块，接收错误对象并返回新的信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 错误恢复：当网络请求失败时切换到本地缓存
 * 2. 错误转换：将特定错误转换为用户友好的错误
 * 3. 降级处理：主服务失败时使用备用服务
 * 
 * 实现原理：
 * 1. 创建串行可释放对象管理错误处理订阅
 * 2. 正常订阅原信号并传递值
 * 3. 当出错时，调用错误处理块获取新信号
 * 4. 订阅新信号并传递给原订阅者
 * 5. 确保所有订阅都能正确释放
 */
- (RACSignal *)catch:(RACSignal * (^)(NSError *error))catchBlock {
	NSCParameterAssert(catchBlock != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建串行可释放对象来管理错误处理的订阅
		RACSerialDisposable *catchDisposable = [[RACSerialDisposable alloc] init];

		// 订阅原信号
		RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
			// 正常传递值
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			// 当出错时，调用错误处理块获取新信号
			RACSignal *signal = catchBlock(error);
			NSCAssert(signal != nil, @"Expected non-nil signal from catch block on %@", self);
			// 订阅新信号并传递给原订阅者
			catchDisposable.disposable = [signal subscribe:subscriber];
		} completed:^{
			[subscriber sendCompleted];
		}];

		// 返回可释放对象，确保所有订阅都能正确释放
		return [RACDisposable disposableWithBlock:^{
			[catchDisposable dispose];
			[subscriptionDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -catch:", self.name];
}

/**
 * catchTo 方法
 * 
 * 功能：捕获信号中的错误，并用指定的信号替换错误
 * 
 * 参数说明：
 * @param signal 用于替换错误的信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 简单的错误恢复：总是使用同一个备用信号
 * 2. 默认值提供：出错时提供默认值
 * 3. 错误忽略：出错时切换到空信号
 * 
 * 实现原理：
 * 调用 catch 方法，错误处理块总是返回指定的信号
 */
- (RACSignal *)catchTo:(RACSignal *)signal {
	return [[self catch:^(NSError *error) {
		return signal;
	}] setNameWithFormat:@"[%@] -catchTo: %@", self.name, signal];
}

/**
 * try 类方法
 * 
 * 功能：将可能抛出错误的同步操作包装成信号
 * 
 * 参数说明：
 * @param tryBlock 可能抛出错误的同步块，通过 errorPtr 参数返回错误
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 文件操作：读取文件可能失败
 * 2. 数据解析：JSON解析可能失败
 * 3. 同步API调用：可能抛出异常的API调用
 * 
 * 实现原理：
 * 1. 同步执行 tryBlock
 * 2. 如果返回值为 nil 且有错误，发送错误信号
 * 3. 如果返回值不为 nil，发送成功信号
 * 4. 订阅结果信号并传递给订阅者
 */
+ (RACSignal *)try:(id (^)(NSError **errorPtr))tryBlock {
	NSCParameterAssert(tryBlock != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		NSError *error;
		// 执行可能抛出错误的同步操作
		id value = tryBlock(&error);
		// 根据结果创建相应的信号
		RACSignal *signal = (value == nil ? [RACSignal error:error] : [RACSignal return:value]);
		return [signal subscribe:subscriber];
	}] setNameWithFormat:@"+try:"];
}

/**
 * try: 方法
 * 
 * 功能：对信号中的每个值执行可能失败的验证操作
 * 
 * 参数说明：
 * @param tryBlock 验证块，接收值和错误指针，返回是否通过验证
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 数据验证：验证每个数据项是否有效
 * 2. 格式检查：检查数据格式是否正确
 * 3. 业务规则：验证数据是否符合业务规则
 * 
 * 实现原理：
 * 1. 使用 flattenMap 处理每个值
 * 2. 调用验证块检查值是否通过验证
 * 3. 如果通过验证，返回包含原值的信号
 * 4. 如果验证失败，返回包含错误的信号
 */
- (RACSignal *)try:(BOOL (^)(id value, NSError **errorPtr))tryBlock {
	NSCParameterAssert(tryBlock != NULL);

	return [[self flattenMap:^(id value) {
		NSError *error = nil;
		BOOL passed = tryBlock(value, &error);
		return (passed ? [RACSignal return:value] : [RACSignal error:error]);
	}] setNameWithFormat:@"[%@] -try:", self.name];
}

/**
 * tryMap: 方法
 * 
 * 功能：对信号中的每个值执行可能失败的转换操作
 * 
 * 参数说明：
 * @param mapBlock 转换块，接收值和错误指针，返回转换后的值
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 数据转换：将数据转换为其他格式
 * 2. 类型转换：将一种类型转换为另一种类型
 * 3. 数据解析：解析可能失败的数据
 * 
 * 实现原理：
 * 1. 使用 flattenMap 处理每个值
 * 2. 调用转换块进行值转换
 * 3. 如果转换成功，返回包含转换后值的信号
 * 4. 如果转换失败，返回包含错误的信号
 */
- (RACSignal *)tryMap:(id (^)(id value, NSError **errorPtr))mapBlock {
	NSCParameterAssert(mapBlock != NULL);

	return [[self flattenMap:^(id value) {
		NSError *error = nil;
		id mappedValue = mapBlock(value, &error);
		return (mappedValue == nil ? [RACSignal error:error] : [RACSignal return:mappedValue]);
	}] setNameWithFormat:@"[%@] -tryMap:", self.name];
}

/**
 * initially: 方法
 * 
 * 功能：在信号开始发送值之前执行指定的块
 * 
 * 参数说明：
 * @param block 要在信号开始时执行的块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 初始化操作：在信号开始前进行初始化
 * 2. 状态设置：设置初始状态
 * 3. 准备工作：在信号开始前做准备工作
 * 
 * 实现原理：
 * 1. 使用 defer 延迟创建信号
 * 2. 在信号创建时先执行指定的块
 * 3. 然后返回原信号
 */
- (RACSignal *)initially:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	return [[RACSignal defer:^{
		block();
		return self;
	}] setNameWithFormat:@"[%@] -initially:", self.name];
}

/**
 * finally: 方法
 * 
 * 功能：在信号完成或出错时执行指定的块
 * 
 * 参数说明：
 * @param block 要在信号结束时执行的块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 清理工作：在信号结束时进行清理
 * 2. 状态重置：重置相关状态
 * 3. 资源释放：释放相关资源
 * 
 * 实现原理：
 * 1. 使用 doError 在出错时执行块
 * 2. 使用 doCompleted 在完成时执行块
 * 3. 确保无论信号如何结束都会执行指定的块
 */
- (RACSignal *)finally:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	return [[[self
		doError:^(NSError *error) {
			block();
		}]
		doCompleted:^{
			block();
		}]
		setNameWithFormat:@"[%@] -finally:", self.name];
}

/**
 * bufferWithTime:onScheduler: 方法
 * 
 * 功能：将信号的值按时间间隔缓冲，然后批量发送
 * 
 * 参数说明：
 * @param interval 缓冲时间间隔（秒）
 * @param scheduler 调度器
 * 
 * 返回值：新的 RACSignal 对象，发送 RACTuple 类型的值
 * 
 * 使用场景：
 * 1. 批量处理：将多个值批量处理
 * 2. 性能优化：减少处理频率
 * 3. 数据聚合：将一段时间内的数据聚合
 * 
 * 实现原理：
 * 1. 使用数组存储缓冲的值
 * 2. 使用定时器控制缓冲时间
 * 3. 当定时器触发时，发送所有缓冲的值
 * 4. 使用同步锁保证线程安全
 */
- (RACSignal *)bufferWithTime:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(scheduler != RACScheduler.immediateScheduler);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建串行可释放对象管理定时器
		RACSerialDisposable *timerDisposable = [[RACSerialDisposable alloc] init];
		// 存储缓冲值的数组
		NSMutableArray *values = [NSMutableArray array];

		/**
		 * flushValues 块
		 * 
		 * 功能：刷新并发送所有缓冲的值
		 * 
		 * 实现逻辑：
		 * 1. 释放当前的定时器
		 * 2. 如果没有缓冲值，直接返回
		 * 3. 创建包含所有缓冲值的元组
		 * 4. 清空缓冲数组
		 * 5. 发送元组给订阅者
		 */
		void (^flushValues)(void) = ^{
			@synchronized (values) {
				[timerDisposable.disposable dispose];

				if (values.count == 0) return;

				RACTuple *tuple = [RACTuple tupleWithObjectsFromArray:values];
				[values removeAllObjects];
				[subscriber sendNext:tuple];
			}
		};

		// 订阅原信号
		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			@synchronized (values) {
				// 如果是第一个值，启动定时器
				if (values.count == 0) {
					timerDisposable.disposable = [scheduler afterDelay:interval schedule:flushValues];
				}

				// 将值添加到缓冲数组
				[values addObject:x ?: RACTupleNil.tupleNil];
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			// 完成时发送所有缓冲的值
			flushValues();
			[subscriber sendCompleted];
		}];

		return [RACDisposable disposableWithBlock:^{
			[selfDisposable dispose];
			[timerDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -bufferWithTime: %f onScheduler: %@", self.name, (double)interval, scheduler];
}

/**
 * collect 方法
 * 
 * 功能：将信号的所有值收集到数组中
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送包含所有值的数组
 * 
 * 使用场景：
 * 1. 数据收集：收集所有数据后一次性处理
 * 2. 批量操作：对收集的数据进行批量处理
 * 3. 数据缓存：将数据缓存到数组中
 * 
 * 实现原理：
 * 1. 使用 aggregateWithStartFactory 创建初始数组
 * 2. 使用 reduce 将每个值添加到数组中
 * 3. 最终返回包含所有值的数组
 */
- (RACSignal *)collect {
	return [[self aggregateWithStartFactory:^{
		return [[NSMutableArray alloc] init];
	} reduce:^(NSMutableArray *collectedValues, id x) {
		[collectedValues addObject:(x ?: NSNull.null)];
		return collectedValues;
	}] setNameWithFormat:@"[%@] -collect", self.name];
}

/**
 * takeLast: 方法
 * 
 * 功能：获取信号的最后 N 个值
 * 
 * 参数说明：
 * @param count 要获取的值的数量
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 历史记录：获取最近的操作记录
 * 2. 状态回滚：获取最近的状态
 * 3. 数据缓存：获取最近的数据
 * 
 * 实现原理：
 * 1. 使用数组存储接收到的值
 * 2. 当数组长度超过指定数量时，移除最早的值
 * 3. 当信号完成时，发送所有存储的值
 * 4. 处理 RACTupleNil 的特殊情况
 */
- (RACSignal *)takeLast:(NSUInteger)count {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建数组存储最后的值
		NSMutableArray *valuesTaken = [NSMutableArray arrayWithCapacity:count];
		return [self subscribeNext:^(id x) {
			// 添加值到数组
			[valuesTaken addObject:x ? : RACTupleNil.tupleNil];

			// 保持数组长度不超过指定数量
			while (valuesTaken.count > count) {
				[valuesTaken removeObjectAtIndex:0];
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			// 完成时发送所有存储的值
			for (id value in valuesTaken) {
				[subscriber sendNext:value == RACTupleNil.tupleNil ? nil : value];
			}

			[subscriber sendCompleted];
		}];
	}] setNameWithFormat:@"[%@] -takeLast: %lu", self.name, (unsigned long)count];
}

/**
 * combineLatestWith 方法
 * 
 * 功能：将当前信号与另一个信号组合，每当任一信号发送新值时，发送两个信号的最新值的元组
 * 
 * 参数说明：
 * @param signal 要组合的另一个信号
 * 
 * 返回值：新的 RACSignal 对象，发送 RACTuple 类型的值
 * 
 * 使用场景：
 * 1. 表单验证：用户名和密码输入框的值组合
 * 2. 实时搜索：搜索关键词和筛选条件组合
 * 3. 多条件查询：多个查询条件的组合
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理两个信号的订阅
 * 2. 分别记录两个信号的最新值
 * 3. 每当任一信号发送新值时，检查是否两个信号都有值
 * 4. 如果都有值，则发送包含两个最新值的元组
 * 5. 只有当两个信号都完成时才发送完成事件
 * 6. 使用同步锁保证线程安全
 */
- (RACSignal *)combineLatestWith:(RACSignal *)signal {
	NSCParameterAssert(signal != nil);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理两个信号的订阅
		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

		// 记录当前信号的最新值和完成状态
		__block id lastSelfValue = nil;
		__block BOOL selfCompleted = NO;

		// 记录另一个信号的最新值和完成状态
		__block id lastOtherValue = nil;
		__block BOOL otherCompleted = NO;

		/**
		 * sendNext 块
		 * 
		 * 功能：发送组合后的值
		 * 
		 * 实现逻辑：
		 * 1. 检查两个信号是否都有值
		 * 2. 如果都有值，则发送包含两个最新值的元组
		 * 3. 使用同步锁保证线程安全
		 */
		void (^sendNext)(void) = ^{
			@synchronized (disposable) {
				// 只有当两个信号都有值时才发送
				if (lastSelfValue == nil || lastOtherValue == nil) return;
				[subscriber sendNext:RACTuplePack(lastSelfValue, lastOtherValue)];
			}
		};

		// 订阅当前信号
		RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
			@synchronized (disposable) {
				// 更新当前信号的最新值
				lastSelfValue = x ?: RACTupleNil.tupleNil;
				// 尝试发送组合值
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (disposable) {
				// 标记当前信号已完成
				selfCompleted = YES;
				// 如果另一个信号也已完成，则发送完成事件
				if (otherCompleted) [subscriber sendCompleted];
			}
		}];

		[disposable addDisposable:selfDisposable];

		// 订阅另一个信号
		RACDisposable *otherDisposable = [signal subscribeNext:^(id x) {
			@synchronized (disposable) {
				// 更新另一个信号的最新值
				lastOtherValue = x ?: RACTupleNil.tupleNil;
				// 尝试发送组合值
				sendNext();
			}
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (disposable) {
				// 标记另一个信号已完成
				otherCompleted = YES;
				// 如果当前信号也已完成，则发送完成事件
				if (selfCompleted) [subscriber sendCompleted];
			}
		}];

		[disposable addDisposable:otherDisposable];

		return disposable;
	}] setNameWithFormat:@"[%@] -combineLatestWith: %@", self.name, signal];
}

/**
 * combineLatest 类方法
 * 
 * 功能：将多个信号组合，每当任一信号发送新值时，发送所有信号的最新值的元组
 * 
 * 参数说明：
 * @param signals 要组合的信号集合
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 多条件表单：多个输入框的值组合
 * 2. 复杂查询：多个查询参数的组合
 * 3. 实时计算：多个数据源的组合
 * 
 * 实现原理：
 * 使用 join 方法递归组合多个信号
 */
+ (RACSignal *)combineLatest:(id<NSFastEnumeration>)signals {
	return [[self join:signals block:^(RACSignal *left, RACSignal *right) {
		return [left combineLatestWith:right];
	}] setNameWithFormat:@"+combineLatest: %@", signals];
}

/**
 * combineLatest:reduce: 类方法
 * 
 * 功能：将多个信号组合，并使用指定的块对组合后的值进行转换
 * 
 * 参数说明：
 * @param signals 要组合的信号集合
 * @param reduceBlock 用于转换组合值的块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 数据转换：将多个输入转换为特定格式
 * 2. 业务逻辑：根据多个条件计算业务结果
 * 3. 数据聚合：将多个数据源聚合为单一结果
 * 
 * 实现原理：
 * 1. 先调用 combineLatest 组合信号
 * 2. 然后使用 reduceEach 对结果进行转换
 */
+ (RACSignal *)combineLatest:(id<NSFastEnumeration>)signals reduce:(RACGenericReduceBlock)reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	RACSignal *result = [self combineLatest:signals];

	// 虽然我们在上面断言了这个条件，但旧版本的此方法支持此参数为 nil。
	// 避免在依赖于此的应用程序的 Release 版本中崩溃。
	if (reduceBlock != nil) result = [result reduceEach:reduceBlock];

	return [result setNameWithFormat:@"+combineLatest: %@ reduce:", signals];
}

/**
 * merge 实例方法
 * 
 * 功能：将当前信号与另一个信号合并，按时间顺序发送所有值
 * 
 * 参数说明：
 * @param signal 要合并的另一个信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 多数据源合并：从多个API获取数据
 * 2. 事件流合并：多个用户操作事件
 * 3. 状态更新：多个状态变化事件
 * 
 * 实现原理：
 * 调用类方法 merge，将当前信号和指定信号作为数组传入
 */
- (RACSignal *)merge:(RACSignal *)signal {
	return [[RACSignal
		merge:@[ self, signal ]]
		setNameWithFormat:@"[%@] -merge: %@", self.name, signal];
}

/**
 * merge 类方法
 * 
 * 功能：将多个信号合并，按时间顺序发送所有值
 * 
 * 参数说明：
 * @param signals 要合并的信号集合
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 多数据源合并：从多个API获取数据
 * 2. 事件流合并：多个用户操作事件
 * 3. 状态更新：多个状态变化事件
 * 
 * 实现原理：
 * 1. 复制所有信号到数组中
 * 2. 创建一个发送所有信号的信号
 * 3. 使用 flatten 将信号流扁平化
 * 4. 按时间顺序发送所有信号的值
 */
+ (RACSignal *)merge:(id<NSFastEnumeration>)signals {
	// 复制所有信号到数组中
	NSMutableArray *copiedSignals = [[NSMutableArray alloc] init];
	for (RACSignal *signal in signals) {
		[copiedSignals addObject:signal];
	}

	return [[[RACSignal
		createSignal:^ RACDisposable * (id<RACSubscriber> subscriber) {
			// 发送所有信号
			for (RACSignal *signal in copiedSignals) {
				[subscriber sendNext:signal];
			}

			[subscriber sendCompleted];
			return nil;
		}]
		flatten]
		setNameWithFormat:@"+merge: %@", copiedSignals];
}

/**
 * flatten 方法
 * 
 * 功能：将信号流扁平化，控制并发订阅的数量
 * 
 * 参数说明：
 * @param maxConcurrent 最大并发订阅数量，0表示无限制
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 控制网络请求并发数：避免同时发起过多请求
 * 2. 资源管理：限制同时打开的文件数量
 * 3. 性能优化：控制数据库连接的并发数
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理所有订阅
 * 2. 维护活跃订阅列表和等待队列
 * 3. 当活跃订阅数达到上限时，将新信号加入等待队列
 * 4. 当活跃订阅完成时，从等待队列中取出下一个信号
 * 5. 使用同步锁保证线程安全
 * 6. 通过弱引用避免循环引用
 */
- (RACSignal *)flatten:(NSUInteger)maxConcurrent {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理所有订阅
		RACCompoundDisposable *compoundDisposable = [[RACCompoundDisposable alloc] init];

		// 包含当前活跃订阅的可释放对象
		// 此数组只能在同步 subscriber 时使用
		NSMutableArray *activeDisposables = [[NSMutableArray alloc] initWithCapacity:maxConcurrent];

		// 信号流是否已完成
		// 此变量只能在同步 subscriber 时使用
		__block BOOL selfCompleted = NO;

		// 订阅给定信号的块
		__block void (^subscribeToSignal)(RACSignal *);

		// 上面的弱引用，避免泄漏
		__weak __block void (^recur)(RACSignal *);

		/**
		 * completeIfAllowed 块
		 * 
		 * 功能：如果所有信号都完成，则发送完成事件给订阅者
		 * 
		 * 实现逻辑：
		 * 1. 检查信号流是否已完成
		 * 2. 检查是否还有活跃订阅
		 * 3. 如果都满足条件，则发送完成事件
		 */
		void (^completeIfAllowed)(void) = ^{
			if (selfCompleted && activeDisposables.count == 0) {
				[subscriber sendCompleted];
			}
		};

		// 等待启动的信号
		// 此数组只能在同步 subscriber 时使用
		NSMutableArray *queuedSignals = [NSMutableArray array];

		/**
		 * subscribeToSignal 块
		 * 
		 * 功能：订阅指定的信号
		 * 
		 * 参数说明：
		 * @param signal 要订阅的信号
		 * 
		 * 实现逻辑：
		 * 1. 创建串行可释放对象管理当前订阅
		 * 2. 将订阅添加到复合可释放对象和活跃列表
		 * 3. 订阅信号并处理事件
		 * 4. 当信号完成时，从活跃列表中移除并处理下一个等待的信号
		 */
		recur = subscribeToSignal = ^(RACSignal *signal) {
			// 创建串行可释放对象来管理当前订阅
			RACSerialDisposable *serialDisposable = [[RACSerialDisposable alloc] init];

			@synchronized (subscriber) {
				// 将订阅添加到复合可释放对象
				[compoundDisposable addDisposable:serialDisposable];
				// 将订阅添加到活跃列表
				[activeDisposables addObject:serialDisposable];
			}

			// 订阅信号
			serialDisposable.disposable = [signal subscribeNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				// 使用强引用避免在异步环境中被释放
				__strong void (^subscribeToSignal)(RACSignal *) = recur;
				RACSignal *nextSignal;

				@synchronized (subscriber) {
					// 从复合可释放对象中移除当前订阅
					[compoundDisposable removeDisposable:serialDisposable];
					// 从活跃列表中移除当前订阅
					[activeDisposables removeObjectIdenticalTo:serialDisposable];

					// 如果没有等待的信号，检查是否可以完成
					if (queuedSignals.count == 0) {
						completeIfAllowed();
						return;
					}

					// 从等待队列中取出下一个信号
					nextSignal = queuedSignals[0];
					[queuedSignals removeObjectAtIndex:0];
				}

				// 订阅下一个信号
				subscribeToSignal(nextSignal);
			}];
		};

		// 订阅信号流
		[compoundDisposable addDisposable:[self subscribeNext:^(RACSignal *signal) {
			// 忽略空信号
			if (signal == nil) return;

			// 断言确保接收到的是 RACSignal 对象
			NSCAssert([signal isKindOfClass:RACSignal.class], @"Expected a RACSignal, got %@", signal);

			@synchronized (subscriber) {
				// 如果设置了最大并发数且当前活跃订阅数已达到上限
				if (maxConcurrent > 0 && activeDisposables.count >= maxConcurrent) {
					// 将信号添加到等待队列
					[queuedSignals addObject:signal];

					// 如果需要等待，跳过订阅此信号
					return;
				}
			}

			// 立即订阅信号
			subscribeToSignal(signal);
		} error:^(NSError *error) {
			[subscriber sendError:error];
		} completed:^{
			@synchronized (subscriber) {
				// 标记信号流已完成
				selfCompleted = YES;
				// 检查是否可以发送完成事件
				completeIfAllowed();
			}
		}]];

		// 添加清理块，防止 subscribeToSignal 过早释放
		[compoundDisposable addDisposable:[RACDisposable disposableWithBlock:^{
			// 保持对 subscribeToSignal 的强引用，直到我们完成，
			// 防止它过早释放。
			subscribeToSignal = nil;
		}]];

		return compoundDisposable;
	}] setNameWithFormat:@"[%@] -flatten: %lu", self.name, (unsigned long)maxConcurrent];
}

/**
 * then 方法
 * 
 * 功能：忽略当前信号的所有值，然后执行指定的块并返回新的信号
 * 
 * 参数说明：
 * @param block 要执行的块，返回新的信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 链式操作：先执行一个操作，然后执行另一个操作
 * 2. 条件分支：根据第一个操作的结果决定后续操作
 * 3. 流程控制：按顺序执行多个操作
 * 
 * 实现原理：
 * 1. 使用 ignoreValues 忽略当前信号的所有值
 * 2. 使用 concat 连接当前信号和延迟创建的新信号
 * 3. 新信号通过 defer 延迟创建，避免过早执行
 */
- (RACSignal *)then:(RACSignal * (^)(void))block {
	NSCParameterAssert(block != nil);

	return [[[self
		ignoreValues]
		concat:[RACSignal defer:block]]
		setNameWithFormat:@"[%@] -then:", self.name];
}

/**
 * concat 方法
 * 
 * 功能：将信号流按顺序连接，一次只处理一个信号
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 顺序操作：按顺序执行多个网络请求
 * 2. 数据流处理：按顺序处理多个数据源
 * 3. 任务队列：按顺序执行多个任务
 * 
 * 实现原理：
 * 调用 flatten 方法，设置最大并发数为1，确保信号按顺序处理
 */
- (RACSignal *)concat {
	return [[self flatten:1] setNameWithFormat:@"[%@] -concat", self.name];
}

/**
 * aggregateWithStartFactory:reduce: 方法
 * 
 * 功能：使用工厂函数创建初始值，然后对信号的值进行聚合操作
 * 
 * 参数说明：
 * @param startFactory 创建初始值的工厂函数
 * @param reduceBlock 聚合操作块，接收当前累积值和下一个值
 * 
 * 返回值：新的 RACSignal 对象，发送最终的聚合结果
 * 
 * 使用场景：
 * 1. 数据统计：计算总和、平均值等
 * 2. 状态累积：累积多个状态变化
 * 3. 数据转换：将多个值转换为单一结果
 * 
 * 实现原理：
 * 1. 使用 defer 延迟执行工厂函数
 * 2. 调用 aggregateWithStart:reduce: 方法进行聚合
 */
- (RACSignal *)aggregateWithStartFactory:(id (^)(void))startFactory reduce:(id (^)(id running, id next))reduceBlock {
	NSCParameterAssert(startFactory != NULL);
	NSCParameterAssert(reduceBlock != NULL);

	return [[RACSignal defer:^{
		return [self aggregateWithStart:startFactory() reduce:reduceBlock];
	}] setNameWithFormat:@"[%@] -aggregateWithStartFactory:reduce:", self.name];
}

/**
 * aggregateWithStart:reduce: 方法
 * 
 * 功能：使用指定的初始值对信号的值进行聚合操作
 * 
 * 参数说明：
 * @param start 初始值
 * @param reduceBlock 聚合操作块，接收当前累积值和下一个值
 * 
 * 返回值：新的 RACSignal 对象，发送最终的聚合结果
 * 
 * 使用场景：
 * 1. 数值计算：求和、求积等
 * 2. 字符串拼接：累积多个字符串
 * 3. 数组构建：累积多个元素到数组中
 * 
 * 实现原理：
 * 调用带索引的聚合方法，忽略索引参数
 */
- (RACSignal *)aggregateWithStart:(id)start reduce:(id (^)(id running, id next))reduceBlock {
	return [[self
		aggregateWithStart:start
		reduceWithIndex:^(id running, id next, NSUInteger index) {
			return reduceBlock(running, next);
		}]
		setNameWithFormat:@"[%@] -aggregateWithStart: %@ reduce:", self.name, RACDescription(start)];
}

/**
 * aggregateWithStart:reduceWithIndex: 方法
 * 
 * 功能：使用指定的初始值对信号的值进行聚合操作，聚合块可以访问索引
 * 
 * 参数说明：
 * @param start 初始值
 * @param reduceBlock 聚合操作块，接收当前累积值、下一个值和索引
 * 
 * 返回值：新的 RACSignal 对象，发送最终的聚合结果
 * 
 * 使用场景：
 * 1. 带索引的聚合：需要知道当前处理的是第几个值
 * 2. 条件聚合：根据索引决定不同的聚合策略
 * 3. 复杂计算：需要索引信息的复杂聚合操作
 * 
 * 实现原理：
 * 1. 使用 scanWithStart:reduceWithIndex: 进行扫描聚合
 * 2. 使用 startWith: 在开头添加初始值
 * 3. 使用 takeLast:1 只取最后一个值（最终结果）
 */
- (RACSignal *)aggregateWithStart:(id)start reduceWithIndex:(id (^)(id, id, NSUInteger))reduceBlock {
	return [[[[self
		scanWithStart:start reduceWithIndex:reduceBlock]
		startWith:start]
		takeLast:1]
		setNameWithFormat:@"[%@] -aggregateWithStart: %@ reduceWithIndex:", self.name, RACDescription(start)];
}

/**
 * setKeyPath:onObject: 方法
 * 
 * 功能：将信号的值绑定到对象的指定键路径
 * 
 * 参数说明：
 * @param keyPath 要绑定的键路径
 * @param object 要绑定的对象
 * 
 * 返回值：RACDisposable 对象，用于取消绑定
 * 
 * 使用场景：
 * 1. UI绑定：将数据信号绑定到UI控件的属性
 * 2. 模型绑定：将网络请求结果绑定到数据模型
 * 3. 状态管理：将状态信号绑定到业务对象
 * 
 * 实现原理：
 * 调用带 nilValue 参数的 setKeyPath 方法，使用 nil 作为默认值
 */
- (RACDisposable *)setKeyPath:(NSString *)keyPath onObject:(NSObject *)object {
	return [self setKeyPath:keyPath onObject:object nilValue:nil];
}

/**
 * setKeyPath:onObject:nilValue: 方法
 * 
 * 功能：将信号的值绑定到对象的指定键路径，可以指定 nil 时的替代值
 * 
 * 参数说明：
 * @param keyPath 要绑定的键路径
 * @param object 要绑定的对象
 * @param nilValue 当信号值为 nil 时使用的替代值
 * 
 * 返回值：RACDisposable 对象，用于取消绑定
 * 
 * 使用场景：
 * 1. 数据绑定：将网络数据绑定到模型对象
 * 2. UI更新：将数据变化绑定到界面更新
 * 3. 状态同步：将状态变化绑定到业务逻辑
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理绑定
 * 2. 使用弱引用避免循环引用
 * 3. 通过 KVC 设置对象属性
 * 4. 在调试模式下跟踪绑定关系
 * 5. 当对象销毁时自动清理绑定
 */
- (RACDisposable *)setKeyPath:(NSString *)keyPath onObject:(NSObject *)object nilValue:(id)nilValue {
	NSCParameterAssert(keyPath != nil);
	NSCParameterAssert(object != nil);

	// 复制键路径以避免外部修改
	keyPath = [keyPath copy];

	// 创建复合可释放对象来管理绑定
	RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

	// 故意不保留 'object'，因为我们希望在它正常销毁时拆除绑定
	__block void * volatile objectPtr = (__bridge void *)object;

	// 订阅信号并设置对象属性
	RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
		// 可能是规范问题，也可能是编译器bug，但这个 __bridge 转换不会
		// 在这里产生 retain，实际上是隐式的 __unsafe_unretained 限定符。
		// 使用 objc_precise_lifetime 给出所需的 __strong 引用。
		// 显式使用 __strong 是严格防御性的。
		__strong NSObject *object __attribute__((objc_precise_lifetime)) = (__bridge __strong id)objectPtr;
		// 使用 KVC 设置对象属性
		[object setValue:x ?: nilValue forKeyPath:keyPath];
	} error:^(NSError *error) {
		__strong NSObject *object __attribute__((objc_precise_lifetime)) = (__bridge __strong id)objectPtr;

		// 断言失败，因为绑定不应该收到错误
		NSCAssert(NO, @"Received error from %@ in binding for key path \"%@\" on %@: %@", self, keyPath, object, error);

		// 如果禁用了断言，则记录错误
		NSLog(@"Received error from %@ in binding for key path \"%@\" on %@: %@", self, keyPath, object, error);

		[disposable dispose];
	} completed:^{
		[disposable dispose];
	}];

	[disposable addDisposable:subscriptionDisposable];

	#if DEBUG
	// 调试模式下的绑定跟踪
	static void *bindingsKey = &bindingsKey;
	NSMutableDictionary *bindings;

	@synchronized (object) {
		// 获取对象的绑定字典
		bindings = objc_getAssociatedObject(object, bindingsKey);
		if (bindings == nil) {
			// 如果不存在，创建新的绑定字典
			bindings = [NSMutableDictionary dictionary];
			objc_setAssociatedObject(object, bindingsKey, bindings, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
		}
	}

	@synchronized (bindings) {
		// 断言确保没有重复绑定到同一个键路径
		NSCAssert(bindings[keyPath] == nil, @"Signal %@ is already bound to key path \"%@\" on object %@, adding signal %@ is undefined behavior", [bindings[keyPath] nonretainedObjectValue], keyPath, object, self);

		// 记录绑定关系
		bindings[keyPath] = [NSValue valueWithNonretainedObject:self];
	}
	#endif

	/**
	 * clearPointerDisposable 清理块
	 * 
	 * 功能：清理绑定时的清理操作
	 * 
	 * 实现逻辑：
	 * 1. 在调试模式下移除绑定记录
	 * 2. 使用原子操作清空对象指针
	 */
	RACDisposable *clearPointerDisposable = [RACDisposable disposableWithBlock:^{
		#if DEBUG
		@synchronized (bindings) {
			// 移除绑定记录
			[bindings removeObjectForKey:keyPath];
		}
		#endif

		// 使用原子操作清空对象指针
		while (YES) {
			void *ptr = objectPtr;
			if (OSAtomicCompareAndSwapPtrBarrier(ptr, NULL, &objectPtr)) {
				break;
			}
		}
	}];

	[disposable addDisposable:clearPointerDisposable];

	// 将绑定添加到对象的销毁可释放对象中，确保对象销毁时自动清理
	[object.rac_deallocDisposable addDisposable:disposable];

	// 返回可释放对象，用于手动取消绑定
	RACCompoundDisposable *objectDisposable = object.rac_deallocDisposable;
	return [RACDisposable disposableWithBlock:^{
		[objectDisposable removeDisposable:disposable];
		[disposable dispose];
	}];
}

/**
 * interval:onScheduler: 类方法
 * 
 * 功能：创建一个定时发送当前时间的信号
 * 
 * 参数说明：
 * @param interval 发送间隔（秒）
 * @param scheduler 调度器
 * 
 * 返回值：新的 RACSignal 对象，发送 NSDate 类型的值
 * 
 * 使用场景：
 * 1. 定时器：创建定时任务
 * 2. 轮询：定期检查服务器状态
 * 3. 动画：定时更新动画状态
 * 
 * 实现原理：
 * 调用带容差参数的 interval 方法，使用 0.0 作为容差
 */
+ (RACSignal *)interval:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler {
	return [[RACSignal interval:interval onScheduler:scheduler withLeeway:0.0] setNameWithFormat:@"+interval: %f onScheduler: %@", (double)interval, scheduler];
}

/**
 * interval:onScheduler:withLeeway: 类方法
 * 
 * 功能：创建一个定时发送当前时间的信号，可以指定时间容差
 * 
 * 参数说明：
 * @param interval 发送间隔（秒）
 * @param scheduler 调度器
 * @param leeway 时间容差（秒），允许调度器在指定时间范围内灵活安排
 * 
 * 返回值：新的 RACSignal 对象，发送 NSDate 类型的值
 * 
 * 使用场景：
 * 1. 精确定时：需要精确时间控制的场景
 * 2. 性能优化：允许调度器优化执行时间
 * 3. 电池优化：在移动设备上减少电池消耗
 * 
 * 实现原理：
 * 1. 使用调度器的 after:repeatingEvery:withLeeway:schedule: 方法
 * 2. 从当前时间开始，每隔指定间隔发送当前时间
 * 3. 使用容差参数允许调度器优化执行时间
 */
+ (RACSignal *)interval:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler withLeeway:(NSTimeInterval)leeway {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(scheduler != RACScheduler.immediateScheduler);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [scheduler after:[NSDate dateWithTimeIntervalSinceNow:interval] repeatingEvery:interval withLeeway:leeway schedule:^{
			[subscriber sendNext:[NSDate date]];
		}];
	}] setNameWithFormat:@"+interval: %f onScheduler: %@ withLeeway: %f", (double)interval, scheduler, (double)leeway];
}

/**
 * takeUntil 方法
 * 
 * 功能：当指定的触发信号发送任何值时，停止当前信号并发送完成事件
 * 
 * 参数说明：
 * @param signalTrigger 触发停止的信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 条件停止：根据某个条件停止信号
 * 2. 超时控制：设置超时时间停止操作
 * 3. 用户取消：用户点击取消按钮时停止操作
 * 
 * 实现原理：
 * 1. 创建复合可释放对象管理所有订阅
 * 2. 订阅触发信号，当它发送任何值时停止当前信号
 * 3. 订阅当前信号，正常传递值
 * 4. 当触发信号发送值或完成时，停止所有订阅并发送完成事件
 */
- (RACSignal *)takeUntil:(RACSignal *)signalTrigger {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理所有订阅
		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];
		
		/**
		 * triggerCompletion 块
		 * 
		 * 功能：触发完成事件
		 * 
		 * 实现逻辑：
		 * 1. 释放所有订阅
		 * 2. 发送完成事件给订阅者
		 */
		void (^triggerCompletion)(void) = ^{
			[disposable dispose];
			[subscriber sendCompleted];
		};

		// 订阅触发信号
		RACDisposable *triggerDisposable = [signalTrigger subscribeNext:^(id _) {
			// 当触发信号发送任何值时，停止当前信号
			triggerCompletion();
		} completed:^{
			// 当触发信号完成时，也停止当前信号
			triggerCompletion();
		}];

		[disposable addDisposable:triggerDisposable];

		// 如果复合可释放对象未被释放，则订阅当前信号
		if (!disposable.disposed) {
			RACDisposable *selfDisposable = [self subscribeNext:^(id x) {
				[subscriber sendNext:x];
			} error:^(NSError *error) {
				[subscriber sendError:error];
			} completed:^{
				[disposable dispose];
				[subscriber sendCompleted];
			}];

			[disposable addDisposable:selfDisposable];
		}

		return disposable;
	}] setNameWithFormat:@"[%@] -takeUntil: %@", self.name, signalTrigger];
}

/**
 * takeUntilReplacement 方法
 * 
 * 功能：当指定的替换信号发送任何值时，停止当前信号并切换到替换信号
 * 
 * 参数说明：
 * @param replacement 替换信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 信号切换：根据条件切换到不同的信号
 * 2. 降级处理：主信号失败时切换到备用信号
 * 3. 动态路由：根据用户选择切换到不同的数据源
 * 
 * 实现原理：
 * 1. 使用串行可释放对象管理当前信号的订阅
 * 2. 订阅替换信号，当它发送任何值时停止当前信号并传递值
 * 3. 订阅当前信号，正常传递值
 * 4. 当替换信号发送值时，停止当前信号并切换到替换信号
 */
- (RACSignal *)takeUntilReplacement:(RACSignal *)replacement {
	return [RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建串行可释放对象来管理当前信号的订阅
		RACSerialDisposable *selfDisposable = [[RACSerialDisposable alloc] init];

		// 订阅替换信号
		RACDisposable *replacementDisposable = [replacement subscribeNext:^(id x) {
			// 当替换信号发送值时，停止当前信号并传递值
			[selfDisposable dispose];
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			// 当替换信号出错时，停止当前信号并传递错误
			[selfDisposable dispose];
			[subscriber sendError:error];
		} completed:^{
			// 当替换信号完成时，停止当前信号并发送完成事件
			[selfDisposable dispose];
			[subscriber sendCompleted];
		}];

		if (!selfDisposable.disposed) {
			selfDisposable.disposable = [[self
				concat:[RACSignal never]]
				subscribe:subscriber];
		}

		return [RACDisposable disposableWithBlock:^{
			[selfDisposable dispose];
			[replacementDisposable dispose];
		}];
	}];
}

/**
 * switchToLatest 方法
 * 
 * 功能：将信号流转换为信号，每当源信号发送新信号时，取消之前的订阅并订阅新信号
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 搜索功能：用户输入时取消之前的搜索请求
 * 2. 页面切换：切换到新页面时取消之前的网络请求
 * 3. 实时更新：只处理最新的数据请求
 * 
 * 实现原理：
 * 1. 使用 publish 创建多播连接，避免多次订阅源信号
 * 2. 使用 flattenMap 将每个信号转换为新的信号
 * 3. 使用 takeUntil 确保当源信号发送新信号时，取消之前的订阅
 * 4. 使用 concat:[RACSignal never] 防止接收者的完成事件过早终止内部信号
 * 5. 通过多播连接确保所有订阅者都能收到最新的信号
 */
- (RACSignal *)switchToLatest {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建多播连接，避免多次订阅源信号
		RACMulticastConnection *connection = [self publish];

		// 订阅多播信号
		RACDisposable *subscriptionDisposable = [[connection.signal
			flattenMap:^(RACSignal *x) {
				// 断言确保接收到的是 RACSignal 对象
				NSCAssert(x == nil || [x isKindOfClass:RACSignal.class], @"-switchToLatest requires that the source signal (%@) send signals. Instead we got: %@", self, x);

				// -concat:[RACSignal never] 防止接收者的完成事件过早终止内部信号
				return [x takeUntil:[connection.signal concat:[RACSignal never]]];
			}]
			subscribe:subscriber];

		// 连接多播
		RACDisposable *connectionDisposable = [connection connect];
		
		// 返回可释放对象，确保所有订阅都能正确释放
		return [RACDisposable disposableWithBlock:^{
			[subscriptionDisposable dispose];
			[connectionDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -switchToLatest", self.name];
}

/**
 * switch:cases:default: 类方法
 * 
 * 功能：根据信号的值选择对应的信号，类似于 switch-case 语句
 * 
 * 参数说明：
 * @param signal 提供选择键的信号
 * @param cases 键值对字典，键是选择值，值是对应的信号
 * @param defaultSignal 默认信号，当没有匹配的键时使用
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 路由选择：根据用户选择切换到不同的数据源
 * 2. 状态机：根据当前状态切换到不同的处理逻辑
 * 3. 条件分支：根据条件选择不同的业务逻辑
 * 
 * 实现原理：
 * 1. 验证所有 case 值都是 RACSignal 对象
 * 2. 复制 cases 字典避免外部修改
 * 3. 使用 map 将信号值转换为对应的信号
 * 4. 使用 switchToLatest 切换到最新的信号
 * 5. 当没有匹配的键时，返回错误信号
 */
+ (RACSignal *)switch:(RACSignal *)signal cases:(NSDictionary *)cases default:(RACSignal *)defaultSignal {
	NSCParameterAssert(signal != nil);
	NSCParameterAssert(cases != nil);

	// 验证所有 case 值都是 RACSignal 对象
	for (id key in cases) {
		id value __attribute__((unused)) = cases[key];
		NSCAssert([value isKindOfClass:RACSignal.class], @"Expected all cases to be RACSignals, %@ isn't", value);
	}

	// 复制 cases 字典避免外部修改
	NSDictionary *copy = [cases copy];

	return [[[signal
		map:^(id key) {
			// 处理 nil 键，使用 RACTupleNil 作为键
			if (key == nil) key = RACTupleNil.tupleNil;

			// 查找对应的信号，如果没有找到则使用默认信号
			RACSignal *signal = copy[key] ?: defaultSignal;
			if (signal == nil) {
				// 如果没有匹配的信号且没有默认信号，返回错误
				NSString *description = [NSString stringWithFormat:NSLocalizedString(@"No matching signal found for value %@", @""), key];
				return [RACSignal error:[NSError errorWithDomain:RACSignalErrorDomain code:RACSignalErrorNoMatchingCase userInfo:@{ NSLocalizedDescriptionKey: description }]];
			}

			return signal;
		}]
		switchToLatest]
		setNameWithFormat:@"+switch: %@ cases: %@ default: %@", signal, cases, defaultSignal];
}

/**
 * if:then:else: 类方法
 * 
 * 功能：根据布尔信号的值选择 true 信号或 false 信号
 * 
 * 参数说明：
 * @param boolSignal 提供布尔值的信号
 * @param trueSignal 当布尔值为 true 时使用的信号
 * @param falseSignal 当布尔值为 false 时使用的信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 条件分支：根据条件选择不同的处理逻辑
 * 2. 功能开关：根据开关状态选择不同的功能
 * 3. 用户偏好：根据用户设置选择不同的行为
 * 
 * 实现原理：
 * 1. 使用 map 将布尔值转换为对应的信号
 * 2. 使用 switchToLatest 切换到选中的信号
 * 3. 断言确保布尔信号发送的是 NSNumber 类型的值
 */
+ (RACSignal *)if:(RACSignal *)boolSignal then:(RACSignal *)trueSignal else:(RACSignal *)falseSignal {
	NSCParameterAssert(boolSignal != nil);
	NSCParameterAssert(trueSignal != nil);
	NSCParameterAssert(falseSignal != nil);

	return [[[boolSignal
		map:^(NSNumber *value) {
			// 断言确保接收到的是 NSNumber 类型的布尔值
			NSCAssert([value isKindOfClass:NSNumber.class], @"Expected %@ to send BOOLs, not %@", boolSignal, value);

			// 根据布尔值选择对应的信号
			return (value.boolValue ? trueSignal : falseSignal);
		}]
		switchToLatest]
		setNameWithFormat:@"+if: %@ then: %@ else: %@", boolSignal, trueSignal, falseSignal];
}

/**
 * first 方法
 * 
 * 功能：获取信号的第一个值，如果信号为空则返回 nil
 * 
 * 参数说明：无
 * 
 * 返回值：信号的第一个值或 nil
 * 
 * 使用场景：
 * 1. 获取默认值：获取配置的默认值
 * 2. 单次操作：只需要第一个结果的场景
 * 3. 初始化：获取初始状态值
 * 
 * 实现原理：
 * 调用 firstOrDefault 方法，使用 nil 作为默认值
 */
- (id)first {
	return [self firstOrDefault:nil];
}

/**
 * firstOrDefault: 方法
 * 
 * 功能：获取信号的第一个值，如果信号为空则返回指定的默认值
 * 
 * 参数说明：
 * @param defaultValue 当信号为空时返回的默认值
 * 
 * 返回值：信号的第一个值或默认值
 * 
 * 使用场景：
 * 1. 安全获取：避免空值导致的崩溃
 * 2. 默认配置：提供合理的默认值
 * 3. 降级处理：当无法获取值时使用备用值
 * 
 * 实现原理：
 * 调用带成功和错误参数的 firstOrDefault 方法，忽略成功和错误状态
 */
- (id)firstOrDefault:(id)defaultValue {
	return [self firstOrDefault:defaultValue success:NULL error:NULL];
}

/**
 * firstOrDefault:success:error: 方法
 * 
 * 功能：获取信号的第一个值，并提供成功和错误状态信息
 * 
 * 参数说明：
 * @param defaultValue 当信号为空时返回的默认值
 * @param success 成功状态指针，用于返回是否成功获取值
 * @param error 错误指针，用于返回错误信息
 * 
 * 返回值：信号的第一个值或默认值
 * 
 * 使用场景：
 * 1. 错误处理：需要知道获取值是否成功
 * 2. 调试信息：需要详细的错误信息
 * 3. 状态检查：需要检查操作的成功状态
 * 
 * 实现原理：
 * 1. 使用条件锁同步访问
 * 2. 订阅信号并等待第一个值
 * 3. 使用 take:1 只获取第一个值
 * 4. 通过条件锁确保线程安全
 * 5. 返回获取的值和状态信息
 */
- (id)firstOrDefault:(id)defaultValue success:(BOOL *)success error:(NSError **)error {
	// 创建条件锁用于同步
	NSCondition *condition = [[NSCondition alloc] init];
	condition.name = [NSString stringWithFormat:@"[%@] -firstOrDefault: %@ success:error:", self.name, defaultValue];

	// 存储结果值
	__block id value = defaultValue;
	__block BOOL done = NO;

	// 确保我们不会通过引用跨线程边界传递值
	__block NSError *localError;
	__block BOOL localSuccess;

	// 订阅信号并只获取第一个值
	[[self take:1] subscribeNext:^(id x) {
		[condition lock];

		// 设置获取到的值
		value = x;
		localSuccess = YES;

		// 标记操作完成并通知等待的线程
		done = YES;
		[condition broadcast];
		[condition unlock];
	} error:^(NSError *e) {
		[condition lock];

		// 只有在未完成时才处理错误
		if (!done) {
			localSuccess = NO;
			localError = e;

			// 标记操作完成并通知等待的线程
			done = YES;
			[condition broadcast];
		}

		[condition unlock];
	} completed:^{
		[condition lock];

		// 信号完成时标记为成功
		localSuccess = YES;

		// 标记操作完成并通知等待的线程
		done = YES;
		[condition broadcast];
		[condition unlock];
	}];

	// 等待操作完成
	[condition lock];
	while (!done) {
		[condition wait];
	}

	// 设置返回的成功和错误状态
	if (success != NULL) *success = localSuccess;
	if (error != NULL) *error = localError;

	[condition unlock];
	return value;
}

/**
 * waitUntilCompleted: 方法
 * 
 * 功能：等待信号完成，返回是否成功完成
 * 
 * 参数说明：
 * @param error 错误指针，用于返回错误信息
 * 
 * 返回值：BOOL 值，表示是否成功完成
 * 
 * 使用场景：
 * 1. 同步等待：需要等待异步操作完成
 * 2. 错误检查：需要检查操作是否成功
 * 3. 测试验证：在测试中验证信号行为
 * 
 * 实现原理：
 * 1. 使用 ignoreValues 忽略信号的所有值
 * 2. 使用 firstOrDefault 等待信号完成
 * 3. 返回成功状态
 */
- (BOOL)waitUntilCompleted:(NSError **)error {
	BOOL success = NO;

	[[[self
		ignoreValues]
		setNameWithFormat:@"[%@] -waitUntilCompleted:", self.name]
		firstOrDefault:nil success:&success error:error];

	return success;
}

/**
 * defer 类方法
 * 
 * 功能：延迟创建信号，直到有订阅者时才执行创建块
 * 
 * 参数说明：
 * @param block 创建信号的块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 延迟初始化：避免过早创建昂贵的资源
 * 2. 条件创建：根据运行时条件创建不同的信号
 * 3. 依赖注入：在订阅时注入依赖
 * 
 * 实现原理：
 * 1. 创建新的信号
 * 2. 当有订阅者时，执行创建块
 * 3. 订阅创建块返回的信号
 */
+ (RACSignal *)defer:(RACSignal<id> * (^)(void))block {
	NSCParameterAssert(block != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [block() subscribe:subscriber];
	}] setNameWithFormat:@"+defer:"];
}

/**
 * toArray 方法
 * 
 * 功能：将信号的所有值收集到数组中
 * 
 * 参数说明：无
 * 
 * 返回值：包含所有值的 NSArray 对象
 * 
 * 使用场景：
 * 1. 数据收集：收集所有数据后一次性处理
 * 2. 批量操作：对收集的数据进行批量处理
 * 3. 缓存数据：将数据缓存到数组中
 * 
 * 实现原理：
 * 1. 使用 collect 收集所有值
 * 2. 使用 first 获取第一个（也是唯一一个）值
 * 3. 返回数组的副本
 */
- (NSArray *)toArray {
	return [[[self collect] first] copy];
}

/**
 * sequence 方法
 * 
 * 功能：将信号转换为序列
 * 
 * 参数说明：无
 * 
 * 返回值：RACSequence 对象
 * 
 * 使用场景：
 * 1. 序列操作：使用序列的丰富操作方法
 * 2. 数据转换：将信号数据转换为序列格式
 * 3. 链式操作：利用序列的链式操作特性
 * 
 * 实现原理：
 * 使用 RACSignalSequence 将信号包装为序列
 */
- (RACSequence *)sequence {
	return [[RACSignalSequence sequenceWithSignal:self] setNameWithFormat:@"[%@] -sequence", self.name];
}

/**
 * publish 方法
 * 
 * 功能：创建多播连接，允许多个订阅者共享同一个信号
 * 
 * 参数说明：无
 * 
 * 返回值：RACMulticastConnection 对象
 * 
 * 使用场景：
 * 1. 资源共享：多个订阅者共享同一个信号
 * 2. 性能优化：避免重复执行昂贵的操作
 * 3. 状态同步：确保多个订阅者看到相同的状态
 * 
 * 实现原理：
 * 1. 创建 RACSubject 作为多播主题
 * 2. 使用 multicast 创建多播连接
 * 3. 返回多播连接对象
 */
- (RACMulticastConnection *)publish {
	RACSubject *subject = [[RACSubject subject] setNameWithFormat:@"[%@] -publish", self.name];
	RACMulticastConnection *connection = [self multicast:subject];
	return connection;
}

/**
 * multicast: 方法
 * 
 * 功能：使用指定的主题创建多播连接
 * 
 * 参数说明：
 * @param subject 用于多播的主题
 * 
 * 返回值：RACMulticastConnection 对象
 * 
 * 使用场景：
 * 1. 自定义多播：使用特定的主题进行多播
 * 2. 状态管理：使用特定的主题管理状态
 * 3. 事件分发：使用主题分发事件
 * 
 * 实现原理：
 * 1. 设置主题的名称
 * 2. 创建多播连接
 * 3. 返回连接对象
 */
- (RACMulticastConnection *)multicast:(RACSubject *)subject {
	[subject setNameWithFormat:@"[%@] -multicast: %@", self.name, subject.name];
	RACMulticastConnection *connection = [[RACMulticastConnection alloc] initWithSourceSignal:self subject:subject];
	return connection;
}

/**
 * replay 方法
 * 
 * 功能：创建重放信号，新订阅者会收到之前发送的所有值
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 缓存数据：新订阅者可以获取历史数据
 * 2. 状态恢复：新订阅者可以获取当前状态
 * 3. 数据同步：确保所有订阅者看到相同的数据
 * 
 * 实现原理：
 * 1. 创建 RACReplaySubject 作为重放主题
 * 2. 使用 multicast 创建多播连接
 * 3. 连接多播并返回信号
 */
- (RACSignal *)replay {
	RACReplaySubject *subject = [[RACReplaySubject subject] setNameWithFormat:@"[%@] -replay", self.name];

	RACMulticastConnection *connection = [self multicast:subject];
	[connection connect];

	return connection.signal;
}

/**
 * replayLast 方法
 * 
 * 功能：创建重放信号，新订阅者只会收到最后一个发送的值
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 状态缓存：新订阅者获取最新状态
 * 2. 配置管理：新订阅者获取最新配置
 * 3. 数据同步：确保新订阅者看到最新数据
 * 
 * 实现原理：
 * 1. 创建容量为1的 RACReplaySubject
 * 2. 使用 multicast 创建多播连接
 * 3. 连接多播并返回信号
 */
- (RACSignal *)replayLast {
	RACReplaySubject *subject = [[RACReplaySubject replaySubjectWithCapacity:1] setNameWithFormat:@"[%@] -replayLast", self.name];

	RACMulticastConnection *connection = [self multicast:subject];
	[connection connect];

	return connection.signal;
}

/**
 * replayLazily 方法
 * 
 * 功能：创建延迟重放信号，只有在有订阅者时才连接多播
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 延迟初始化：避免过早创建昂贵的资源
 * 2. 条件重放：只在需要时才重放信号
 * 3. 性能优化：减少不必要的资源消耗
 * 
 * 实现原理：
 * 1. 创建多播连接但不立即连接
 * 2. 使用 defer 延迟连接多播
 * 3. 只有在有订阅者时才连接并返回信号
 */
- (RACSignal *)replayLazily {
	RACMulticastConnection *connection = [self multicast:[RACReplaySubject subject]];
	return [[RACSignal
		defer:^{
			[connection connect];
			return connection.signal;
		}]
		setNameWithFormat:@"[%@] -replayLazily", self.name];
}

/**
 * timeout:onScheduler: 方法
 * 
 * 功能：为信号设置超时时间，超时后发送错误
 * 
 * 参数说明：
 * @param interval 超时时间间隔（秒）
 * @param scheduler 调度器
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 网络请求：设置请求超时时间
 * 2. 用户操作：设置用户操作超时
 * 3. 资源管理：避免长时间占用资源
 * 
 * 实现原理：
 * 1. 使用复合可释放对象管理所有订阅
 * 2. 使用调度器设置延迟超时操作
 * 3. 订阅原信号并正常传递事件
 * 4. 超时后释放所有订阅并发送错误
 */
- (RACSignal *)timeout:(NSTimeInterval)interval onScheduler:(RACScheduler *)scheduler {
	NSCParameterAssert(scheduler != nil);
	NSCParameterAssert(scheduler != RACScheduler.immediateScheduler);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理所有订阅
		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

		// 设置超时操作
		RACDisposable *timeoutDisposable = [scheduler afterDelay:interval schedule:^{
			[disposable dispose];
			[subscriber sendError:[NSError errorWithDomain:RACSignalErrorDomain code:RACSignalErrorTimedOut userInfo:nil]];
		}];

		[disposable addDisposable:timeoutDisposable];

		// 订阅原信号
		RACDisposable *subscriptionDisposable = [self subscribeNext:^(id x) {
			[subscriber sendNext:x];
		} error:^(NSError *error) {
			[disposable dispose];
			[subscriber sendError:error];
		} completed:^{
			[disposable dispose];
			[subscriber sendCompleted];
		}];

		[disposable addDisposable:subscriptionDisposable];
		return disposable;
	}] setNameWithFormat:@"[%@] -timeout: %f onScheduler: %@", self.name, (double)interval, scheduler];
}

/**
 * deliverOn: 方法
 * 
 * 功能：在指定的调度器上传递信号的所有事件
 * 
 * 参数说明：
 * @param scheduler 调度器
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 线程切换：将事件传递到指定线程
 * 2. UI更新：确保UI更新在主线程执行
 * 3. 后台处理：将事件传递到后台线程处理
 * 
 * 实现原理：
 * 1. 创建新的信号
 * 2. 订阅原信号
 * 3. 使用调度器延迟执行所有事件
 * 4. 确保所有事件都在指定调度器上执行
 */
- (RACSignal *)deliverOn:(RACScheduler *)scheduler {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[scheduler schedule:^{
				[subscriber sendNext:x];
			}];
		} error:^(NSError *error) {
			[scheduler schedule:^{
				[subscriber sendError:error];
			}];
		} completed:^{
			[scheduler schedule:^{
				[subscriber sendCompleted];
			}];
		}];
	}] setNameWithFormat:@"[%@] -deliverOn: %@", self.name, scheduler];
}

/**
 * subscribeOn: 方法
 * 
 * 功能：在指定的调度器上订阅信号
 * 
 * 参数说明：
 * @param scheduler 调度器
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 订阅线程控制：控制信号订阅的线程
 * 2. 性能优化：在合适的线程上执行订阅操作
 * 3. 线程隔离：将订阅操作隔离到特定线程
 * 
 * 实现原理：
 * 1. 创建复合可释放对象管理订阅
 * 2. 使用调度器延迟执行订阅操作
 * 3. 在指定调度器上订阅原信号
 * 4. 确保订阅操作在指定调度器上执行
 */
- (RACSignal *)subscribeOn:(RACScheduler *)scheduler {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 创建复合可释放对象来管理订阅
		RACCompoundDisposable *disposable = [RACCompoundDisposable compoundDisposable];

		// 使用调度器延迟执行订阅操作
		RACDisposable *schedulingDisposable = [scheduler schedule:^{
			RACDisposable *subscriptionDisposable = [self subscribe:subscriber];

			[disposable addDisposable:subscriptionDisposable];
		}];

		[disposable addDisposable:schedulingDisposable];
		return disposable;
	}] setNameWithFormat:@"[%@] -subscribeOn: %@", self.name, scheduler];
}

/**
 * deliverOnMainThread 方法
 * 
 * 功能：在主线程上传递信号的所有事件
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. UI更新：确保所有UI更新在主线程执行
 * 2. 线程安全：避免跨线程访问UI组件
 * 3. 性能优化：减少线程切换开销
 * 
 * 实现原理：
 * 1. 使用原子操作管理队列长度
 * 2. 如果当前在主线程且队列为空，直接执行
 * 3. 否则异步派发到主队列执行
 * 4. 确保所有事件都在主线程上执行
 */
- (RACSignal *)deliverOnMainThread {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 使用原子操作管理队列长度
		__block volatile int32_t queueLength = 0;
		
		/**
		 * performOnMainThread 块
		 * 
		 * 功能：在主线程上执行指定的块
		 * 
		 * 参数说明：
		 * @param block 要执行的块
		 * 
		 * 实现逻辑：
		 * 1. 原子递增队列长度
		 * 2. 如果当前在主线程且队列长度为1，直接执行
		 * 3. 否则异步派发到主队列执行
		 * 4. 执行完成后原子递减队列长度
		 */
		void (^performOnMainThread)(dispatch_block_t) = ^(dispatch_block_t block) {
			int32_t queued = OSAtomicIncrement32(&queueLength);
			if (NSThread.isMainThread && queued == 1) {
				block();
				OSAtomicDecrement32(&queueLength);
			} else {
				dispatch_async(dispatch_get_main_queue(), ^{
					block();
					OSAtomicDecrement32(&queueLength);
				});
			}
		};

		return [self subscribeNext:^(id x) {
			performOnMainThread(^{
				[subscriber sendNext:x];
			});
		} error:^(NSError *error) {
			performOnMainThread(^{
				[subscriber sendError:error];
			});
		} completed:^{
			performOnMainThread(^{
				[subscriber sendCompleted];
			});
		}];
	}] setNameWithFormat:@"[%@] -deliverOnMainThread", self.name];
}

/**
 * groupBy:transform: 方法
 * 
 * 功能：根据键块对信号的值进行分组，并可选地对值进行转换
 * 
 * 参数说明：
 * @param keyBlock 用于生成分组键的块
 * @param transformBlock 用于转换值的块，可以为 nil
 * 
 * 返回值：新的 RACSignal 对象，发送 RACGroupedSignal 类型的值
 * 
 * 使用场景：
 * 1. 数据分组：将数据按类别分组
 * 2. 事件分类：将事件按类型分类
 * 3. 状态管理：将状态按类型分组管理
 * 
 * 实现原理：
 * 1. 使用字典存储分组信号
 * 2. 使用数组保持分组顺序
 * 3. 根据键块生成分组键
 * 4. 为每个新键创建分组信号
 * 5. 将值发送到对应的分组信号
 */
- (RACSignal *)groupBy:(id<NSCopying> (^)(id object))keyBlock transform:(id (^)(id object))transformBlock {
	NSCParameterAssert(keyBlock != NULL);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 存储分组信号的字典
		NSMutableDictionary *groups = [NSMutableDictionary dictionary];
		// 保持分组顺序的数组
		NSMutableArray *orderedGroups = [NSMutableArray array];

		return [self subscribeNext:^(id x) {
			// 生成分组键
			id<NSCopying> key = keyBlock(x);
			RACGroupedSignal *groupSubject = nil;
			@synchronized(groups) {
				// 获取或创建分组信号
				groupSubject = groups[key];
				if (groupSubject == nil) {
					groupSubject = [RACGroupedSignal signalWithKey:key];
					groups[key] = groupSubject;
					[orderedGroups addObject:groupSubject];
					[subscriber sendNext:groupSubject];
				}
			}

			// 发送转换后的值到分组信号
			[groupSubject sendNext:transformBlock != NULL ? transformBlock(x) : x];
		} error:^(NSError *error) {
			[subscriber sendError:error];

			// 向所有分组信号发送错误
			[orderedGroups makeObjectsPerformSelector:@selector(sendError:) withObject:error];
		} completed:^{
			[subscriber sendCompleted];

			// 向所有分组信号发送完成事件
			[orderedGroups makeObjectsPerformSelector:@selector(sendCompleted)];
		}];
	}] setNameWithFormat:@"[%@] -groupBy:transform:", self.name];
}

/**
 * groupBy: 方法
 * 
 * 功能：根据键块对信号的值进行分组，不进行值转换
 * 
 * 参数说明：
 * @param keyBlock 用于生成分组键的块
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 简单分组：只需要按键分组，不需要转换值
 * 2. 数据分类：将数据按类别分组
 * 3. 事件分类：将事件按类型分类
 * 
 * 实现原理：
 * 调用带转换块的 groupBy 方法，传递 nil 作为转换块
 */
- (RACSignal *)groupBy:(id<NSCopying> (^)(id object))keyBlock {
	return [[self groupBy:keyBlock transform:nil] setNameWithFormat:@"[%@] -groupBy:", self.name];
}

/**
 * any 方法
 * 
 * 功能：检查信号是否包含任何值
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 存在性检查：检查是否有数据存在
 * 2. 条件判断：检查是否满足某个条件
 * 3. 状态检查：检查是否有状态变化
 * 
 * 实现原理：
 * 调用带谓词的 any 方法，对所有值都返回 YES
 */
- (RACSignal *)any {
	return [[self any:^(id x) {
		return YES;
	}] setNameWithFormat:@"[%@] -any", self.name];
}

/**
 * any: 方法
 * 
 * 功能：检查信号是否包含满足谓词条件的值
 * 
 * 参数说明：
 * @param predicateBlock 谓词块，用于判断值是否满足条件
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 条件检查：检查是否有满足条件的值
 * 2. 数据验证：检查是否有有效数据
 * 3. 状态验证：检查是否有特定状态
 * 
 * 实现原理：
 * 1. 使用 materialize 将信号事件化
 * 2. 使用 bind 处理每个事件
 * 3. 当找到满足条件的值时立即返回 YES
 * 4. 当信号完成时返回 NO
 */
- (RACSignal *)any:(BOOL (^)(id object))predicateBlock {
	NSCParameterAssert(predicateBlock != NULL);

	return [[[self materialize] bind:^{
		return ^(RACEvent *event, BOOL *stop) {
			if (event.finished) {
				*stop = YES;
				return [RACSignal return:@NO];
			}

			if (predicateBlock(event.value)) {
				*stop = YES;
				return [RACSignal return:@YES];
			}

			return [RACSignal empty];
		};
	}] setNameWithFormat:@"[%@] -any:", self.name];
}

/**
 * all: 方法
 * 
 * 功能：检查信号的所有值是否都满足谓词条件
 * 
 * 参数说明：
 * @param predicateBlock 谓词块，用于判断值是否满足条件
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 数据验证：检查所有数据是否有效
 * 2. 条件检查：检查所有值是否满足条件
 * 3. 状态验证：检查所有状态是否正确
 * 
 * 实现原理：
 * 1. 使用 materialize 将信号事件化
 * 2. 使用 bind 处理每个事件
 * 3. 当找到不满足条件的值时立即返回 NO
 * 4. 当信号完成时返回 YES
 */
- (RACSignal *)all:(BOOL (^)(id object))predicateBlock {
	NSCParameterAssert(predicateBlock != NULL);

	return [[[self materialize] bind:^{
		return ^(RACEvent *event, BOOL *stop) {
			if (event.eventType == RACEventTypeCompleted) {
				*stop = YES;
				return [RACSignal return:@YES];
			}

			if (event.eventType == RACEventTypeError || !predicateBlock(event.value)) {
				*stop = YES;
				return [RACSignal return:@NO];
			}

			return [RACSignal empty];
		};
	}] setNameWithFormat:@"[%@] -all:", self.name];
}

/**
 * retry: 方法
 * 
 * 功能：当信号出错时重试指定次数
 * 
 * 参数说明：
 * @param retryCount 重试次数，0表示无限重试
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 网络请求：网络请求失败时重试
 * 2. 数据获取：数据获取失败时重试
 * 3. 操作重试：操作失败时重试
 * 
 * 实现原理：
 * 1. 使用 subscribeForever 实现永久订阅
 * 2. 记录当前重试次数
 * 3. 当出错时检查是否还有重试机会
 * 4. 如果有重试机会则重新订阅，否则传递错误
 */
- (RACSignal *)retry:(NSInteger)retryCount {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		__block NSInteger currentRetryCount = 0;
		return subscribeForever(self,
			^(id x) {
				[subscriber sendNext:x];
			},
			^(NSError *error, RACDisposable *disposable) {
				if (retryCount == 0 || currentRetryCount < retryCount) {
					// 重新订阅
					currentRetryCount++;
					return;
				}

				[disposable dispose];
				[subscriber sendError:error];
			},
			^(RACDisposable *disposable) {
				[disposable dispose];
				[subscriber sendCompleted];
			});
	}] setNameWithFormat:@"[%@] -retry: %lu", self.name, (unsigned long)retryCount];
}

/**
 * retry 方法
 * 
 * 功能：当信号出错时无限重试
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 持久化操作：需要确保操作最终成功
 * 2. 关键操作：关键操作失败时必须重试
 * 3. 监控操作：监控操作需要持续进行
 * 
 * 实现原理：
 * 调用 retry: 方法，传递 0 表示无限重试
 */
- (RACSignal *)retry {
	return [[self retry:0] setNameWithFormat:@"[%@] -retry", self.name];
}

/**
 * sample: 方法
 * 
 * 功能：根据采样信号的值发送当前信号的最新值
 * 
 * 参数说明：
 * @param sampler 采样信号
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 定时采样：定时获取最新状态
 * 2. 事件触发：根据事件获取最新数据
 * 3. 状态同步：根据触发条件同步状态
 * 
 * 实现原理：
 * 1. 使用锁保护共享状态
 * 2. 记录当前信号的最新值
 * 3. 当采样信号发送值时，发送当前信号的最新值
 * 4. 确保线程安全
 */
- (RACSignal *)sample:(RACSignal *)sampler {
	NSCParameterAssert(sampler != nil);

	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		// 使用锁保护共享状态
		NSLock *lock = [[NSLock alloc] init];
		__block id lastValue;
		__block BOOL hasValue = NO;

		// 订阅当前信号
		RACSerialDisposable *samplerDisposable = [[RACSerialDisposable alloc] init];
		RACDisposable *sourceDisposable = [self subscribeNext:^(id x) {
			[lock lock];
			hasValue = YES;
			lastValue = x;
			[lock unlock];
		} error:^(NSError *error) {
			[samplerDisposable dispose];
			[subscriber sendError:error];
		} completed:^{
			[samplerDisposable dispose];
			[subscriber sendCompleted];
		}];

		// 订阅采样信号
		samplerDisposable.disposable = [sampler subscribeNext:^(id _) {
			BOOL shouldSend = NO;
			id value;
			[lock lock];
			shouldSend = hasValue;
			value = lastValue;
			[lock unlock];

			if (shouldSend) {
				[subscriber sendNext:value];
			}
		} error:^(NSError *error) {
			[sourceDisposable dispose];
			[subscriber sendError:error];
		} completed:^{
			[sourceDisposable dispose];
			[subscriber sendCompleted];
		}];

		return [RACDisposable disposableWithBlock:^{
			[samplerDisposable dispose];
			[sourceDisposable dispose];
		}];
	}] setNameWithFormat:@"[%@] -sample: %@", self.name, sampler];
}

/**
 * ignoreValues 方法
 * 
 * 功能：忽略信号的所有值，只传递完成和错误事件
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 状态监控：只关心操作是否完成，不关心结果
 * 2. 事件处理：只关心事件是否发生，不关心事件内容
 * 3. 流程控制：只关心流程是否完成
 * 
 * 实现原理：
 * 使用 filter 过滤掉所有值，只保留完成和错误事件
 */
- (RACSignal *)ignoreValues {
	return [[self filter:^(id _) {
		return NO;
	}] setNameWithFormat:@"[%@] -ignoreValues", self.name];
}

/**
 * materialize 方法
 * 
 * 功能：将信号的所有事件（next、error、completed）都包装为 RACEvent 对象
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送 RACEvent 类型的值
 * 
 * 使用场景：
 * 1. 事件处理：需要统一处理所有类型的事件
 * 2. 调试分析：需要分析信号的事件流
 * 3. 事件转换：需要将事件转换为其他格式
 * 
 * 实现原理：
 * 1. 订阅原信号
 * 2. 将 next 事件包装为 RACEvent
 * 3. 将 error 事件包装为 RACEvent 并发送完成
 * 4. 将 completed 事件包装为 RACEvent 并发送完成
 */
- (RACSignal *)materialize {
	return [[RACSignal createSignal:^(id<RACSubscriber> subscriber) {
		return [self subscribeNext:^(id x) {
			[subscriber sendNext:[RACEvent eventWithValue:x]];
		} error:^(NSError *error) {
			[subscriber sendNext:[RACEvent eventWithError:error]];
			[subscriber sendCompleted];
		} completed:^{
			[subscriber sendNext:RACEvent.completedEvent];
			[subscriber sendCompleted];
		}];
	}] setNameWithFormat:@"[%@] -materialize", self.name];
}

/**
 * dematerialize 方法
 * 
 * 功能：将 RACEvent 对象转换回原始的事件流
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 事件恢复：将包装的事件恢复为原始事件
 * 2. 事件处理：处理经过 materialize 的事件流
 * 3. 事件转换：将事件转换为其他格式后恢复
 * 
 * 实现原理：
 * 1. 使用 bind 处理每个 RACEvent
 * 2. 根据事件类型返回相应的信号
 * 3. 对于 completed 事件停止处理
 * 4. 对于 error 事件返回错误信号
 * 5. 对于 next 事件返回包含值的信号
 */
- (RACSignal *)dematerialize {
	return [[self bind:^{
		return ^(RACEvent *event, BOOL *stop) {
			switch (event.eventType) {
				case RACEventTypeCompleted:
					*stop = YES;
					return [RACSignal empty];

				case RACEventTypeError:
					*stop = YES;
					return [RACSignal error:event.error];

				case RACEventTypeNext:
					return [RACSignal return:event.value];
			}
		};
	}] setNameWithFormat:@"[%@] -dematerialize", self.name];
}

/**
 * not 方法
 * 
 * 功能：对信号中的布尔值进行逻辑非操作
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 逻辑运算：对布尔值进行逻辑非操作
 * 2. 条件反转：反转条件判断结果
 * 3. 状态反转：反转状态值
 * 
 * 实现原理：
 * 1. 使用 map 对每个值进行转换
 * 2. 断言确保接收到的是 NSNumber 类型的布尔值
 * 3. 对布尔值进行逻辑非操作
 */
- (RACSignal *)not {
	return [[self map:^(NSNumber *value) {
		NSCAssert([value isKindOfClass:NSNumber.class], @"-not must only be used on a signal of NSNumbers. Instead, got: %@", value);

		return @(!value.boolValue);
	}] setNameWithFormat:@"[%@] -not", self.name];
}

/**
 * and 方法
 * 
 * 功能：对信号中的元组进行逻辑与操作
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 逻辑运算：对多个布尔值进行逻辑与操作
 * 2. 条件组合：组合多个条件判断
 * 3. 状态检查：检查多个状态是否都为真
 * 
 * 实现原理：
 * 1. 使用 map 对每个元组进行转换
 * 2. 断言确保接收到的是 RACTuple 类型且包含至少一个值
 * 3. 使用 rac_sequence 对所有布尔值进行逻辑与操作
 * 4. 断言确保元组中的所有值都是 NSNumber 类型
 */
- (RACSignal *)and {
	return [[self map:^(RACTuple *tuple) {
		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-and must only be used on a signal of RACTuples of NSNumbers. Instead, received: %@", tuple);
		NSCAssert(tuple.count > 0, @"-and must only be used on a signal of RACTuples of NSNumbers, with at least 1 value in the tuple");

		return @([tuple.rac_sequence all:^(NSNumber *number) {
			NSCAssert([number isKindOfClass:NSNumber.class], @"-and must only be used on a signal of RACTuples of NSNumbers. Instead, tuple contains a non-NSNumber value: %@", tuple);

			return number.boolValue;
		}]);
	}] setNameWithFormat:@"[%@] -and", self.name];
}

/**
 * or 方法
 * 
 * 功能：对信号中的元组进行逻辑或操作
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象，发送 BOOL 值
 * 
 * 使用场景：
 * 1. 逻辑运算：对多个布尔值进行逻辑或操作
 * 2. 条件组合：组合多个条件判断
 * 3. 状态检查：检查多个状态中是否有真值
 * 
 * 实现原理：
 * 1. 使用 map 对每个元组进行转换
 * 2. 断言确保接收到的是 RACTuple 类型且包含至少一个值
 * 3. 使用 rac_sequence 对所有布尔值进行逻辑或操作
 * 4. 断言确保元组中的所有值都是 NSNumber 类型
 */
- (RACSignal *)or {
	return [[self map:^(RACTuple *tuple) {
		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-or must only be used on a signal of RACTuples of NSNumbers. Instead, received: %@", tuple);
		NSCAssert(tuple.count > 0, @"-or must only be used on a signal of RACTuples of NSNumbers, with at least 1 value in the tuple");

		return @([tuple.rac_sequence any:^(NSNumber *number) {
			NSCAssert([number isKindOfClass:NSNumber.class], @"-or must only be used on a signal of RACTuples of NSNumbers. Instead, tuple contains a non-NSNumber value: %@", tuple);

			return number.boolValue;
		}]);
	}] setNameWithFormat:@"[%@] -or", self.name];
}

/**
 * reduceApply 方法
 * 
 * 功能：将信号中的元组作为函数调用的参数，第一个元素是函数，其余元素是参数
 * 
 * 参数说明：无
 * 
 * 返回值：新的 RACSignal 对象
 * 
 * 使用场景：
 * 1. 函数调用：动态调用函数
 * 2. 方法调用：动态调用方法
 * 3. 参数传递：动态传递参数
 * 
 * 实现原理：
 * 1. 使用 map 对每个元组进行处理
 * 2. 断言确保接收到的是 RACTuple 类型且包含至少两个元素
 * 3. 将元组转换为数组，保留 RACTupleNil
 * 4. 提取函数和参数
 * 5. 使用 RACBlockTrampoline 调用函数
 */
- (RACSignal *)reduceApply {
	return [[self map:^(RACTuple *tuple) {
		NSCAssert([tuple isKindOfClass:RACTuple.class], @"-reduceApply must only be used on a signal of RACTuples. Instead, received: %@", tuple);
		NSCAssert(tuple.count > 1, @"-reduceApply must only be used on a signal of RACTuples, with at least a block in tuple[0] and its first argument in tuple[1]");

		// 我们不能使用 -array，因为我们需要保留 RACTupleNil
		NSMutableArray *tupleArray = [NSMutableArray arrayWithCapacity:tuple.count];
		for (id val in tuple) {
			[tupleArray addObject:val];
		}
		RACTuple *arguments = [RACTuple tupleWithObjectsFromArray:[tupleArray subarrayWithRange:NSMakeRange(1, tupleArray.count - 1)]];

		return [RACBlockTrampoline invokeBlock:tuple[0] withArguments:arguments];
	}] setNameWithFormat:@"[%@] -reduceApply", self.name];
}

@end
