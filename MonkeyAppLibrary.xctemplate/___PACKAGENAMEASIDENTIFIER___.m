#import "___FILEBASENAME___.h"
#import <UIKit/UIKit.h>
#import <CaptainHook/CaptainHook.h>

// Leave CHUseSubstrate undefined to use CaptainHook's internal runtime backend.
// Replace this class and selector with the method you want to investigate.
CHDeclareClass(UIViewController);

CHMethod1(void, UIViewController, viewDidAppear, BOOL, animated) {
    // Call the original implementation (including other installed hooks).
    CHSuper1(UIViewController, viewDidAppear, animated);
    static BOOL logged;
    if (!logged) {
        logged = YES;
        NSLog(@"[MonkeyDev] CaptainHook hook executed: %@", NSStringFromClass(self.class));
    }
}

__attribute__((constructor)) static void monkeyDevEntry(void) {
    NSLog(@"[MonkeyDev] Objective-C dylib loaded: ___PACKAGENAME___");
    CHLoadClass(UIViewController);
    CHHook1(UIViewController, viewDidAppear);
}
