#include "fishhook.h"
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <unistd.h>

static pid_t (*original_getpid)(void);
static int hook_calls;
static pid_t replacement_getpid(void) {
    ++hook_calls;
    return original_getpid() + 1000;
}

static int run_check(void) {
    pid_t expected = getpid();
    Dl_info info;
    if (!dladdr((void *)&run_check, &info)) return 2;
    const struct mach_header *header = NULL;
    intptr_t slide = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); ++i) {
        if ((void *)_dyld_get_image_header(i) == info.dli_fbase) {
            header = _dyld_get_image_header(i);
            slide = _dyld_get_image_vmaddr_slide(i);
            break;
        }
    }
    if (!header) return 3;
    struct rebinding binding = {"getpid", (void *)&replacement_getpid, (void **)&original_getpid};
    if (rebind_symbols_image((void *)header, slide, &binding, 1)) return 4;
    pid_t result = getpid();
    if (!original_getpid || hook_calls != 1 || result != expected + 1000 || original_getpid() != expected) {
        fprintf(stderr, "[MonkeyDevFishhook] FAIL: calls=%d, result=%d, expected=%d\n", hook_calls, result, expected + 1000);
        return 5;
    }
    fprintf(stderr, "[MonkeyDevFishhook] PASS: imported getpid rebound; original function preserved\n");
    return 0;
}
#ifdef MD_FISHHOOK_DYLIB
__attribute__((constructor)) static void fishhook_check_entry(void) { run_check(); }
#else
int main(void) { return run_check(); }
#endif
