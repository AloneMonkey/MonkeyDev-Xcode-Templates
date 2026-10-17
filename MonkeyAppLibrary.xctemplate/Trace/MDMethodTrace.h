// MonkeyDev's opt-in typed Objective-C method tracer. Debug / arm64 only.
#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
// Only non-variadic methods with supported type encodings may be registered.
// Class lookup is exact; YES selects a class method. No automatic registration.
FOUNDATION_EXPORT NSString *md_trace_start(const char *className, const char *selectorName, BOOL classMethod);
// Stop logging; installed wrappers stay in place to preserve other hook chains.
FOUNDATION_EXPORT void md_trace_stop(void);
// YES (default): bounded object descriptions. NO: class/address only.
FOUNDATION_EXPORT void md_trace_set_descriptions(BOOL enabled);
FOUNDATION_EXPORT NSString *md_trace_status(void);
#ifdef __cplusplus
}
#endif
