//
//  LocalVideoInfo.m
//  KncAngel
//
//  Created by zhao qi on 15/8/29.
//  Copyright (c) 2015年 ouyang. All rights reserved.
//

#import "LocalVideoInfo.h"

@implementation LocalVideoInfo



//- (id)initWithID:(NSString*)path Time:(NSInteger)time {
//    self = [super init];
//    
//    if (self) {
//        self.path = path;
//        self.time = time;
//    }
//    
//    return self;
//}

- (id)initWithRecordingName:(NSString *)name time:(NSInteger)time type:(NSInteger)type {
    if (self = [super init]) {
        
        self.path = name;
        self.time = time;
        self.type = type;
    }
    return self;
}



@end
