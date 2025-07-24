//
//  NSArray+RACSequenceAdditions.m
//  ReactiveObjC
//
//  Created by Justin Spahr-Summers on 2012-10-29.
//  Copyright (c) 2012 GitHub. All rights reserved.
//

#import "NSArray+RACSequenceAdditions.h"
#import "RACArraySequence.h"

@implementation NSArray (RACSequenceAdditions)

// 返回一个与当前NSArray对象对应的RACSequence序列。
// 该方法通过RACArraySequence的工厂方法创建一个新的序列，
// 并以当前数组和偏移量0作为参数。
// 注意：对原数组的修改不会影响已创建的序列。
- (RACSequence *)rac_sequence {
    // 使用RACArraySequence的sequenceWithArray:offset:方法，
    // 以当前数组和偏移量0创建一个新的RACSequence对象。
    return [RACArraySequence sequenceWithArray:self offset:0];
}

@end
