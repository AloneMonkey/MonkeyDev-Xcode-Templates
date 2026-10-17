// MonkeyDev debugger helpers; no constructors, hooks or automatic heap scanning.
#import "LLDBTools.h"
#import <TargetConditionals.h>
#import <objc/runtime.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

#if DEBUG
#define MD_DEBUG_EXPORT __attribute__((used, noinline, visibility("default")))

static NSString *MDString(const char *text) {
    return text ? ([NSString stringWithUTF8String:text] ?: @"<invalid UTF-8>") : @"<unknown>";
}

MD_DEBUG_EXPORT NSString *methods(const char *className) {
    if (!className || !*className) return @"LLDBTools: provide an Objective-C runtime class name.";
    Class cls = objc_lookUpClass(className);
    if (!cls) return [NSString stringWithFormat:@"LLDBTools: class not found: %@", MDString(className)];
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger depth = 0; cls && depth < 64; ++depth, cls = class_getSuperclass(cls)) {
        [result appendFormat:@"Class %@\n", MDString(class_getName(cls))];
        for (unsigned kind = 0; kind < 2; ++kind) {
            unsigned count = 0;
            Method *list = class_copyMethodList(kind ? object_getClass(cls) : cls, &count);
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            for (unsigned i = 0; i < count; ++i) {
                Method method = list[i];
                [lines addObject:[NSString stringWithFormat:@"%c[%@ %@] type=%@ IMP=%p\n", kind ? '+' : '-',
                    MDString(class_getName(cls)), MDString(sel_getName(method_getName(method))),
                    MDString(method_getTypeEncoding(method)), (void *)method_getImplementation(method)]];
            }
            free(list);
            for (NSString *line in [lines sortedArrayUsingSelector:@selector(compare:)]) [result appendString:line];
        }
    }
    return result;
}

MD_DEBUG_EXPORT NSString *ivars(uintptr_t address) {
    if (!address) return @"LLDBTools: provide the address of a live Objective-C object.";
    // Do not retain, describe, or read ivar values of the inspected object.
    __unsafe_unretained id target = (__bridge id)(void *)address;
    Class cls = object_getClass(target);
    NSMutableString *result = [NSMutableString stringWithFormat:@"Object %p class=%@ (ivar metadata)\n", (void *)address, MDString(class_getName(cls))];
    for (NSUInteger depth = 0; cls && depth < 64; ++depth, cls = class_getSuperclass(cls)) {
        unsigned count = 0;
        Ivar *list = class_copyIvarList(cls, &count);
        for (unsigned i = 0; i < count; ++i) {
            [result appendFormat:@"%@.%@ type=%@ offset=%td\n", MDString(class_getName(cls)),
                MDString(ivar_getName(list[i])), MDString(ivar_getTypeEncoding(list[i])), ivar_getOffset(list[i])];
        }
        free(list);
    }
    return result;
}

#if TARGET_OS_IOS
static NSArray<UIWindow *> *MDWindows(void) {
    UIApplication *app = UIApplication.sharedApplication;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    // Enumerate scenes rather than assuming a single global keyWindow.
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive &&
            scene.activationState != UISceneActivationStateForegroundInactive) continue;
        [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    if (!windows.count) {
        // Legacy applications without their own scene lifecycle (the bundled Demo).
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:app.windows];
#pragma clang diagnostic pop
    }
    NSMutableArray<UIWindow *> *visible = [NSMutableArray array];
    for (UIWindow *window in windows) if (!window.hidden && window.alpha > 0) [visible addObject:window];
    return visible;
}

static NSString *MDMainThreadError(void) {
    return NSThread.isMainThread ? nil : @"LLDBTools: select the main thread in LLDB before invoking a UI helper; no dispatch_sync is performed.";
}

static void MDWalkView(UIView *view, NSUInteger depth, NSMutableString *output, NSMutableSet<NSValue *> *seen, NSUInteger *remaining) {
    if (!view || !*remaining || depth > 32) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)view];
    if ([seen containsObject:key]) return;
    [seen addObject:key]; --*remaining;
    [output appendFormat:@"%@<%@:%p> frame=%@ hidden=%d alpha=%.3f\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        MDString(class_getName(object_getClass(view))), (__bridge void *)view, NSStringFromCGRect(view.frame), view.hidden, view.alpha];
    for (UIView *child in view.subviews) MDWalkView(child, depth + 1, output, seen, remaining);
}

static void MDWalkController(UIViewController *controller, NSUInteger depth, NSMutableString *output, NSMutableSet<NSValue *> *seen, NSUInteger *remaining) {
    if (!controller || !*remaining || depth > 32) return;
    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)controller];
    if ([seen containsObject:key]) return;
    [seen addObject:key]; --*remaining;
    [output appendFormat:@"%@<%@:%p> viewLoaded=%d\n", [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        MDString(class_getName(object_getClass(controller))), (__bridge void *)controller, controller.isViewLoaded];
    for (UIViewController *child in controller.childViewControllers) MDWalkController(child, depth + 1, output, seen, remaining);
    MDWalkController(controller.presentedViewController, depth + 1, output, seen, remaining);
}
#endif

MD_DEBUG_EXPORT NSString *pviews(void) {
#if TARGET_OS_IOS
    NSString *error = MDMainThreadError(); if (error) return error;
    NSMutableString *result = [NSMutableString string];
    NSUInteger remaining = 2000;
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    for (UIWindow *window in MDWindows()) MDWalkView(window, 0, result, seen, &remaining);
    if (!remaining) [result appendString:@"[truncated: 2000 views]\n"];
    return result.length ? result : @"LLDBTools: no visible foreground windows.";
#else
    return @"LLDBTools: pviews requires UIKit on iOS.";
#endif
}

MD_DEBUG_EXPORT NSString *pvc(void) {
#if TARGET_OS_IOS
    NSString *error = MDMainThreadError(); if (error) return error;
    NSMutableString *result = [NSMutableString string];
    NSUInteger remaining = 2000;
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    for (UIWindow *window in MDWindows()) {
        [result appendFormat:@"Window <%@:%p> key=%d\n", MDString(class_getName(object_getClass(window))), (__bridge void *)window, window.isKeyWindow];
        MDWalkController(window.rootViewController, 1, result, seen, &remaining);
    }
    if (!remaining) [result appendString:@"[truncated: 2000 controllers]\n"];
    return result.length ? result : @"LLDBTools: no visible foreground windows.";
#else
    return @"LLDBTools: pvc requires UIKit on iOS.";
#endif
}

MD_DEBUG_EXPORT NSString *pactions(uintptr_t address) {
#if TARGET_OS_IOS
    NSString *error = MDMainThreadError(); if (error) return error;
    if (!address) return @"LLDBTools: provide a live UIControl address.";
    __unsafe_unretained UIControl *control = (__bridge UIControl *)(void *)address;
    if (![control isKindOfClass:UIControl.class]) return @"LLDBTools: object is not a UIControl.";
    NSMutableString *result = [NSMutableString string];
    for (id target in control.allTargets) {
        NSMutableOrderedSet<NSString *> *actions = [NSMutableOrderedSet orderedSet];
        UIControlEvents registered = control.allControlEvents;
        for (UIControlEvents event = 1; event; event <<= 1) {
            if (!(registered & event)) continue;
            NSArray<NSString *> *names = [control actionsForTarget:target forControlEvent:event];
            if (names) [actions addObjectsFromArray:names];
        }
        if (actions.count) [result appendFormat:@"<%@:%p> %@\n", MDString(class_getName(object_getClass(target))), (__bridge void *)target, [actions.array componentsJoinedByString:@", "]];
    }
    return result.length ? result : @"LLDBTools: no target/action selectors (UIAction handlers are not enumerated).";
#else
    (void)address;
    return @"LLDBTools: pactions requires UIKit on iOS.";
#endif
}
// C calls bind to this translation unit, not LLDB's broad symbol-name lookup.
MD_DEBUG_EXPORT NSString *md_pvc(void) { return pvc(); }
MD_DEBUG_EXPORT NSString *md_pviews(void) { return pviews(); }
MD_DEBUG_EXPORT NSString *md_pactions(uintptr_t address) { return pactions(address); }
MD_DEBUG_EXPORT NSString *md_methods(const char *className) { return methods(className); }
MD_DEBUG_EXPORT NSString *md_ivars(uintptr_t address) { return ivars(address); }
#endif // DEBUG
