//
//  main.cpp
//  plugin_test
//
//  Created by Andrii on 23.08.2020.
//  Copyright © 2020 MDSoft. All rights reserved.
//

#include <opencv2/core.hpp>
#include <opencv2/imgproc/imgproc.hpp>
#include <opencv2/videoio.hpp>
#include <opencv2/highgui.hpp>
#include <iostream>
#include <stdio.h>
#include <iostream>

using namespace cv;
using namespace std;

static inline bool convertAndShow(const char *wndName, const cv::Mat &rawData)
{
        if (rawData.empty()) {
            cerr << "ERROR! blank frame grabbed\n";
            return false;
        }
        Mat dst;
        cvtColor(rawData, dst,  COLOR_YUV2RGB_YVYU);
        imshow(wndName, dst);
    return true;
}

int main(int argc, const char * argv[]) {
    Mat frame1, frame2;
    //--- INITIALIZE VIDEOCAPTURE
    VideoCapture cap1;
    VideoCapture cap2;
    // open the default camera using default API
    // cap.open(0);
    // OR advance usage: select any API backend
    int deviceID = 0;             // 0 = open default camera
    int apiID = cv::CAP_MINE;      // 0 = autodetect default API
    // open selected camera using selected API
    bool is_alive1 = cap1.open(deviceID, apiID);
    bool is_alive2 = cap2.open(1, apiID);
    // check if we succeeded
    if ( !is_alive1 && !is_alive2 ) {
        cerr << "ERROR! Unable to open camera\n";
        return -1;
    }
    //--- GRAB AND WRITE LOOP
    cout << "Start grabbing" << endl
        << "Press any key to terminate" << endl;
    for (;;)
    {
        // wait for a new frame from camera and store it into 'frame'
        if( is_alive1 )
        {
            cap1.read(frame1);
            convertAndShow("Live1", frame1);
            
        }
        if( is_alive2 )
        {
            cap2.read(frame2);
            convertAndShow("Live2", frame2);
        }
        // check if we succeeded
        
        // show live and wait for a key with timeout long enough to show images
        
        
        if (waitKey(1000 / 25) >= 0)
            break;
    }
    // the camera will be deinitialized automatically in VideoCapture destructor
    return 0;
}
