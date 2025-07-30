//
//  RACStream.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-31.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACStream.h"
#import "NSObject+RACDescription.h"
#import "RACBlockTrampoline.h"
#import "RACTuple.h"

/**
 * RACStream 是 ReactiveObjC 中流式操作的抽象基类
 * 
 * 核心概念：
 * - Stream（流）：表示一个可以产生值的序列
 * - 流是不可变的，操作会返回新的流
 * - 支持函数式编程范式，提供链式调用
 * - 实现了 Monad 模式，支持 bind/flattenMap 操作
 * 
 * 主要特性：
 * - 抽象基类，定义了流的基本操作接口
 * - 提供丰富的操作符用于流转换和组合
 * - 支持流的命名，便于调试
 * - 实现了惰性求值，只有在订阅时才开始执行
 */
@implementation RACStream

#pragma mark Lifecycle

/**
 * 初始化方法
 * 设置默认的流名称为空字符串
 */
- (instancetype)init {
	self = [super init];

	self.name = @"";
	return self;
}

#pragma mark Abstract methods

/**
 * 返回一个空流
 * 
 * 抽象方法，必须由子类实现
 * 空流不产生任何值，通常用于表示"无数据"状态
 * 
 * @return 空流实例
 */
+ (__kindof RACStream *)empty {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/**
 * 绑定操作（Monad 的 bind 操作）
 * 
 * 这是流操作的核心方法，类似于 Haskell 中的 >>= 操作符
 * 将当前流中的每个值通过 block 转换为新的流
 * 
 * @param block 返回绑定 block 的 block
 * @return 绑定后的新流
 */
- (__kindof RACStream *)bind:(RACStreamBindBlock (^)(void))block {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/**
 * 返回一个只包含指定值的流
 * 
 * 类似于 Haskell 中的 return 函数
 * 将单个值包装成流
 * 
 * @param value 要包装的值
 * @return 包含该值的流
 */
+ (__kindof RACStream *)return:(id)value {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/**
 * 串联操作
 * 
 * 将当前流与另一个流按顺序连接
 * 先产生当前流的所有值，再产生参数流的所有值
 * 
 * @param stream 要串联的流
 * @return 串联后的新流
 */
- (__kindof RACStream *)concat:(RACStream *)stream {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

/**
 * 配对操作
 * 
 * 将当前流与另一个流按元素一一配对
 * 当两个流都有值时，产生包含两个值的元组
 * 
 * @param stream 要配对的流
 * @return 配对后的新流
 */
- (__kindof RACStream *)zipWith:(RACStream *)stream {
	NSString *reason = [NSString stringWithFormat:@"%@ 必须由子类重写", NSStringFromSelector(_cmd)];
	@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:reason userInfo:nil];
}

#pragma mark Naming

/**
 * 设置流的名称，用于调试
 * 
 * 只有在设置了环境变量 RAC_DEBUG_SIGNAL_NAMES 时才会生效
 * 便于在调试时识别不同的流
 * 
 * @param format 名称格式字符串
 * @return 设置名称后的流（支持链式调用）
 */
- (instancetype)setNameWithFormat:(NSString *)format, ... {
	if (getenv("RAC_DEBUG_SIGNAL_NAMES") == NULL) return self;

	NSCParameterAssert(format != nil);

	va_list args;
	va_start(args, format);

	NSString *str = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);

	self.name = str;
	return self;
}

@end

// MARK: - RACStream 操作扩展
/**
 * RACStream 的操作扩展
 * 
 * 提供了丰富的流操作符，包括：
 * - 转换操作：map, filter, flattenMap
 * - 组合操作：concat, zip, combine
 * - 控制操作：take, skip, distinctUntilChanged
 * - 累积操作：scan, reduce
 */
@implementation RACStream (Operations)

/**
 * flattenMap: 核心转换操作
 * 
 * 将流中的每个元素通过 block 转换为新的流，然后将所有流合并为一个流
 * 这是实现其他操作的基础
 * 
 * 工作流程：
 * 1. 接收流中的每个值
 * 2. 通过 block 将值转换为新的流
 * 3. 将所有新流合并为一个流
 * 
 * @param block 转换 block，接收值并返回新的流
 * @return 合并后的新流
 */
- (__kindof RACStream *)flattenMap:(__kindof RACStream * (^)(id value))block {
	Class class = self.class;

	return [[self bind:^{
		// 返回一个 block，每次处理流中的一个元素
		return ^(id value, BOOL *stop) {
			id stream = block(value) ?: [class empty];
			NSCAssert([stream isKindOfClass:RACStream.class], @"-flattenMap: 返回的不是 RACStream 类型: %@", stream);

			return stream;
		};
	}] setNameWithFormat:@"[%@] -flattenMap:", self.name];
}

/**
 * flatten: 扁平化操作
 * 
 * 将流中的元素（本身为流）合并为一个流
 * 相当于 flattenMap 的特殊情况，直接返回元素本身
 * 
 * @return 扁平化后的流
 */
- (__kindof RACStream *)flatten {
	return [[self flattenMap:^(id value) {
		return value;
	}] setNameWithFormat:@"[%@] -flatten", self.name];
}

/**
 * map: 映射操作
 * 
 * 对流中的每个元素应用 block，并返回新的流
 * 类似于函数式编程中的 map 函数
 * 
 * @param block 转换 block，接收值并返回新值
 * @return 映射后的新流
 */
- (__kindof RACStream *)map:(id (^)(id value))block {
	NSCParameterAssert(block != nil);

	Class class = self.class;
	
	return [[self flattenMap:^(id value) {
		return [class return:block(value)];
	}] setNameWithFormat:@"[%@] -map:", self.name];
}

/**
 * mapReplace: 替换操作
 * 
 * 用指定的对象替换流中的每个元素
 * 忽略原始值，统一返回指定对象
 * 
 * @param object 要替换的对象
 * @return 替换后的新流
 */
- (__kindof RACStream *)mapReplace:(id)object {
	return [[self map:^(id _) {
		return object;
	}] setNameWithFormat:@"[%@] -mapReplace: %@", self.name, RACDescription(object)];
}

/**
 * combinePreviousWithStart:reduce: 组合前一个和当前元素
 * 
 * 结合前一个和当前元素，通过 reduceBlock 生成新值
 * 第一个值会与 start 参数组合
 * 
 * @param start 起始值
 * @param reduceBlock 组合 block，接收前一个值和当前值，返回新值
 * @return 组合后的新流
 */
- (__kindof RACStream *)combinePreviousWithStart:(id)start reduce:(id (^)(id previous, id next))reduceBlock {
	NSCParameterAssert(reduceBlock != NULL);
	return [[[self
		scanWithStart:RACTuplePack(start)
		reduce:^(RACTuple *previousTuple, id next) {
			id value = reduceBlock(previousTuple[0], next);
			return RACTuplePack(next, value);
		}]
		map:^(RACTuple *tuple) {
			return tuple[1];
		}]
		setNameWithFormat:@"[%@] -combinePreviousWithStart: %@ reduce:", self.name, RACDescription(start)];
}

/**
 * filter: 过滤操作
 * 
 * 过滤流中的元素，仅保留 block 返回 YES 的元素
 * 类似于函数式编程中的 filter 函数
 * 
 * @param block 过滤条件 block，返回 YES 表示保留该元素
 * @return 过滤后的新流
 */
- (__kindof RACStream *)filter:(BOOL (^)(id value))block {
	NSCParameterAssert(block != nil);

	Class class = self.class;
	
	return [[self flattenMap:^ id (id value) {
		if (block(value)) {
			return [class return:value];
		} else {
			return class.empty;
		}
	}] setNameWithFormat:@"[%@] -filter:", self.name];
}

/**
 * ignore: 忽略操作
 * 
 * 忽略等于指定值的元素
 * 使用 isEqual: 进行相等性比较
 * 
 * @param value 要忽略的值
 * @return 忽略指定值后的新流
 */
- (__kindof RACStream *)ignore:(id)value {
	return [[self filter:^ BOOL (id innerValue) {
		return innerValue != value && ![innerValue isEqual:value];
	}] setNameWithFormat:@"[%@] -ignore: %@", self.name, RACDescription(value)];
}

/**
 * reduceEach: 对元组元素进行归约操作
 * 
 * 对流中的 RACTuple 元素应用 reduceBlock
 * 将元组中的值作为参数传递给 reduceBlock
 * 
 * @param reduceBlock 归约 block，接收元组中的值作为参数
 * @return 归约后的新流
 */
- (__kindof RACStream *)reduceEach:(RACReduceBlock)reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	__weak RACStream *stream __attribute__((unused)) = self;
	return [[self map:^(RACTuple *t) {
		NSCAssert([t isKindOfClass:RACTuple.class], @"流 %@ 的元素不是 RACTuple: %@", stream, t);
		return [RACBlockTrampoline invokeBlock:reduceBlock withArguments:t];
	}] setNameWithFormat:@"[%@] -reduceEach:", self.name];
}

/**
 * startWith: 前置操作
 * 
 * 在流前面插入一个元素
 * 新流会先产生指定值，然后产生原流的所有值
 * 
 * @param value 要前置的值
 * @return 前置值后的新流
 */
- (__kindof RACStream *)startWith:(id)value {
	return [[[self.class return:value]
		concat:self]
		setNameWithFormat:@"[%@] -startWith: %@", self.name, RACDescription(value)];
}

/**
 * skip: 跳过操作
 * 
 * 跳过前 skipCount 个元素
 * 从第 skipCount + 1 个元素开始产生值
 * 
 * @param skipCount 要跳过的元素数量
 * @return 跳过指定数量元素后的新流
 */
- (__kindof RACStream *)skip:(NSUInteger)skipCount {
	Class class = self.class;
	
	return [[self bind:^{
		__block NSUInteger skipped = 0;

		return ^(id value, BOOL *stop) {
			if (skipped >= skipCount) return [class return:value];

			skipped++;
			return class.empty;
		};
	}] setNameWithFormat:@"[%@] -skip: %lu", self.name, (unsigned long)skipCount];
}

/**
 * take: 取值操作
 * 
 * 只取前 count 个元素
 * 取完指定数量的元素后停止
 * 
 * @param count 要取的元素数量
 * @return 只包含前 count 个元素的新流
 */
- (__kindof RACStream *)take:(NSUInteger)count {
	Class class = self.class;
	
	if (count == 0) return class.empty;

	return [[self bind:^{
		__block NSUInteger taken = 0;

		return ^ id (id value, BOOL *stop) {
			if (taken < count) {
				++taken;
				if (taken == count) *stop = YES;
				return [class return:value];
			} else {
				return nil;
			}
		};
	}] setNameWithFormat:@"[%@] -take: %lu", self.name, (unsigned long)count];
}

/**
 * join: 连接多个流
 * 
 * 将多个流合并为一个流，并通过 block 组合
 * 这是一个复杂的操作，用于处理多个流的组合
 * 
 * @param streams 要连接的流集合
 * @param block 组合 block，接收两个流并返回组合后的流
 * @return 连接后的新流
 */
+ (__kindof RACStream *)join:(id<NSFastEnumeration>)streams block:(RACStream * (^)(id, id))block {
	RACStream *current = nil;

	// 依次将输入流合并为更大的元组流
	for (RACStream *stream in streams) {
		// 第一个流，直接包装为 RACTuple
		if (current == nil) {
			current = [stream map:^(id x) {
				return RACTuplePack(x);
			}];

			continue;
		}

		current = block(current, stream);
	}

	if (current == nil) return [self empty];

	return [current map:^(RACTuple *xs) {
		// 解包嵌套元组，生成最终的 RACTuple
		NSMutableArray *values = [[NSMutableArray alloc] init];

		while (xs != nil) {
			[values insertObject:xs.last ?: RACTupleNil.tupleNil atIndex:0];
			xs = (xs.count > 1 ? xs.first : nil);
		}

		return [RACTuple tupleWithObjectsFromArray:values];
	}];
}

/**
 * zip: 配对多个流
 * 
 * 将多个流按顺序配对组合为元组流
 * 当所有流都有值时，产生包含所有值的元组
 * 
 * @param streams 要配对的流集合
 * @return 配对后的新流
 */
+ (__kindof RACStream *)zip:(id<NSFastEnumeration>)streams {
	return [[self join:streams block:^(RACStream *left, RACStream *right) {
		return [left zipWith:right];
	}] setNameWithFormat:@"+zip: %@", streams];
}

/**
 * zip:reduce: 配对后归约
 * 
 * 将多个流配对后应用 reduceBlock 生成新流
 * 先进行配对，再对配对结果进行归约
 * 
 * @param streams 要配对的流集合
 * @param reduceBlock 归约 block
 * @return 配对归约后的新流
 */
+ (__kindof RACStream *)zip:(id<NSFastEnumeration>)streams reduce:(RACGenericReduceBlock)reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	RACStream *result = [self zip:streams];

	// 兼容旧版本 reduceBlock 为空的情况
	if (reduceBlock != nil) result = [result reduceEach:reduceBlock];

	return [result setNameWithFormat:@"+zip: %@ reduce:", streams];
}

/**
 * concat: 串联多个流
 * 
 * 将多个流顺序串联为一个流
 * 先产生第一个流的所有值，再产生第二个流的所有值，以此类推
 * 
 * @param streams 要串联的流集合
 * @return 串联后的新流
 */
+ (__kindof RACStream *)concat:(id<NSFastEnumeration>)streams {
	RACStream *result = self.empty;
	for (RACStream *stream in streams) {
		result = [result concat:stream];
	}

	return [result setNameWithFormat:@"+concat: %@", streams];
}

/**
 * scanWithStart:reduce: 累加操作
 * 
 * 对流中的每个元素应用 reduceBlock，累积结果
 * 类似于函数式编程中的 scan 函数
 * 
 * @param startingValue 起始值
 * @param reduceBlock 累加 block，接收累积值和当前值，返回新的累积值
 * @return 累加后的新流
 */
- (__kindof RACStream *)scanWithStart:(id)startingValue reduce:(id (^)(id running, id next))reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	return [[self
		scanWithStart:startingValue
		reduceWithIndex:^(id running, id next, NSUInteger index) {
			return reduceBlock(running, next);
		}]
		setNameWithFormat:@"[%@] -scanWithStart: %@ reduce:", self.name, RACDescription(startingValue)];
}

/**
 * scanWithStart:reduceWithIndex: 带索引的累加操作
 * 
 * 累加操作的高级版本，提供元素索引
 * 
 * @param startingValue 起始值
 * @param reduceBlock 累加 block，接收累积值、当前值和索引
 * @return 累加后的新流
 */
- (__kindof RACStream *)scanWithStart:(id)startingValue reduceWithIndex:(id (^)(id, id, NSUInteger))reduceBlock {
	NSCParameterAssert(reduceBlock != nil);

	Class class = self.class;

	return [[self bind:^{
		__block id running = startingValue;
		__block NSUInteger index = 0;

		return ^(id value, BOOL *stop) {
			running = reduceBlock(running, value, index++);
			return [class return:running];
		};
	}] setNameWithFormat:@"[%@] -scanWithStart: %@ reduceWithIndex:", self.name, RACDescription(startingValue)];
}

/**
 * takeUntilBlock: 条件取值操作
 * 
 * 持续取值直到满足 predicate 条件
 * 当 predicate 返回 YES 时停止取值
 * 
 * @param predicate 停止条件 block
 * @return 条件取值后的新流
 */
- (__kindof RACStream *)takeUntilBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	Class class = self.class;
	
	return [[self bind:^{
		return ^ id (id value, BOOL *stop) {
			if (predicate(value)) return nil;

			return [class return:value];
		};
	}] setNameWithFormat:@"[%@] -takeUntilBlock:", self.name];
}

/**
 * takeWhileBlock: 条件取值操作
 * 
 * 只要 predicate 返回 YES 就持续取值
 * 当 predicate 返回 NO 时停止取值
 * 
 * @param predicate 继续条件 block
 * @return 条件取值后的新流
 */
- (__kindof RACStream *)takeWhileBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	return [[self takeUntilBlock:^ BOOL (id x) {
		return !predicate(x);
	}] setNameWithFormat:@"[%@] -takeWhileBlock:", self.name];
}

/**
 * skipUntilBlock: 条件跳过操作
 * 
 * 满足 predicate 前跳过所有元素
 * 当 predicate 返回 YES 时开始取值
 * 
 * @param predicate 开始条件 block
 * @return 条件跳过后的新流
 */
- (__kindof RACStream *)skipUntilBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	Class class = self.class;
	
	return [[self bind:^{
		__block BOOL skipping = YES;

		return ^ id (id value, BOOL *stop) {
			if (skipping) {
				if (predicate(value)) {
					skipping = NO;
				} else {
					return class.empty;
				}
			}

			return [class return:value];
		};
	}] setNameWithFormat:@"[%@] -skipUntilBlock:", self.name];
}

/**
 * skipWhileBlock: 条件跳过操作
 * 
 * 只要 predicate 返回 YES 就跳过
 * 当 predicate 返回 NO 时开始取值
 * 
 * @param predicate 跳过条件 block
 * @return 条件跳过后的新流
 */
- (__kindof RACStream *)skipWhileBlock:(BOOL (^)(id x))predicate {
	NSCParameterAssert(predicate != nil);

	return [[self skipUntilBlock:^ BOOL (id x) {
		return !predicate(x);
	}] setNameWithFormat:@"[%@] -skipWhileBlock:", self.name];
}

/**
 * distinctUntilChanged: 去重操作
 * 
 * 过滤掉连续重复的元素
 * 使用 isEqual: 进行相等性比较
 * 只过滤相邻的重复元素，不相邻的相同元素会被保留
 * 
 * @return 去重后的新流
 */
- (__kindof RACStream *)distinctUntilChanged {
	Class class = self.class;

	return [[self bind:^{
		__block id lastValue = nil;
		__block BOOL initial = YES;

		return ^(id x, BOOL *stop) {
			if (!initial && (lastValue == x || [x isEqual:lastValue])) return [class empty];

			initial = NO;
			lastValue = x;
			return [class return:x];
		};
	}] setNameWithFormat:@"[%@] -distinctUntilChanged", self.name];
}

@end
