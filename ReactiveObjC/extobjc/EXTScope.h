//
//  EXTScope.h
//  extobjc
//
//  Created by Justin Spahr-Summers on 2011-05-04.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import "metamacros.h"

/**
 * \@onExit 定义在当前作用域退出时要执行的代码。
 * 代码必须用大括号包围并以分号结尾，无论作用域如何退出都会执行，
 * 包括异常、\c goto、\c return、\c break 和 \c continue。
 *
 * 提供的代码将放入一个稍后执行的块中。请记住这一点，
 * 因为它涉及内存管理、赋值限制等。由于代码在块中使用，
 * \c return 是合法的（虽然可能令人困惑）提前退出清理块的方式。
 *
 * 同一作用域中的多个 \@onExit 语句按相反的词法顺序执行。
 * 这有助于将资源获取与 \@onExit 语句配对，
 * 因为它保证按与获取相反的顺序进行清理。
 *
 * @note 此语句不能在未用大括号定义的作用域中使用（如单行 \c if）。
 * 在实践中，这不是问题，因为 \@onExit 在这种情况下本来就是无用的构造。
 */
#define onExit \
    rac_keywordify \
    __strong rac_cleanupBlock_t metamacro_concat(rac_exitBlock_, __LINE__) __attribute__((cleanup(rac_executeCleanupBlock), unused)) = ^

/**
 * 为作为参数提供的每个变量创建 \c __weak 影子变量，
 * 稍后可以使用 #strongify 再次使其变强。
 *
 * 这通常用于在块中弱引用变量，但然后确保变量在块实际执行期间保持活跃
 * （如果它们在进入时是活跃的）。
 *
 * 有关使用示例，请参见 #strongify。
 */
#define weakify(...) \
    rac_keywordify \
    metamacro_foreach_cxt(rac_weakify_,, __weak, __VA_ARGS__)

/**
 * 类似于 #weakify，但使用 \c __unsafe_unretained 代替，
 * 适用于不支持弱引用的目标或类。
 */
#define unsafeify(...) \
    rac_keywordify \
    metamacro_foreach_cxt(rac_weakify_,, __unsafe_unretained, __VA_ARGS__)

/**
 * 强引用作为参数提供的每个变量，这些变量之前必须已传递给 #weakify。
 *
 * 创建的强引用将遮蔽原始变量名，这样原始名称可以在当前作用域中
 * 无问题地使用（并显著降低保留循环的风险）。
 *
 * @code

    id foo = [[NSObject alloc] init];
    id bar = [[NSObject alloc] init];

    @weakify(foo, bar);

    // 这个块不会保持 'foo' 或 'bar' 活跃
    BOOL (^matchesFooOrBar)(id) = ^ BOOL (id obj){
        // 但现在，在进入时，'foo' 和 'bar' 将保持活跃直到块执行完成
        @strongify(foo, bar);

        return [foo isEqual:obj] || [bar isEqual:obj];
    };

 * @endcode
 */
#define strongify(...) \
    rac_keywordify \
    _Pragma("clang diagnostic push") \
    _Pragma("clang diagnostic ignored \"-Wshadow\"") \
    metamacro_foreach(rac_strongify_,, __VA_ARGS__) \
    _Pragma("clang diagnostic pop")

/*** 实现细节如下 ***/

// 清理块类型定义：无参数无返回值的块
typedef void (^rac_cleanupBlock_t)(void);

/**
 * 执行清理块的静态内联函数
 * @param block 指向清理块的强引用指针
 */
static inline void rac_executeCleanupBlock (__strong rac_cleanupBlock_t *block) {
    (*block)();
}

/**
 * 弱化宏的实现：为变量创建弱引用
 * @param INDEX 宏循环的索引（未使用）
 * @param CONTEXT 上下文修饰符（如 __weak）
 * @param VAR 要弱化的变量名
 */
#define rac_weakify_(INDEX, CONTEXT, VAR) \
    CONTEXT __typeof__(VAR) metamacro_concat(VAR, _weak_) = (VAR);

/**
 * 强化宏的实现：将弱引用重新变为强引用
 * @param INDEX 宏循环的索引（未使用）
 * @param VAR 要强化的变量名
 */
#define rac_strongify_(INDEX, VAR) \
    __strong __typeof__(VAR) VAR = metamacro_concat(VAR, _weak_);

// 关于选择后备关键字的详细信息：
//
// 使用 @try/@catch/@finally 可能导致编译器抑制返回类型警告。
// 使用 @autoreleasepool {} 不会被编译器优化掉，
// 导致创建多余的自动释放池。
//
// 由于两个选项都不完美，且没有其他替代方案，
// 折衷方案是在 DEBUG 构建中使用 @autorelease 以保持编译器分析，
// 在其他情况下使用 @try/@catch 以避免插入不必要的自动释放池。
#if DEBUG
#define rac_keywordify autoreleasepool {}
#else
#define rac_keywordify try {} @catch (...) {}
#endif
