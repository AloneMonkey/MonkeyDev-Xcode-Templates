// Explicit typed wrappers replace the old global NSObject forwarding/remap engine.
#import "MDMethodTrace.h"
#if DEBUG
#if !defined(__arm64__) || defined(__arm64e__)
#error MDMethodTrace currently supports arm64 only, not arm64e/PAC.
#endif
#import <objc/runtime.h>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <type_traits>
#include <vector>
#include <time.h>
#include <pthread.h>

namespace {
constexpr unsigned sampleLimit = 100;
constexpr size_t hookLimit = 128;
struct Trace {
    __strong NSString *name;
    __strong NSString *selectorName;
    Class destination;
    SEL selector;
    bool classMethod;
    IMP original;
    std::atomic<uint64_t> calls{0}, attempts{0}, before{0}, after{0}, thrown{0};
};
// Function-local initialization also supports registration from dylib constructors.
static std::mutex &registryMutex() { static auto *value = new std::mutex; return *value; }
static std::vector<std::shared_ptr<Trace>> &registry() {
    static auto *value = new std::vector<std::shared_ptr<Trace>>; return *value;
}
static std::atomic<bool> enabled{false};
static std::atomic<bool> descriptions{true};
static std::atomic<uint64_t> nextCallID{1};
struct Call {
    bool active;
    unsigned level;
    uint64_t start, identifier, thread;
};
static thread_local unsigned depth = 0;
static thread_local bool inLogger = false;

static NSString *boundedText(NSString *text) {
    if (!text) return @"<nil description>";
    if (text.length > 512) text = [[text substringToIndex:512] stringByAppendingString:@"…<truncated>"];
    return [[text stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"]
        stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
}
static NSString *formatValue(id value) {
    if (!value) return @"nil";
    NSString *identity = [NSString stringWithFormat:@"<%s:%p>", class_getName(object_getClass(value)), (__bridge void *)value];
    if (!descriptions.load(std::memory_order_relaxed)) return identity;
    NSString *description;
    @try { description = boundedText([value description]); }
    @catch (NSException *exception) {
        description = [NSString stringWithFormat:@"<description threw %@>", boundedText(exception.name)];
    }
    return [NSString stringWithFormat:@"%@ %@", identity, description];
}
template<typename T> static NSString *formatValue(T value) {
    if constexpr (std::is_same<T, bool>::value) return value ? @"YES" : @"NO";
    else if constexpr (std::is_floating_point<T>::value) return [NSString stringWithFormat:@"%.17g", (double)value];
    else if constexpr (std::is_signed<T>::value) return [NSString stringWithFormat:@"%lld", (long long)value];
    else return [NSString stringWithFormat:@"%llu", (unsigned long long)value];
}
// Render inside the recursion guard: an object's description may itself call a
// traced method. Catch description exceptions without altering original calls.
template<typename Renderer>
static void logValues(const std::shared_ptr<Trace> &trace, const Call &call, const char *kind, Renderer render) {
    const bool previous = inLogger;
    inLogger = true;
    @try {
        @autoreleasepool {
            NSString *values = render();
            NSLog(@"[MonkeyDevTrace] %s depth=%u call=%llu thread=%llu %c[%@ %@] %@", kind, call.level,
                (unsigned long long)call.identifier, (unsigned long long)call.thread, trace->classMethod ? '+' : '-', trace->name, trace->selectorName, values);
        }
    } @catch (__unused NSException *exception) {
        // Logging must not change the original method's result or exception.
    } @finally { inLogger = previous; }
}

static void logEvent(const std::shared_ptr<Trace> &trace, id target, const Call &call, const char *event, double ms) {
    const bool previous = inLogger;
    inLogger = true;
    @try {
        @autoreleasepool {
            NSLog(@"[MonkeyDevTrace] %s depth=%u call=%llu thread=%llu %c[%@ %@] target=%p elapsed_ms=%.3f",
                event, call.level, (unsigned long long)call.identifier, (unsigned long long)call.thread, trace->classMethod ? '+' : '-', trace->name, trace->selectorName, (__bridge void *)target, ms);
        }
    } @catch (__unused NSException *exception) {
        // Instrumentation logging must not replace the method's own exception.
    } @finally { inLogger = previous; }
}
static Call enter(const std::shared_ptr<Trace> &trace, id target) {
    trace->calls.fetch_add(1, std::memory_order_relaxed);
    if (!enabled.load(std::memory_order_relaxed) || inLogger || depth >= 32) return {false, 0, 0, 0, 0};
    if (trace->attempts.fetch_add(1, std::memory_order_relaxed) >= sampleLimit) return {false, 0, 0, 0, 0};
    uint64_t thread = 0;
    pthread_threadid_np(nullptr, &thread);
    Call call{true, depth++, 0, nextCallID.fetch_add(1, std::memory_order_relaxed), thread};
    trace->before.fetch_add(1, std::memory_order_relaxed);
    logEvent(trace, target, call, "before", 0);
    return call;
}
static void leave(const std::shared_ptr<Trace> &trace, id target, const Call &call, bool returned, uint64_t end) {
    if (!call.active) return;
    if (!end) end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    const double ms = (end - call.start) / 1000000.0;
    --depth;
    trace->after.fetch_add(1, std::memory_order_relaxed);
    if (!returned) trace->thrown.fetch_add(1, std::memory_order_relaxed);
    logEvent(trace, target, call, returned ? "after" : "after-throw", ms);
}

template<typename R, typename... Args>
static IMP makeWrapper(std::shared_ptr<Trace> trace) {
    R (^block)(id, Args...) = ^R(id target, Args... args) {
        using Function = R (*)(id, SEL, Args...);
        Function original = reinterpret_cast<Function>(trace->original);
        Call call = enter(trace, target);
        if (!call.active) return original(target, trace->selector, args...);
        logValues(trace, call, "args", [&]() -> NSString * {
            NSMutableArray *values = [NSMutableArray array];
            __unused unsigned index = 0;
            ([values addObject:[NSString stringWithFormat:@"arg%u=%@", ++index, formatValue(args)]], ...);
            return values.count ? [values componentsJoinedByString:@" | "] : @"(none)";
        });
        bool returned = false;
        uint64_t end = 0;
        call.start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        @try {
            if constexpr (std::is_void<R>::value) {
                original(target, trace->selector, args...);
                end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
                returned = true;
                logValues(trace, call, "return", []() -> NSString * { return @"void"; });
                return;
            } else {
                R result = original(target, trace->selector, args...);
                end = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
                returned = true;
                logValues(trace, call, "return", [&]() -> NSString * { return formatValue(result); });
                return result;
            }
        } @finally { leave(trace, target, call, returned, end); }
    };
    return imp_implementationWithBlock(block);
}

// An explicit supported-signature table, never cast an unknown ABI to a wrapper.
static std::string typeCode(char *raw) {
    if (!raw) return {};
    const char *type = raw;
    while (*type && strchr("rnNoORV", *type)) ++type;
    std::string result = (*type == '@') ? "@" : std::string(type);
    free(raw);
    return result;
}
template<typename R>
static IMP chooseArguments(const std::shared_ptr<Trace> &trace, const std::vector<std::string> &args) {
    if (args.empty()) return makeWrapper<R>(trace);
    if (args.size() == 2 && args[0] == "@" && args[1] == "@") return makeWrapper<R, id, id>(trace);
    if (args.size() != 1) return nullptr;
    const std::string &arg = args[0];
    if (arg == "@") return makeWrapper<R, id>(trace);
    if (arg == "B") return makeWrapper<R, bool>(trace);
    if (arg == "c") return makeWrapper<R, signed char>(trace);
    if (arg == "i") return makeWrapper<R, int32_t>(trace);
    if (arg == "I") return makeWrapper<R, uint32_t>(trace);
    if (arg == "q") return makeWrapper<R, int64_t>(trace);
    if (arg == "Q") return makeWrapper<R, uint64_t>(trace);
    if (arg == "f") return makeWrapper<R, float>(trace);
    if (arg == "d") return makeWrapper<R, double>(trace);
    return nullptr;
}
static IMP chooseSignature(const std::shared_ptr<Trace> &trace, Method method) {
    unsigned count = method_getNumberOfArguments(method);
    if (count < 2 || count > 4) return nullptr;
    std::vector<std::string> args;
    for (unsigned i = 2; i < count; ++i) args.push_back(typeCode(method_copyArgumentType(method, i)));
    const std::string result = typeCode(method_copyReturnType(method));
    if (result == "v") return chooseArguments<void>(trace, args);
    if (result == "@") return chooseArguments<id>(trace, args);
    if (result == "B") return chooseArguments<bool>(trace, args);
    if (result == "c") return chooseArguments<signed char>(trace, args);
    if (result == "i") return chooseArguments<int32_t>(trace, args);
    if (result == "I") return chooseArguments<uint32_t>(trace, args);
    if (result == "q") return chooseArguments<int64_t>(trace, args);
    if (result == "Q") return chooseArguments<uint64_t>(trace, args);
    if (result == "f") return chooseArguments<float>(trace, args);
    if (result == "d") return chooseArguments<double>(trace, args);
    return nullptr;
}
static bool forbidden(NSString *selector) {
    // Avoid retain/create method-family and forwarding/runtime-management ABIs.
    NSString *name = selector;
    while ([name hasPrefix:@"_"]) name = [name substringFromIndex:1];
    for (NSString *family in @[@"alloc", @"new", @"copy", @"mutableCopy", @"init"]) {
        if ([name hasPrefix:family] && (name.length == family.length ||
            ![[NSCharacterSet lowercaseLetterCharacterSet] characterIsMember:[name characterAtIndex:family.length]])) return true;
    }
    return [@[@"retain", @"release", @"autorelease", @"dealloc", @".cxx_destruct", @"class", @"load", @"initialize",
        @"retainCount", @"retainWeakReference", @"allowsWeakReference", @"respondsToSelector:",
        @"forwardingTargetForSelector:", @"methodSignatureForSelector:", @"forwardInvocation:",
        @"resolveInstanceMethod:", @"resolveClassMethod:"] containsObject:selector];
}
}

#define MD_TRACE_EXPORT __attribute__((used, noinline, visibility("default")))
MD_TRACE_EXPORT NSString *md_trace_start(const char *className, const char *selectorName, BOOL classMethod) {
    if (!className || !*className || !selectorName || !*selectorName) return @"Trace rejected: class and selector are required.";
    NSString *name = [NSString stringWithUTF8String:className];
    NSString *selectorText = [NSString stringWithUTF8String:selectorName];
    if (!name || !selectorText) return @"Trace rejected: invalid UTF-8.";
    Class cls = objc_lookUpClass(className);
    if (!cls) return [NSString stringWithFormat:@"Trace rejected: class not found: %@", name];
    if (cls == NSObject.class || cls == NSProxy.class || forbidden(selectorText)) return @"Trace rejected: runtime/lifecycle method or root class.";
    Class destination = classMethod ? object_getClass(cls) : cls;
    SEL selector = sel_registerName(selectorName);
    Method method = class_getInstanceMethod(destination, selector);
    if (!method) return @"Trace rejected: method not found.";
    std::lock_guard<std::mutex> lock(registryMutex());
    for (const auto &entry : registry()) {
        if (entry->destination == destination && entry->selector == selector) {
            enabled.store(true, std::memory_order_relaxed);
            return @"Trace already installed; logging enabled (existing sample budget retained).";
        }
    }
    if (registry().size() >= hookLimit) return @"Trace rejected: 128-method limit reached.";
    auto trace = std::make_shared<Trace>();
    trace->name = name; trace->selectorName = selectorText;
    trace->destination = destination; trace->selector = selector; trace->classMethod = classMethod;
    trace->original = method_getImplementation(method);
    IMP replacement = chooseSignature(trace, method);
    if (!replacement) return [NSString stringWithFormat:@"Trace rejected: unsupported signature %s", method_getTypeEncoding(method)];
    // Reserve ownership before touching the runtime. Registration must happen at
    // startup or while paused, not concurrently with another library's swizzling.
    registry().push_back(trace);
    if (!class_addMethod(destination, selector, replacement, method_getTypeEncoding(method))) {
        class_replaceMethod(destination, selector, replacement, method_getTypeEncoding(method));
    }
    enabled.store(true, std::memory_order_relaxed);
    return [NSString stringWithFormat:@"Trace installed: %c[%@ %@] (first %u calls)", classMethod ? '+' : '-', name, selectorText, sampleLimit];
}
MD_TRACE_EXPORT void md_trace_stop(void) { enabled.store(false, std::memory_order_relaxed); }
MD_TRACE_EXPORT void md_trace_set_descriptions(BOOL value) { descriptions.store(value, std::memory_order_relaxed); }
MD_TRACE_EXPORT NSString *md_trace_status(void) {
    std::vector<std::shared_ptr<Trace>> snapshot;
    {
        std::lock_guard<std::mutex> lock(registryMutex());
        snapshot = registry();
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (const auto &trace : snapshot) {
        [entries addObject:@{@"class": trace->name, @"selector": trace->selectorName, @"classMethod": @(trace->classMethod),
            @"calls": @(trace->calls.load()), @"limitReached": @(trace->attempts.load() >= sampleLimit), @"before": @(trace->before.load()), @"after": @(trace->after.load()), @"thrown": @(trace->thrown.load())}];
    }
    NSDictionary *status = @{@"enabled": @(enabled.load()), @"descriptions": @(descriptions.load()), @"sampleLimit": @(sampleLimit), @"methods": entries};
    NSData *data = [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:NULL];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
#endif // DEBUG
