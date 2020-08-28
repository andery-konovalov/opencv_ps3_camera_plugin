//
//  CamManager.m
//  CamTest
//
//  Created by Andrii on 14.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//

#import "CameraManager.h"

#include "MyCameraDriver.h"
#include "MyCameraCentral.h"

@interface DriverContext: NSObject
@property MyCameraDriver *driver;
@property (nonatomic) BOOL busy;
@end

@implementation DriverContext

-(instancetype) initWithDriver:(MyCameraDriver *)drv
{
    self = [super init];
    if (self)
    {
        self.driver = drv;
        self.busy = NO;
    }
    return self;
}
@end

@interface CameraManager ()
{
    MyCameraCentral *cameraCentral;
    NSMutableDictionary *connectedCameras;
    uint8_t cameraPointer;
    NSLock *lock;
}
@end

@implementation CameraManager

-(instancetype) init
{
    self = [super init];
    if ( self )
    {
        cameraCentral = [MyCameraCentral new];
        cameraCentral.delegate = self;
        connectedCameras = [NSMutableDictionary new];
        cameraPointer = 0;
        lock = [NSLock new];
    }
    return self;
}

- (void) startup
{
    [cameraCentral startupWithNotificationsOnMainThread:NO recognizeLaterPlugins:YES];
}

-(MyCameraDriver *) getDriverByIndex:(uint8_t)cameraIndex
{
    [lock lock];
    MyCameraDriver *drv = nil;
    DriverContext *ctx = [connectedCameras objectForKey:[NSNumber numberWithUnsignedChar:cameraIndex]];
    if ( ctx != nil && !ctx.busy)
    {
        drv = ctx.driver;
        ctx.busy = YES;
    }
    [lock unlock];
    return drv;
}

- (void) destroyAll;
{
    
}

- (void)cameraDetected:(unsigned long)cid {
    CameraError err;

    MyCameraDriver* drv = NULL;
    err=[cameraCentral useCameraWithID:cid to:&drv acceptDummy:NO];
    if ( err )
    {
        NSLog(@"Camera with id=%lu was not found", cid);
            switch (err) {
                case CameraErrorBusy:
                    NSLog(@"Status: Camera used by another app");
                    break;
                case CameraErrorNoPower:
                    NSLog(@"Status: Not enough USB bus power");
                    break;
                case CameraErrorNoCam:
                    NSLog(@"Status: Camera not found (this shouldn't happen)");
                    break;
                case CameraErrorNoMem:
                    NSLog(@"Status: Out of memory");
                    break;
                case CameraErrorUSBProblem:
                    NSLog(@"Status: USB communication problem");
                    break;
                case CameraErrorInternal:
                    NSLog(@"Status: Internal error (this shouldn't happen)");
                    break;
                case CameraErrorUnimplemented:
                    NSLog(@"Status: Unsupported");
                    break;
                default:
                    NSLog(@"Status: Unknown error (this shouldn't happen)");
                    break;
        }
    }
    else
    {
        [lock lock];
        DriverContext *ctx = [[DriverContext alloc] initWithDriver:drv];
        [connectedCameras setObject:ctx forKey:[NSNumber numberWithUnsignedChar:cameraPointer]];
        cameraPointer ++;
        [lock unlock];
    }
}

- (void) disconnect:(uint8_t)cameraIndex
{
    [lock lock];
    DriverContext *ctx = [connectedCameras objectForKey:[NSNumber numberWithUnsignedChar:cameraIndex]];
    if ( ctx != nil )
    {
        ctx.busy = NO;
        [ctx.driver stopGrabbing];
        [connectedCameras removeObjectForKey:[NSNumber numberWithUnsignedLong:cameraIndex]];
    }
    [lock unlock];
}

@end
