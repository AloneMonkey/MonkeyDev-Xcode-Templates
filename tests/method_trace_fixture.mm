#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "MDMethodTrace.h"
#include <atomic>
#include <initializer_list>
#include <dispatch/dispatch.h>

struct MDTraceLarge { double a,b,c,d; };
static std::atomic<unsigned> originalCalls{0};
static std::atomic<unsigned> descriptionCalls{0};
@interface MDTraceBase : NSObject
- (void)ping;
- (void)flag:(BOOL)value;
- (BOOL)boolean:(BOOL)value;
- (int)integer:(int)value;
- (int)nested:(int)value;
- (unsigned)unsignedInteger:(unsigned)value;
- (long long)wide:(long long)value;
- (unsigned long long)unsignedWide:(unsigned long long)value;
- (float)single:(float)value;
- (double)floating:(double)value;
- (id)object:(id)value;
- (id)pair:(id)first other:(id)second;
- (id)selectorName;
- (void)raises;
- (struct MDTraceLarge)large;
+ (double)classFloating:(double)value;
@end
@implementation MDTraceBase
- (void)ping { originalCalls.fetch_add(1); }
- (void)flag:(BOOL)value { NSCAssert(value, @"BOOL argument preserved"); originalCalls.fetch_add(1); }
- (BOOL)boolean:(BOOL)value { return !value; }
- (int)integer:(int)value { return value - 11; }
- (int)nested:(int)value { return [self integer:value]; }
- (unsigned)unsignedInteger:(unsigned)value { return value + 7; }
- (long long)wide:(long long)value { return value + 13; }
- (unsigned long long)unsignedWide:(unsigned long long)value { return value + 19; }
- (float)single:(float)value { return value + 0.5f; }
- (double)floating:(double)value { return value * 2.0; }
- (id)object:(id)value { return value; }
- (id)pair:(id)first other:(id)second { return first ?: second; }
- (id)selectorName { return NSStringFromSelector(_cmd); }
- (void)raises { @throw [NSException exceptionWithName:@"MDTraceExpected" reason:@"fixture" userInfo:nil]; }
- (struct MDTraceLarge)large { return {1,2,3,4}; }
+ (double)classFloating:(double)value { return value + 0.25; }
@end
@interface MDTraceChild : MDTraceBase @end
@implementation MDTraceChild @end

@interface MDTraceDescriptionFailure : NSObject @end
@implementation MDTraceDescriptionFailure
- (NSString *)description { descriptionCalls.fetch_add(1); @throw [NSException exceptionWithName:@"MDTraceDescriptionFailure" reason:@"fixture" userInfo:nil]; }
@end
@interface MDTraceReentrantDescription : NSObject @end
@implementation MDTraceReentrantDescription
- (NSString *)description { return [NSString stringWithFormat:@"nested-value=%d", [[MDTraceChild new] integer:20]]; }
@end

static NSDictionary *status() {
    return [NSJSONSerialization JSONObjectWithData:[md_trace_status() dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
}
static void install(const char *selector, BOOL classMethod = NO) {
    NSString *result = md_trace_start("MDTraceChild", selector, classMethod);
    NSCAssert([result hasPrefix:@"Trace installed"], @"%@", result);
}
int main() {
    @autoreleasepool {
        MDTraceChild *child = [MDTraceChild new];
        NSCAssert([status()[@"methods"] count] == 0 && ![status()[@"enabled"] boolValue], @"off by default");
        IMP original = class_getMethodImplementation(MDTraceBase.class, @selector(ping));
        for (const char *selector : {"ping", "flag:", "boolean:", "integer:", "nested:", "unsignedInteger:", "wide:", "unsignedWide:", "single:", "floating:", "object:", "pair:other:", "selectorName", "raises"}) install(selector);
        install("classFloating:", YES);
        NSCAssert(original == class_getMethodImplementation(MDTraceBase.class, @selector(ping)), @"inherited base untouched");
        [child ping]; [child flag:YES];
        NSCAssert(originalCalls.load() == 2, @"original methods ran exactly once");
        NSCAssert([child boolean:NO], @"BOOL result");
        NSCAssert([child integer:-9] == -20, @"int ABI");
        NSCAssert([child nested:25] == 14, @"nested traced methods preserve execution");
        NSCAssert([child unsignedInteger:0xffffff00u] == 0xffffff07u, @"unsigned ABI");
        NSCAssert([child wide:0x100000000ll] == 0x10000000dll, @"wide ABI");
        NSCAssert([child unsignedWide:0x8000000000000000ull] == 0x8000000000000013ull, @"unsigned wide ABI");
        NSCAssert([child single:1.25f] == 1.75f && [child floating:1.25] == 2.5, @"float ABI");
        NSObject *object = [NSObject new];
        NSCAssert([child object:object] == object && [child pair:nil other:object] == object, @"object identity");
        NSCAssert([child object:nil] == nil, @"nil preserved");
        NSString *text = @"trace-value\nsecond-line";
        NSCAssert([child object:text] == text, @"string result preserved");
        NSString *longText = [@"A" stringByPaddingToLength:2000 withString:@"A" startingAtIndex:0];
        NSCAssert([child object:longText] == longText, @"truncation only changes logs");
        id failure = [MDTraceDescriptionFailure new];
        md_trace_set_descriptions(NO);
        NSCAssert([child object:failure] == failure && descriptionCalls.load() == 0, @"address-only mode does not call description");
        NSCAssert(![status()[@"descriptions"] boolValue], @"description setting reported");
        md_trace_set_descriptions(YES);
        NSCAssert([child object:failure] == failure, @"description exception does not escape");
        NSCAssert(descriptionCalls.load() == 2, @"argument and return descriptions attempted once each");
        id recursive = [MDTraceReentrantDescription new];
        NSCAssert([child object:recursive] == recursive, @"description can reenter without recursive logs");
        NSCAssert([[child selectorName] isEqual:@"selectorName"], @"original _cmd preserved");
        NSCAssert([MDTraceChild classFloating:1.0] == 1.25, @"class method ABI");
        @try { [child raises]; NSCAssert(NO, @"must throw"); }
        @catch(NSException *exception) { NSCAssert([exception.name isEqual:@"MDTraceExpected"], @"original exception"); }
        NSCAssert([md_trace_start("MDTraceChild", "ping", NO) hasPrefix:@"Trace already"], @"idempotent install");
        NSCAssert([md_trace_start("MDTraceChild", "large", NO) hasPrefix:@"Trace rejected: unsupported"], @"reject struct ABI");
        struct MDTraceLarge large = [child large]; NSCAssert(large.d == 4, @"rejected method unchanged");
        NSCAssert([md_trace_start("MDTraceChild", "init", NO) hasPrefix:@"Trace rejected"], @"reject ownership family");
        NSCAssert([md_trace_start("NoSuchClass", "ping", NO) hasPrefix:@"Trace rejected"], @"unknown class");
        dispatch_apply(200, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t) {
            @autoreleasepool { NSCAssert([child integer:19] == 8, @"concurrent original calls"); }
        });
        NSDictionary *beforeStop = status();
        md_trace_stop(); [child ping];
        NSDictionary *stopped = status();
        NSCAssert(![stopped[@"enabled"] boolValue], @"stop logging");
        NSCAssert([beforeStop[@"methods"] count] == 15, @"only supported hooks installed");
        for (NSDictionary *entry in stopped[@"methods"]) {
            NSCAssert([entry[@"before"] isEqual:entry[@"after"]], @"balanced before/after including throw");
            NSCAssert([entry[@"before"] unsignedIntValue] <= 100, @"sample budget");
            if ([entry[@"selector"] isEqual:@"raises"]) NSCAssert([entry[@"thrown"] intValue] == 1, @"exception recorded");
            if ([entry[@"selector"] isEqual:@"integer:"]) NSCAssert([entry[@"limitReached"] boolValue] && [entry[@"before"] intValue] == 100, @"sampling exhaustion reported");
            if ([entry[@"selector"] isEqual:@"ping"]) NSCAssert([entry[@"before"] intValue] == 1 && [entry[@"calls"] intValue] == 2, @"stopped wrapper calls original without logging");
        }
        NSCAssert(originalCalls.load() == 3, @"stop keeps original execution");
        NSLog(@"[MonkeyDevTraceTest] PASS: ABI, original selector, inheritance, exception, concurrency, stop and rejected signatures");
    }
}
