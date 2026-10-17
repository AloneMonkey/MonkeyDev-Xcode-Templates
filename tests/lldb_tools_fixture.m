#import <Foundation/Foundation.h>
#import "LLDBTools.h"
@interface MDHelperBase : NSObject { @public int _fixtureNumber; }
- (int)fixtureMethod;
+ (void)fixtureClassMethod;
@end
@implementation MDHelperBase
- (int)fixtureMethod { return 17; }
+ (void)fixtureClassMethod {}
@end
@interface MDHelperChild : MDHelperBase { @public double _childValue; }
@end
@implementation MDHelperChild
@end
int main(void) {
    @autoreleasepool {
        MDHelperChild *object = [MDHelperChild new];
        NSString *m = md_methods("MDHelperChild");
        NSCAssert([m containsString:@"-[MDHelperBase fixtureMethod]"], @"inherited instance method");
        NSCAssert([m containsString:@"+[MDHelperBase fixtureClassMethod]"], @"class method");
        NSString *v = md_ivars((uintptr_t)(__bridge void *)object);
        NSCAssert([v containsString:@"_fixtureNumber type=i offset="], @"base ivar");
        NSCAssert([v containsString:@"_childValue type=d offset="], @"child ivar");
        NSCAssert([methods(NULL) containsString:@"provide"], @"null class");
        NSCAssert([methods("NoSuchMonkeyDevClass") containsString:@"not found"], @"unknown class");
        NSCAssert([ivars(0) containsString:@"live"], @"null object");
        NSLog(@"[MonkeyDevLLDBTools] PASS: runtime metadata, inheritance and invalid inputs");
    }
}
