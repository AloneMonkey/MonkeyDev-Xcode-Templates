//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  Created by AloneMonkey on 2016/12/10.
//  Copyright © 2017年 Coder. All rights reserved.
//

#import "fishhook.h"
#import <Foundation/Foundation.h>
#import <sys/sysctl.h>

typedef int (*ptrace_ptr_t)(int _request,pid_t _pid, caddr_t _addr,int _data);
typedef void* (*dlsym_ptr_t)(void * __handle, const char* __symbol);
typedef int (*syscall_ptr_t)(int, ...);
typedef int (*sysctl_ptr_t)(int *,u_int, void*, size_t*,void*, size_t);


static ptrace_ptr_t orig_ptrace = NULL;
static dlsym_ptr_t orig_dlsym = NULL;
static sysctl_ptr_t orig_sysctl = NULL;

#ifndef __LP64__
static syscall_ptr_t origin_syscall = NULL;
#endif

int my_ptrace(int _request, pid_t _pid, caddr_t _addr, int _data);
void* my_dlsym(void* __handle, const char* __symbol);
int my_sysctl(int * name, u_int namelen, void * info, size_t * infosize, void * newinfo, size_t newinfosize);

int my_ptrace(int _request, pid_t _pid, caddr_t _addr, int _data){
    if(_request != 31){
        return orig_ptrace(_request,_pid,_addr,_data);
    }
    
    NSLog(@"[AntiAntiDebug] - ptrace request is PT_DENY_ATTACH");
    
    return 0;
}

void* my_dlsym(void* __handle, const char* __symbol){
    if(strcmp(__symbol, "ptrace") != 0){
        return orig_dlsym(__handle, __symbol);
    }
    
    NSLog(@"[AntiAntiDebug] - dlsym get ptrace symbol");
    
    return my_ptrace;
}

typedef struct kinfo_proc _kinfo_proc;

int my_sysctl(int * name, u_int namelen, void * info, size_t * infosize, void * newinfo, size_t newinfosize){
    int ret = orig_sysctl(name, namelen, info, infosize, newinfo, newinfosize);
    if(namelen == 4 && name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID && info && infosize && (*infosize == sizeof(_kinfo_proc))){
        struct kinfo_proc *info_ptr = (struct kinfo_proc *)info;
        if(info_ptr && (info_ptr->kp_proc.p_flag & P_TRACED) != 0){
            NSLog(@"[AntiAntiDebug] - sysctl query trace status.");
            info_ptr->kp_proc.p_flag ^= P_TRACED;
            if((info_ptr->kp_proc.p_flag & P_TRACED) == 0){
                NSLog(@"trace status reomve success!");
            }
        }
    }
    return ret;
}

#ifndef __LP64__
void * my_syscall(long code, va_list args){
    int request;
    va_list newArgs;
    va_copy(newArgs, args);
    if(code == 26){
        request = (int)args;
        if(request == 31){
            NSLog(@"[AntiAntiDebug] - syscall call ptrace, and request is PT_DENY_ATTACH");
            return nil;
        }
    }
    return (void*)origin_syscall(code, newArgs);
}
#endif

__attribute__((constructor)) static void entry(){
    NSLog(@"[AntiAntiDebug Init]");
    
    rebind_symbols((struct rebinding[1]){{"ptrace", my_ptrace, (void*)&orig_ptrace}},1);
    
    rebind_symbols((struct rebinding[1]){{"dlsym", my_dlsym, (void*)&orig_dlsym}},1);
    
    //some app will crash with _dyld_debugger_notification
    //rebind_symbols((struct rebinding[1]){{"sysctl", my_sysctl, (void*)&orig_sysctl}},1);
    
#ifndef __LP64__
    rebind_symbols((struct rebinding[1]){{"syscall", my_syscall, (void*)&origin_syscall}},1);
#endif
}

