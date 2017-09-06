//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  Created by AloneMonkey on 2017/9/6.
//  Copyright © 2017年 AloneMonkey. All rights reserved.
//

#import "ANYMethodLog.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static __attribute__((constructor)) void entry(){
    NSString* configFilePath = [[NSBundle mainBundle] pathForResource:@"MethodTraceConfig" ofType:@"plist"];
    NSMutableDictionary *configItem = [NSMutableDictionary dictionaryWithContentsOfFile:configFilePath];
    BOOL isEnable = [[configItem valueForKey:@"ENABLE_METHODTRACE"] boolValue];
    if(isEnable){
        NSDictionary* classListDictionary = [configItem valueForKey:@"TARGET_CLASS_LIST"];
        for (NSString* class in classListDictionary.allKeys) {
            Class targetClass = objc_getClass([class UTF8String]);
            if(targetClass != nil){
                BOOL hookAll = YES;
                id methodList = [classListDictionary valueForKey:class];
                if([methodList isKindOfClass:[NSArray class]] && methodList != nil && ((NSArray*)methodList).count > 0){
                    hookAll = NO;
                }
                [ANYMethodLog logMethodWithClass:[targetClass class] condition:^BOOL(SEL sel) {
                    return hookAll ? YES : [methodList containsObject:NSStringFromSelector(sel)];
                } before:^(id target, SEL sel, NSArray *args, int deep) {
                    NSString *selector = NSStringFromSelector(sel);
                    NSArray *selectorArrary = [selector componentsSeparatedByString:@":"];
                    selectorArrary = [selectorArrary filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
                    NSMutableString *selectorString = [NSMutableString new];
                    for (int i = 0; i < selectorArrary.count; i++) {
                        [selectorString appendFormat:@"%@:%@ ", selectorArrary[i], args[i]];
                    }
                    NSMutableString *deepString = [NSMutableString new];
                    for (int i = 0; i < deep; i++) {
                        [deepString appendString:@"-"];
                    }
                    NSLog(@"%@[%@ %@]", deepString , target, selectorString);
                } after:^(id target, SEL sel, NSArray *args, NSTimeInterval interval,int deep, id retValue) {
                    NSMutableString *deepString = [NSMutableString new];
                    for (int i = 0; i < deep; i++) {
                        [deepString appendString:@"-"];
                    }
                    NSLog(@"%@ret:%@", deepString, retValue);
                }];
            }else{
                NSLog(@"canot find class %@", class);
            }
        }
    }else{
        NSLog(@"Method Trace is disable");
    }
}
