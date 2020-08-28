//
//  plugin_api.cpp
//  camera_plugin
//
//  Created by Andrii on 23.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//

#include <stddef.h>
#include <opencv2/core/llapi/llapi.h>
#include <plugin_api.hpp>

#include "PS3CamCapture.h"

#import "CameraManager.h"

static CameraManager *cameraManager;

__attribute__((constructor))
static void initialize_CameraManager() {
    
    cameraManager = [CameraManager new];
    [cameraManager startup];
}

__attribute__((destructor))
static void destroy_CameraManager() {
  
    [cameraManager destroyAll];
}

namespace camera { namespace plugin { namespace api {

using namespace cv;

static cv::Mat src_image1;
static
CvResult CV_API_CALL cv_capture_open(const char* filename, int camera_index, CV_OUT CvPluginCapture* handle)
{
    if (!handle)
        return CV_ERROR_FAIL;
    *handle = NULL;
    
    PS3CamCapture *cap = 0;
    MyCameraDriver *drv = [cameraManager getDriverByIndex: camera_index];
    if(!drv)
    {
        return CV_ERROR_FAIL;
    }
    try
    {
        src_image1 = cv::imread( "/Users/konovalov/work/projects/temp/opencv_test/Stone/RightPhone/20200207_202138.jpg", IMREAD_UNCHANGED );
        cap = new PS3CamCapture(drv);
        bool res;
        if (filename)
            return CV_ERROR_FAIL;
        else
            res = cap->init( );
        if (res)
        {
            *handle = (CvPluginCapture)cap;
            return CV_ERROR_OK;
        }
    }
    catch (...)
    {
    }
    if (cap)
        delete cap;
    return CV_ERROR_FAIL;
}

static
CvResult CV_API_CALL cv_capture_release(CvPluginCapture handle)
{
    if (!handle)
        return CV_ERROR_FAIL;
    PS3CamCapture* instance = (PS3CamCapture*)handle;
    delete instance;
    return CV_ERROR_OK;
}


static
CvResult CV_API_CALL cv_capture_get_prop(CvPluginCapture handle, int prop, CV_OUT double* val)
{
    if (!handle)
        return CV_ERROR_FAIL;
    if (!val)
        return CV_ERROR_FAIL;
    try
    {
        PS3CamCapture* instance = (PS3CamCapture*)handle;
        *val = instance->getProperty(prop);
        return CV_ERROR_OK;
    }
    catch (...)
    {
        return CV_ERROR_FAIL;
    }
}

static
CvResult CV_API_CALL cv_capture_set_prop(CvPluginCapture handle, int prop, double val)
{
    if (!handle)
        return CV_ERROR_FAIL;
    try
    {
        PS3CamCapture* instance = (PS3CamCapture*)handle;
        return instance->setProperty(prop, val) ? CV_ERROR_OK : CV_ERROR_FAIL;
    }
    catch(...)
    {
        return CV_ERROR_FAIL;
    }
}

static
CvResult CV_API_CALL cv_capture_grab(CvPluginCapture handle)
{
    if (!handle)
        return CV_ERROR_FAIL;
    try
    {
        PS3CamCapture* instance = (PS3CamCapture*)handle;
        instance->grabFrame();
        return CV_ERROR_OK;
    }
    catch(...)
    {
        return CV_ERROR_FAIL;
    }
}

static
CvResult CV_API_CALL cv_capture_retrieve(CvPluginCapture handle, int stream_idx, cv_videoio_retrieve_cb_t callback, void* userdata)
{
    if (!handle)
        return CV_ERROR_FAIL;
    try
    {
        PS3CamCapture* instance = (PS3CamCapture*)handle;
        Mat img;
        // TODO: avoid unnecessary copying - implement lower level GStreamerCapture::retrieve
        if (instance->retrieveFrame(stream_idx, img))
        {
            //img =src_image1;
            return callback(stream_idx, img.data, img.step, img.cols, img.rows, img.channels(), userdata);
        }
        return CV_ERROR_FAIL;
    }
    catch(...)
    {
        return CV_ERROR_FAIL;
    }
}

static
CvResult CV_API_CALL cv_writer_open(const char* filename, int fourcc, double fps, int width, int height, int isColor,
                                    CV_OUT CvPluginWriter* handle)
{
    return CV_ERROR_FAIL;
}

static
CvResult CV_API_CALL cv_writer_release(CvPluginWriter handle)
{
   return CV_ERROR_FAIL;
}

static
CvResult CV_API_CALL cv_writer_get_prop(CvPluginWriter /*handle*/, int /*prop*/, CV_OUT double* /*val*/)
{
    return CV_ERROR_FAIL;
}

static
CvResult CV_API_CALL cv_writer_set_prop(CvPluginWriter /*handle*/, int /*prop*/, double /*val*/)
{
    return CV_ERROR_FAIL;
}

static
CvResult CV_API_CALL cv_writer_write(CvPluginWriter handle, const unsigned char *data, int step, int width, int height, int cn)
{
    return CV_ERROR_FAIL;
}

static const OpenCV_VideoIO_Plugin_API_preview plugin_api_v0 =
{
    {
        sizeof(OpenCV_VideoIO_Plugin_API_preview), ABI_VERSION, API_VERSION,
        CV_VERSION_MAJOR, CV_VERSION_MINOR, CV_VERSION_REVISION, CV_VERSION_STATUS,
        "PS3 camera OpenCV Video I/O plugin"
    },
    /*  1*/CAP_MINE,
    /*  2*/cv_capture_open,
    /*  3*/cv_capture_release,
    /*  4*/cv_capture_get_prop,
    /*  5*/cv_capture_set_prop,
    /*  6*/cv_capture_grab,
    /*  7*/cv_capture_retrieve,
    /*  8*/cv_writer_open,
    /*  9*/cv_writer_release,
    /* 10*/cv_writer_get_prop,
    /* 11*/cv_writer_set_prop,
    /* 12*/cv_writer_write
};

} /*camera*/ } /*plugin*/ } /*api*/

#define EXPORT __attribute__((visibility("default")))

extern "C"
const OpenCV_VideoIO_Plugin_API_preview* opencv_videoio_plugin_init_v0(int requested_abi_version, int requested_api_version, void* /*reserved=NULL*/) CV_NOEXCEPT
{
    if (requested_abi_version != 0)
        return NULL;
    if (requested_api_version != 0)
        return NULL;
    if( !cameraManager )
    {
        cameraManager = [CameraManager new];
        [cameraManager startup];
    }
    return &camera::plugin::api::plugin_api_v0;
}
