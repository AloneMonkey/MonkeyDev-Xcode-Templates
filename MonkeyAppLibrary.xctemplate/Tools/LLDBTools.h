// MonkeyDev debugger helpers. Invoke manually in Debug builds.
// Adapted from the original LLDBTools by AloneMonkey (2018).
#pragma once
#import <Foundation/Foundation.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
// UI helpers require the main thread. Addresses must refer to live objects.
FOUNDATION_EXPORT NSString *pvc(void);
FOUNDATION_EXPORT NSString *pviews(void);
FOUNDATION_EXPORT NSString *pactions(uintptr_t address);
// Runtime metadata only: these functions do not invoke inspected methods/getters.
FOUNDATION_EXPORT NSString *methods(const char *className);
FOUNDATION_EXPORT NSString *ivars(uintptr_t address);
// Preferred LLDB names: avoid collisions with system C++/Objective-C symbols.
FOUNDATION_EXPORT NSString *md_pvc(void);
FOUNDATION_EXPORT NSString *md_pviews(void);
FOUNDATION_EXPORT NSString *md_pactions(uintptr_t address);
FOUNDATION_EXPORT NSString *md_methods(const char *className);
FOUNDATION_EXPORT NSString *md_ivars(uintptr_t address);
// choose(), pblock() and vmmap() are not part of this migration.
#ifdef __cplusplus
}
#endif
