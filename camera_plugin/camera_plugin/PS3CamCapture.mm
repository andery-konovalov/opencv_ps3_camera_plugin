//
//  PS3CameraCapture.m
//  camera_plugin
//
//  Created by Andrii on 23.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//
#include "PS3CamCapture.h"
#include <opencv2/opencv.hpp>

#import <Foundation/Foundation.h>
#import "MyCameraDriver.h"

@interface DriverProxy: NSObject
{
    camera::plugin::PS3CamCapture *captureInterface;
    MyCameraDriver *driver;
    uint8_t *imageBuffer;
    uint32_t bufferSize;
    uint32_t height;
    uint32_t width;
    NSCondition *condition;
}
@property (atomic) BOOL bufferReady;
- (instancetype) initWithDriver:(MyCameraDriver*)drv captureClass:(camera::plugin::PS3CamCapture *)cam;
- (BOOL) retriveImage:(cv::OutputArray) dst;
- (void) startGrabbing;
@end

@implementation DriverProxy

-(instancetype)initWithDriver:(MyCameraDriver *)drv captureClass:(camera::plugin::PS3CamCapture *)cam
{
    self = [super init];
    if( self )
    {
        condition = [NSCondition new];
        driver = drv;
        captureInterface = cam;
        self.bufferReady = NO;
        bufferSize = 0;
        height = 0;
        width = 0;
        driver.delegate = self;
        [self setupCameraBuffer];
        [driver startGrabbing];
        
    }
    return self;
}

- (void) setupCameraBuffer
{
    height = [driver height];
    width = [driver width];
    bufferSize = width * height * 4 /* bytes per pixel */ * 3 /* samples per pixel*/;
    imageBuffer =(uint8_t *)calloc(1, bufferSize);

    assert(imageBuffer);

    [driver setImageBuffer:imageBuffer bpp:3 rowBytes:[driver width] * 4];
}

- (void) startGrabbing
{
    //[driver startGrabbing];
}

- (void) imageReady:(MyCameraDriver *)cam
{
    [condition lock];
    if(!self.bufferReady)
    {
        self.bufferReady = YES;
        [condition signal];
    }
    [condition unlock];
}

- (BOOL) retriveImage:(cv::OutputArray) dst
{
    [condition lock];
    while (!self.bufferReady)
    {
        [condition wait];
    }
    
    cv::Mat src;
//    src = cv::Mat(height, width, CV_8UC3, imageBuffer);
    src = cv::Mat(height, width, CV_8UC2, imageBuffer);
    CV_Assert(src.isContinuous());
    src.copyTo(dst);
    self.bufferReady = NO;
    [driver setImageBuffer:[driver imageBuffer]
                       bpp:[driver imageBufferBPP]
                  rowBytes:[driver imageBufferRowBytes]];
    [condition unlock];
    
    return YES;
}

- (void) cameraHasShutDown:(MyCameraDriver *)driver
{
}

@end


namespace camera { namespace plugin {

PS3CamCapture::PS3CamCapture(MyCameraDriver *drv)
    : isGrabbing(false)
    , drv(drv)
{
}

PS3CamCapture::~PS3CamCapture( )
{
    if( drv && isGrabbing )
    {
        [drv stopGrabbing];
        sleep(1);
    }
    proxyDrv = nil;
}

bool PS3CamCapture::init( )
{
    proxyDrv = [[DriverProxy alloc] initWithDriver:drv captureClass:this];
    return true;
}

bool PS3CamCapture::grabFrame()
{
    if (!isGrabbing)
    {
        [proxyDrv startGrabbing];
        isGrabbing = true;
    }
    return true;
}

bool PS3CamCapture::retrieveFrame(int /*unused*/, cv::OutputArray dest)
{
    return [proxyDrv retriveImage:dest];
}

bool PS3CamCapture::isOpened() const
{
    return false;
}

}};
