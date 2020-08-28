//
//  CamManager.h
//  CamTest
//
//  Created by Andrii on 14.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>



NS_ASSUME_NONNULL_BEGIN

@class MyCameraDriver;
@interface CameraManager : NSObject
-(instancetype)init;
-(MyCameraDriver *) getDriverByIndex:(uint8_t)cameraIndex;
-(void)startup;
-(void)destroyAll;
@end

NS_ASSUME_NONNULL_END
