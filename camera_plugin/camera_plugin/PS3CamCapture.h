//
//  PS3CameraCapture.h
//  camera_plugin
//
//  Created by Andrii on 23.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//

#ifndef PS3CamCapture_h
#define PS3CamCapture_h
#include <cap_interface.hpp>
#include <opencv2/opencv.hpp>

@class MyCameraDriver;
@class DriverProxy;

namespace camera { namespace plugin {

class PS3CamCapture: public cv::IVideoCapture
{
public:
    PS3CamCapture(MyCameraDriver *drv);
    virtual ~PS3CamCapture();
    virtual bool grabFrame();
    virtual bool retrieveFrame(int /*unused*/, cv::OutputArray dest);
    virtual bool isOpened() const;

public:
    bool init( );
    
private:
    bool isGrabbing;
    MyCameraDriver *drv;
    DriverProxy *proxyDrv;
};

} /*camer*/ };

#endif /* PS3CameraCapture_h */
