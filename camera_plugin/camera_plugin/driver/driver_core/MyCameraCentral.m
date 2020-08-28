/*
 macam - webcam app and QuickTime driver component
 Copyright (C) 2002 Matthias Krauss (macam@matthias-krauss.de)

 This program is free software; you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation; either version 2 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 $Id: MyCameraCentral.m,v 1.90 2010/10/29 19:58:44 hxr Exp $
 */

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include "MiscTools.h"

#import "MyCameraInfo.h"
#import "MyCameraCentral.h"
#import "MyCameraDriver.h"
#import "OV534Driver.h"

#include <unistd.h>


void DeviceAdded(void *refCon, io_iterator_t iterator);

static NSString* driverBundleName=@"net.sourceforge.webcam-osx.common";
static NSMutableDictionary* prefsDict=NULL;
MyCameraCentral* sharedCameraCentral=NULL;


@interface MyCameraCentral (Private)

//Internal preferences handling. We cannot use NSUserDefaults here because we might be in someone else's bundle (in a lib)
- (id) prefsForKey:(NSString*) key;
- (void) setPrefs:(id)prefs forKey:(NSString*)key;
- (void) registerCameraDriver:(Class)driver;
- (CameraError) locationIdOfUSBDeviceRef:(io_service_t)usbDeviceRef to:(UInt32*)outVal version:(UInt16*)bcdDevice;

- (NSString *) cameraDisabledKeyFromVendorID:(UInt16)vid andProductID:(UInt16)pid;
- (NSString *) cameraDisabledKeyFromDriver:(MyCameraDriver *)camera;

- (void) listAllCameras;
- (void) listAllDuplicates;
- (void) listAllMultiDriver;

@end
    

@implementation MyCameraCentral


//MyCameraCentral is a singleton. Use this function to get the shared instance
+ (MyCameraCentral*) sharedCameraCentral {
    if (!sharedCameraCentral) sharedCameraCentral=[[MyCameraCentral alloc] init];
    return sharedCameraCentral;
}

//See if someone has requested MyCameraCentral before
+ (BOOL) isCameraCentralExisting {
    return (sharedCameraCentral!=NULL)?YES:NO;
}


//Localization for driver-specific stuff. As a component, the standard stuff won't work...

+ (NSString*) localizedStringFor:(NSString*) str {
    NSBundle* bundle=[NSBundle bundleForClass:[self class]];
    NSString* ret=[bundle localizedStringForKey:str value:@"" table:@"DriverLocalizable"];
    return ret;
}

+ (void) localizedCStrFor:(char*)cKey into:(char*)cValue {
    NSString* string;
    const char* tmpCStr;
    if (!cValue) return;
    if (!cKey) return;
    string=[NSString stringWithCString:cKey];
    string=[self localizedStringFor:string];
    tmpCStr=[string lossyCString];
    CStr2CStr(tmpCStr,cValue);	//Note: No bounds check! Don't write dramas...
}

- (char*) localizedCStrForError:(CameraError)err {
    char* cstr;
    switch (err) {
        case CameraErrorOK:
        case CameraErrorBusy:
        case CameraErrorNoPower:
        case CameraErrorNoCam:
        case CameraErrorNoMem:
        case CameraErrorNoBandwidth:
        case CameraErrorTimeout:
        case CameraErrorUSBProblem:
        case CameraErrorInternal:
            cstr=localizedErrorCStrs[err];
            break;
        default:
            cstr=localizedUnknownErrorCStr;
            break;
    }
    return cstr;
}
    

//Init, startup, shutdown, dealloc

- (id) init 
{
    self = [super init];
    cameraTypes=[[NSMutableArray alloc] initWithCapacity:10];
    cameras=[[NSMutableArray alloc] initWithCapacity:10];
    delegate=NULL;
    inVDIG = NO;
    
    if (Gestalt(gestaltSystemVersion, &osVersion) != noErr)
        osVersion = 0x1047;  // Assume recent OS version

    // Cache localized error codes
    
    [[self class] localizedCStrFor:"CameraErrorOK" into:localizedErrorCStrs[CameraErrorOK]];
    [[self class] localizedCStrFor:"CameraErrorBusy" into:localizedErrorCStrs[CameraErrorBusy]];
    [[self class] localizedCStrFor:"CameraErrorNoPower" into:localizedErrorCStrs[CameraErrorNoPower]];
    [[self class] localizedCStrFor:"CameraErrorNoCam" into:localizedErrorCStrs[CameraErrorNoCam]];
    [[self class] localizedCStrFor:"CameraErrorNoMem" into:localizedErrorCStrs[CameraErrorNoMem]];
    [[self class] localizedCStrFor:"CameraErrorNoBandwidth" into:localizedErrorCStrs[CameraErrorNoBandwidth]];
    [[self class] localizedCStrFor:"CameraErrorTimeout" into:localizedErrorCStrs[CameraErrorTimeout]];
    [[self class] localizedCStrFor:"CameraErrorUSBProblem" into:localizedErrorCStrs[CameraErrorUSBProblem]];
    [[self class] localizedCStrFor:"CameraErrorUnimplemented" into:localizedErrorCStrs[CameraErrorUnimplemented]];
    [[self class] localizedCStrFor:"CameraErrorInternal" into:localizedErrorCStrs[CameraErrorInternal]];
    [[self class] localizedCStrFor:"CameraErrorDecoding" into:localizedErrorCStrs[CameraErrorDecoding]];
    [[self class] localizedCStrFor:"CameraErrorUSBNeedsUSB2" into:localizedErrorCStrs[CameraErrorUSBNeedsUSB2]];
    [[self class] localizedCStrFor:"UnknownError" into:localizedUnknownErrorCStr];
    
    return self;
}

- (void) dealloc 
{
    [self shutdown];	//Make sure everything's shut down
}

- (void) listAllCameras
{
    int             i;
    MyCameraInfo *  info = NULL;
    
    printf("\n");
    printf("List of all Cameras:\n");
    printf("==========\n");
    
    for (i = 0; i < [cameraTypes count]; i++) 
    {
        info = [cameraTypes objectAtIndex:i];
        
        printf("%03lu, 0x%04X, 0x%04X, %s, %s\n", [info cid], (unsigned) [info vendorID], (unsigned) [info productID], [NSStringFromClass([info driverClass]) cString], [[info cameraName] cString]);
    }
    
    printf("========== ==========\n");
}

- (void) listAllDuplicates
{
    int             i, j;
    BOOL            first;
    MyCameraInfo *  info = NULL;
    
    printf("\n");
    printf("List of all Duplicates (VID, PID, Driver):\n");
    
    for (i = 0; i < [cameraTypes count]; i++) 
    {
        SInt32          usbVendor;
        SInt32          usbProduct;
        NSString *      driverName;
        
        first = YES;
        info = [cameraTypes objectAtIndex:i];
        
        usbVendor = [info vendorID];
        usbProduct = [info productID];
        driverName = NSStringFromClass([info driverClass]);
        
        for (j = 0; j < [cameraTypes count]; j++) 
        {
            MyCameraInfo * other = [cameraTypes objectAtIndex:j];
            
            if (usbVendor != [other vendorID]) 
                continue;
            
            if (usbProduct != [other productID]) 
                continue;
            
            if (![driverName isEqualToString:NSStringFromClass([other driverClass])]) 
                continue;
            
            if (j == i) 
                continue;
            
            if (j < i) 
                break;
            
            if (first) 
            {
                first = NO;
                printf("==========\n");
                printf("%03lu, 0x%04X, 0x%04X, %s, %s\n", [info cid], (unsigned) [info vendorID], (unsigned) [info productID], [NSStringFromClass([info driverClass]) cString], [[info cameraName] cString]);
            }
            printf("%03lu, 0x%04X, 0x%04X, %s, %s\n", [other cid], (unsigned) [other vendorID], (unsigned) [other productID], [NSStringFromClass([other driverClass]) cString], [[other cameraName] cString]);
        }
    }
    
    printf("========== ==========\n");
}

- (void) listAllMultiDriver
{
    int             i, j;
    BOOL            first;
    MyCameraInfo *  info = NULL;
    
    printf("\n");
    printf("List of cameras with Multiple Drivers (VID, PID):\n");
    
    for (i = 0; i < [cameraTypes count]; i++) 
    {
        SInt32          usbVendor;
        SInt32          usbProduct;
        
        first = YES;
        info = [cameraTypes objectAtIndex:i];
        
        usbVendor = [info vendorID];
        usbProduct = [info productID];
        
        for (j = 0; j < [cameraTypes count]; j++) 
        {
            MyCameraInfo * other = [cameraTypes objectAtIndex:j];
            
            if (usbVendor != [other vendorID]) 
                continue;
            
            if (usbProduct != [other productID]) 
                continue;
            
            if (j == i) 
                continue;
            
            if (j < i) 
                break;
            
            if (first) 
            {
                first = NO;
                printf("==========\n");
                printf("%03lu, 0x%04X, 0x%04X, %s, %s\n", [info cid], (unsigned) [info vendorID], (unsigned) [info productID], [NSStringFromClass([info driverClass]) cString], [[info cameraName] cString]);
            }
            printf("%03lu, 0x%04X, 0x%04X, %s, %s\n", [other cid], (unsigned) [other vendorID], (unsigned) [other productID], [NSStringFromClass([other driverClass]) cString], [[other cameraName] cString]);
        }
    }
    
    printf("========== ==========\n");
}

- (BOOL) startupWithNotificationsOnMainThread:(BOOL)nomt recognizeLaterPlugins:(BOOL)rlp{
    MyCameraInfo* 		info=NULL;
    long 			i;
    mach_port_t 		masterPort;
    CFMutableDictionaryRef 	matchingDict;
    CFRunLoopSourceRef		runLoopSource;
    CFNumberRef			numberRef;
    kern_return_t		ret;
    SInt32              usbVendor;
    SInt32              usbProduct;
    io_iterator_t		iterator;
    
    assert(cameraTypes);
    assert(cameras);

    doNotificationsOnMainThread=nomt;
    recognizeLaterPlugins=rlp;
    
    // Add Driver classes (this is where we have to add new model classes!)
    
    //[self registerCameraDriver:[OV534Driver class]];
    [self registerCameraDriver:[OV538Driver class]];
    
    
#if 0
    [self listAllCameras];
    [self listAllDuplicates];
    [self listAllMultiDriver];
#endif
    
    //Get the IOKit master port (needed for communication with IOKit)
    ret = IOMasterPort(MACH_PORT_NULL, &masterPort);
    if (ret||(!masterPort)) { NSLog(@"MyCameraCentral: IOMasterPort failed (%08x)", ret); return NO;}

    //Get a notification port, get its event source and connect it to the current thread
    notifyPort = IONotificationPortCreate(masterPort);
    runLoopSource = IONotificationPortGetRunLoopSource(notifyPort);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);

    //Go through all our drivers and add plug-in notifications for them
    for (i=0;i<[cameraTypes count];i++) {

        //Get info about the current camera
        info=[cameraTypes objectAtIndex:i];
        if (info==NULL) { NSLog(@"MyCameraCentral:wiringThread: bad info"); return NO; }
        usbVendor =[info vendorID];
        usbProduct=[info productID];

        // Set up the matching criteria for the devices we're interested in
        matchingDict = IOServiceMatching(kIOUSBDeviceClassName);
        if (!matchingDict) { NSLog(@"MyCameraCentral:IOServiceMatching failed"); return NO; }

        // Add our vendor and product IDs to the matching criteria
        numberRef = CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&usbVendor);
        CFDictionarySetValue(matchingDict,CFSTR(kUSBVendorID),numberRef);
        CFRelease(numberRef); numberRef=NULL;

        numberRef = CFNumberCreate(kCFAllocatorDefault,kCFNumberSInt32Type,&usbProduct);
        CFDictionarySetValue(matchingDict,CFSTR(kUSBProductID),numberRef);
        CFRelease(numberRef); numberRef=NULL;

        if (recognizeLaterPlugins) {
            //Request notification if matching devices are plugged in or...
            ret = IOServiceAddMatchingNotification(notifyPort,
                                                   kIOFirstMatchNotification,
                                                   matchingDict,
                                                   DeviceAdded,
                                                   (__bridge void*)info,
                                                   &iterator);
        } else {
            //... just get the currently connected devices
            ret = IOServiceGetMatchingServices(masterPort,
                                               matchingDict,
                                               &iterator);
            
        }
        if (ret==0) {
            //Get first devices and trigger notification process
            DeviceAdded((__bridge void*)info, iterator);

            //If we don't later notifications, we can release the enumerator
            if (!recognizeLaterPlugins) {
                IOObjectRelease(iterator);
            }
        }
    }
    
    return YES;
}

- (void) shutdown {
    MyCameraInfo* info;

    //shutdown all cameras
    while ([cameras count]>0) {
        info=[cameras lastObject];
        [cameras removeLastObject];
        //disconnect from the driver and autorelease our retain
        if ([info driver]!=NULL) {
            [[info driver] setCentral:NULL];
            [[info driver] shutdown];
        }
    }
    //This would be a great place to release all USB notifications *****

    //release cameryTypes cameraInfos
    while ([cameraTypes count]>0) {
        info=[cameraTypes lastObject];
        [cameraTypes removeLastObject];
    }
}

- (id) delegate {
    return delegate;
}

- (void) setDelegate:(id)d {
    delegate=d;
}

- (BOOL) doNotificationsOnMainThread {
    return doNotificationsOnMainThread;
}

- (void) setVDIG:(BOOL)v
{
    inVDIG = v;
}

- (SInt32) osVersion
{
    return osVersion;
}

- (short) numCameras {
    return [cameras count];
}

- (short) indexOfCamera:(MyCameraDriver*)driver {
    short i=0;
    while (i<[cameras count]) {
        if ([[cameras objectAtIndex:i] driver]==driver) return i;
        else i++;
    }
    return -1;
}

- (short) indexOfDriverClass:(Class)driverClass 
{
    short i=0;
    while (i<[cameras count]) 
    {
        if ([[cameras objectAtIndex:i] driverClass] == driverClass) 
            return i;
        else i++;
    }
    return -1;
}

- (unsigned long) idOfCameraWithIndex:(short)idx {
    if ((idx<0)||(idx>=[self numCameras])) return 0;
    return [[cameras objectAtIndex:idx] cid];
}

- (UInt16) versionOfCameraWithIndex:(short)idx 
{
    if ((idx < 0) || (idx >= [self numCameras])) 
        return 0;
    
    return [[cameras objectAtIndex:idx] versionNumber];
}

- (unsigned long) idOfCameraWithLocationID:(UInt32)locID {
    short i;
    for (i=0;i<[cameras count];i++) {
        if ([[cameras objectAtIndex:i] locationID]==locID) return [[cameras objectAtIndex:i] cid];
    }
    return 0;    
}

- (CameraError) useCameraWithID:(unsigned long)cid to:(MyCameraDriver**)outCam acceptDummy:(BOOL)acceptDummy {
    long l;
    MyCameraInfo* dev=NULL;
    MyCameraDriver* cam=NULL;
    CameraError err=CameraErrorOK;
    if (outCam) *outCam=NULL;
    for (l=0;(l<[cameras count])&&(dev==NULL);l++) {
        dev=[cameras objectAtIndex:l];
        if ([dev cid]!=cid) dev=NULL;
    }
    if (dev==NULL) {
#ifdef VERBOSE
        NSLog(@"MyCameraCentral: cid not found");
#endif
        err=CameraErrorInternal;
    }
    if (!err) {
        if ([dev driver]) err=CameraErrorBusy;
    }
    if (!err) {
        cam=[[[dev driverClass] alloc] initWithCentral:self];
        if (!cam) {
#ifdef VERBOSE
            NSLog(@"MyCameraCentral: could not instantiate driver");
#endif
            err=CameraErrorNoMem;
        }
    }
    if (!err) {
        [cam setDelegate:delegate];
        [cam setCameraInfo:dev];
        err=[cam startupWithUsbLocationId:[dev locationID]];
        if (err!=CameraErrorOK) {
            cam=NULL;
        }
    }
    if (err&&acceptDummy) {	//We have an error and the sender wants a dummy in case of an error
        cam=[self useDummyForError:err];
    }
    if (cam!=NULL) {
        [dev setDriver:cam];
//        [cam setCameraInfo:dev];
//        [self setCameraToDefaults:cam];
        if (outCam) *outCam=cam;
    }
    return err;
}

- (NSString *) nameForID:(unsigned long) cid 
{
    long l;
    
    for (l = 0; l < [cameras count]; l++) 
        if ([[cameras objectAtIndex:l] cid] == cid) 
        {
 			NSString * name = [[cameras objectAtIndex:l] cameraName]; // get camera name
 			int  i, counter = 1;
 			NSString * modifiedName = nil;
            
 			for (i = 0; i < [cameras count]; i++)  // look again over all cameras
            {
 				NSString * findName = [[cameras objectAtIndex:i] cameraName];
				if( [findName isEqualToString:name]) // Are there any cameras with the same name?
 				{
 					if (i == l) 
                        modifiedName = [NSString stringWithFormat: @"%@ #%d", name, counter];  // We found our own camera again 
                    
 					counter++;  // Number of cameras with the same name (plus one)
 				}
 			}
            
            return (counter > 2) ? modifiedName : name;  // Modify name if more then one camera
        } 
    
    return NULL;
}

- (NSString *) nameForDriver:(MyCameraDriver*) driver 
{
    long l;
    
    for (l = 0; l < [cameras count]; l++) 
        if ([[cameras objectAtIndex:l] driver] == driver) 
            return [[cameras objectAtIndex:l] cameraName];
    
    return NULL;
}

- (BOOL) getName:(char*)name forID:(unsigned long)cid maxLength:(unsigned)maxLength
{
    NSString * camName = [self nameForID:cid];
    
    if (!camName) 
        return NO;
    
    [camName getCString:name maxLength:maxLength];
    
    return YES;
}

- (BOOL) getRegistrationName:(char*)name forID:(unsigned long)cid maxLength:(unsigned)maxLength
{
    long l;
    NSString * camName = nil;
    
    for (l = 0; l < [cameras count]; l++) 
        if ([[cameras objectAtIndex:l] cid] == cid) 
        {
 			NSString * name = [[cameras objectAtIndex:l] cameraName];
            camName = [NSString stringWithFormat: @"%@ #%lu", name, cid];
 			// This is not so user friendly but name is not be changed after other cameras unplugging etc.
        }
    
    if (!camName) 
        return NO;
    
    [camName getCString:name maxLength:maxLength];
    
    return YES;
}


void DeviceRemoved( void *refCon,io_service_t service,natural_t messageType,void *messageArgument ) {
    MyCameraInfo* dev=(__bridge MyCameraInfo*)refCon;
    if (messageType!=kIOMessageServiceIsTerminated) return;
    if (dev==NULL) {
#ifdef VERBOSE
        NSLog(@"MaCameraCentral:DeviceRemoved: bad refCon");
#endif
    } else {
        if ([dev driver]) [[dev driver] stopUsingUSB];	//Pass the info to the driver as fast as possible
        [[dev central] deviceRemoved:[dev cid]];
    }
}
    
- (void) deviceRemoved:(unsigned long)cid {
    kern_return_t	ret;
    long l;
    MyCameraInfo* dev=NULL;

    //remove the device in the cameras list
    for (l=0;l<[cameras count];l++) {
        if ([[cameras objectAtIndex:l] cid]==cid) {
            dev=[cameras objectAtIndex:l];
            [cameras removeObjectAtIndex:l];
        }
    }
    if (!dev) {
#ifdef VERBOSE
        NSLog(@"MyCameraInfo:deviceRemoved: Tried to unregister a device not registered");
#endif
        return;	//We didn't find the camera
    }
    //Release the usb stuff
    ret = IOObjectRelease([dev notification]);		//we don't need the usb notification any more
//Initiate the driver shutdown.
    if ([dev driver]!=NULL) {
        [[dev driver] shutdown];	//We don't release it here - it is done in the cameraHasShutDown notification
    }
}

void DeviceAdded(void *refCon, io_iterator_t iterator) {
    MyCameraInfo* info=(__bridge MyCameraInfo*)refCon;
    if (info!=NULL) {
        [[info central] deviceAdded:iterator info:info];
    }
}

- (void) deviceAdded:(io_iterator_t)iterator info:(MyCameraInfo*)type {
    kern_return_t	ret;
    io_service_t	usbDeviceRef;
    MyCameraInfo*	dev;
    io_object_t		notification;
    while ( (usbDeviceRef = IOIteratorNext(iterator)) ) {
        UInt32 locID;
        UInt16 versionNumber;
        
        //Setup our data object we use to track the device while it is plugged
        dev=[type copy];
        if (!dev) {
#ifdef VERBOSE
            NSLog(@"Could not copy MyCameraInfo object on insertion of a device");
#endif
            continue;
        }

        //Request notification if the device is unplugged
        ret = IOServiceAddInterestNotification(notifyPort,
                                               usbDeviceRef,
                                               kIOGeneralInterest,
                                               DeviceRemoved,
                                               (__bridge void*)dev,
                                               &notification);
        if (ret!=KERN_SUCCESS) {
#ifdef VERBOSE
            NSLog(@"IOServiceAddInterestNotification returned %08x\n",ret);
#endif
            continue;
        }
        //Try to find our USB location ID
        if ([self locationIdOfUSBDeviceRef:usbDeviceRef to:&locID version:&versionNumber]!=CameraErrorOK) {
#ifdef VERBOSE
            NSLog(@"failed to get location id");
#endif
            continue;
        }
        //Remember the notification (we have to release it later)
        [dev setNotification:notification];
        [dev setLocationID:locID];
        [dev setVersionNumber:versionNumber];

        //Put the new entry to the list of available cameras
        [cameras addObject:dev];

        //Spread the news that a camera was plugged in
        [self cameraDetected:[dev cid]];
    }
}

- (void) cameraDetected:(unsigned long) cid {
    if (delegate) {
        if ([delegate respondsToSelector:@selector(cameraDetected:)]) {
            [delegate cameraDetected:cid];
        }
    }
}

- (void) cameraHasShutDown:(id)sender {
    long i;
    MyCameraInfo* info;
    for(i=0;i<[cameras count];i++) {
        info=[cameras objectAtIndex:i];
        if ([info driver]==sender) {
            [info setDriver:NULL];	//If it's still in the list: mark it as available
        }
    }
}

- (void) registerCameraDriver:(Class)driver 
{
    NSArray * arr = [driver cameraUsbDescriptions];
    int i;
    
    for (i = 0; i < [arr count]; i++) 
    {
        NSDictionary * dict = [arr objectAtIndex:i];
        MyCameraInfo * info = [[MyCameraInfo alloc] init];
        
        if (info != NULL) 
        {
            [info setCameraName:[dict objectForKey:@"name"]];
            [info setVendorID:[[dict objectForKey:@"idVendor"] unsignedShortValue]];
            [info setProductID:[[dict objectForKey:@"idProduct"] unsignedShortValue]];
            [info setDriverClass:driver];
            [info setCentral: self];
            [cameraTypes addObject:info];
        }
    }
}

- (CameraError) locationIdOfUSBDeviceRef:(io_service_t)usbDeviceRef to:(UInt32*)outVal version:(UInt16*)bcdDevice
{
    UInt32 locID=0;
    UInt16 version = 0;
    kern_return_t kernelErr;
    SInt32 score;
    IOCFPlugInInterface **plugin=NULL;
    CameraError err=CameraErrorOK;
    HRESULT res;
    IOUSBDeviceInterface** dev=NULL;

    kernelErr = IOCreatePlugInInterfaceForService(usbDeviceRef, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score);

    if ((kernelErr!=kIOReturnSuccess)||(!plugin)) {
#ifdef VERBOSE
        NSLog(@"MyCameraCentral: IOCreatePlugInInterfaceForService; Could not get plugin");
#endif
        return CameraErrorUSBProblem;
    }
    if (!err) {
        res=(*plugin)->QueryInterface(plugin,CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID),(LPVOID*)(&dev));
        (*plugin)->Release(plugin);
        plugin=NULL;
        if ((res)||(!dev)) {
#ifdef VERBOSE
            NSLog(@"MyCameraCentral: IOCreatePlugInInterfaceForService; Could not get device interface");
#endif
            err=CameraErrorUSBProblem;
        }
    }
    if (!err) {
        kernelErr = (*dev)->GetLocationID(dev,&locID);
        if (kernelErr!=KERN_SUCCESS) 
        {
#ifdef VERBOSE
            NSLog(@"MyCameraCentral: IOCreatePlugInInterfaceForService; Could not get Location ID");
#endif
            err=CameraErrorUSBProblem;
        }
        kernelErr = (*dev)->GetDeviceReleaseNumber(dev, &version);
        if (kernelErr!=KERN_SUCCESS) 
        {
#ifdef VERBOSE
            NSLog(@"MyCameraCentral: IOCreatePlugInInterfaceForService; Could not get Release Number");
#endif
            err=CameraErrorUSBProblem;
        }
        (*dev)->Release(dev);
    }
    if (outVal) 
    {
        if (!err) 
            *outVal=locID;
        else 
            *outVal=0;
    }
    if (bcdDevice) 
    {
        if (!err) 
            *bcdDevice=version;
        else 
            *bcdDevice=0;
    }
    return err;
}


@end
