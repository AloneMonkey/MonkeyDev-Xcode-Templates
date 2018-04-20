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
        [self createCycriptDirectory];
        [self readConfigFile];
    }
    return self;
}

-(void)createCycriptDirectory{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *documentsPath =[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
    _cycriptDirectory = [documentsPath stringByAppendingPathComponent:@"cycript"];
    [fileManager createDirectoryAtPath:_cycriptDirectory withIntermediateDirectories:YES attributes:nil error:nil];
}

-(void)readConfigFile{
    NSString* configFilePath = [[NSBundle mainBundle] pathForResource:@"CycriptConfig" ofType:@"plist"];
    if(configFilePath == nil){
        NSLog(@"CycriptConfig.plsit is not exits!!!");
    }else{
       _configItem = [NSDictionary dictionaryWithContentsOfFile:configFilePath];
    }
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
            NSLog(@"failed download script [%@]: %@", filename, error.localizedDescription);
        }else{
            NSString *fullPath = [[_cycriptDirectory stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"cy"];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:fullPath] error:nil];
            
            NSLog(@"successful download script [%@]", filename);
        }
    }];
    [downloadTask resume];
}

@end
