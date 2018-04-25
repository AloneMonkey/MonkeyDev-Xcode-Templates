//  weibo: http://weibo.com/xiaoqing28
//  blog:  http://www.alonemonkey.com
//
//  CycriptManager.m
//  MonkeyDev
//
//  Created by AloneMonkey on 2018/3/8.
//  Copyright © 2018年 AloneMonkey. All rights reserved.
//

#import "CycriptManager.h"
#import "MDConfigManager.h"
#include <ifaddrs.h>
#include <arpa/inet.h>
#include <net/if.h>

#define IOS_CELLULAR    @"pdp_ip0"
#define IOS_WIFI        @"en0"
#define IP_ADDR_IPv4    @"ipv4"
#define IP_ADDR_IPv6    @"ipv6"
#define MDLog(fmt, ...) NSLog((@"[Cycript] " fmt), ##__VA_ARGS__)

@implementation CycriptManager{
    NSDictionary *_configItem;
    NSString* _cycriptDirectory;
}

+ (instancetype)sharedInstance{
    static CycriptManager *sharedInstance = nil;
    if (!sharedInstance){
        sharedInstance = [[CycriptManager alloc] init];
    }
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self check];
        [self createCycriptDirectory];
        [self readConfigFile];
    }
    return self;
}

-(void)check{
    NSString* ip = [self getIPAddress];
    if(ip != nil){
        printf("\nDownload cycript(https://cydia.saurik.com/api/latest/3) then run: ./cycript -r %s:%d\n\n", [ip UTF8String], PORT);
    }else{
        printf("\nPlease connect wifi before using cycript!\n\n");
    }
}

-(void)createCycriptDirectory{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath =[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
    _cycriptDirectory = [documentsPath stringByAppendingPathComponent:@"cycript"];
    [fileManager createDirectoryAtPath:_cycriptDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

-(void)readConfigFile{
    MDConfigManager * configManager = [MDConfigManager sharedInstance];
    _configItem = [configManager readConfigByKey:MDCONFIG_CYCRIPT_KEY];
}

-(void)startDownloadCycript:(BOOL) update{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(_configItem && _configItem.count > 0){
        for (NSString* filename in _configItem.allKeys) {
            NSString *fullPath = [[_cycriptDirectory stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"cy"];
            
            if(![fileManager fileExistsAtPath:fullPath] || update){
                [self downLoadUrl:_configItem[filename] saveName:filename];
            }
        }
    }
}

-(void)downLoadUrl:(NSString*) urlString saveName:(NSString*) filename{
    NSURLSession *session = [NSURLSession sharedSession];
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithURL:url completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        
        if(error){
            MDLog(@"Failed download script [%@]: %@", filename, error.localizedDescription);
        }else{
            NSString *fullPath = [[_cycriptDirectory stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"cy"];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:fullPath] error:nil];
            
            MDLog(@"Successful download script [%@]", filename);
        }
    }];
    [downloadTask resume];
}

- (NSString *)getIPAddress{
    
    NSDictionary *addresses = [self getIPAddresses];
    
    if([addresses.allKeys containsObject:IOS_WIFI @"/" IP_ADDR_IPv4]){
        return addresses[IOS_WIFI @"/" IP_ADDR_IPv4];
    }
    
    return nil;
}

- (NSDictionary *)getIPAddresses{
    NSMutableDictionary *addresses = [NSMutableDictionary dictionaryWithCapacity:8];
    
    // retrieve the current interfaces - returns 0 on success
    struct ifaddrs *interfaces;
    if(!getifaddrs(&interfaces)) {
        // Loop through linked list of interfaces
        struct ifaddrs *interface;
        for(interface=interfaces; interface; interface=interface->ifa_next) {
            if(!(interface->ifa_flags & IFF_UP) /* || (interface->ifa_flags & IFF_LOOPBACK) */ ) {
                continue; // deeply nested code harder to read
            }
            const struct sockaddr_in *addr = (const struct sockaddr_in*)interface->ifa_addr;
            char addrBuf[ MAX(INET_ADDRSTRLEN, INET6_ADDRSTRLEN) ];
            if(addr && (addr->sin_family==AF_INET || addr->sin_family==AF_INET6)) {
                NSString *name = [NSString stringWithUTF8String:interface->ifa_name];
                NSString *type;
                if(addr->sin_family == AF_INET) {
                    if(inet_ntop(AF_INET, &addr->sin_addr, addrBuf, INET_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv4;
                    }
                } else {
                    const struct sockaddr_in6 *addr6 = (const struct sockaddr_in6*)interface->ifa_addr;
                    if(inet_ntop(AF_INET6, &addr6->sin6_addr, addrBuf, INET6_ADDRSTRLEN)) {
                        type = IP_ADDR_IPv6;
                    }
                }
                if(type) {
                    NSString *key = [NSString stringWithFormat:@"%@/%@", name, type];
                    addresses[key] = [NSString stringWithUTF8String:addrBuf];
                }
            }
        }
        // Free memory
        freeifaddrs(interfaces);
    }
    return [addresses count] ? addresses : nil;
}

@end
