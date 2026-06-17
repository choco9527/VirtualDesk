#import "CGVirtualDisplayBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNumber;
@property (nonatomic) CGSize sizeInMillimeters;
@end

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)width height:(uint32_t)height refreshRate:(double)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic, copy) NSArray *modes;
@property (nonatomic) uint32_t hiDPI;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
- (uint32_t)displayID;
@end

static void DBSetError(char *buffer, size_t length, NSString *message) {
    if (buffer == NULL || length == 0) {
        return;
    }

    const char *utf8 = message.UTF8String;
    if (utf8 == NULL) {
        utf8 = "Unknown error";
    }

    snprintf(buffer, length, "%s", utf8);
}

DBVirtualDisplayRef DBVirtualDisplayCreate(
    const char *name,
    uint32_t width,
    uint32_t height,
    double refreshRate,
    char *errorBuffer,
    size_t errorBufferLength
) {
    if (objc_getClass("CGVirtualDisplay") == Nil) {
        DBSetError(errorBuffer, errorBufferLength, @"CGVirtualDisplay runtime class is unavailable.");
        return NULL;
    }

    NSString *displayName = name == NULL
        ? @"VirtualDesk Virtual Display"
        : [NSString stringWithUTF8String:name];

    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    descriptor.name = displayName;
    descriptor.maxPixelsWide = width;
    descriptor.maxPixelsHigh = height;
    descriptor.vendorID = 0x4442;
    descriptor.productID = 0x0001;
    descriptor.serialNumber = 0x00000001;
    descriptor.sizeInMillimeters = CGSizeMake(344, 194);

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    if (display == nil) {
        DBSetError(errorBuffer, errorBufferLength, @"Failed to initialize CGVirtualDisplay.");
#if !__has_feature(objc_arc)
        [descriptor release];
#endif
        return NULL;
    }

    CGVirtualDisplayMode *mode = [[CGVirtualDisplayMode alloc] initWithWidth:width height:height refreshRate:refreshRate];
    CGVirtualDisplaySettings *settings = [[CGVirtualDisplaySettings alloc] init];
    settings.modes = @[mode];
    settings.hiDPI = 1;

    BOOL applied = [display applySettings:settings];
    if (!applied) {
        DBSetError(errorBuffer, errorBufferLength, @"Failed to apply CGVirtualDisplay settings.");
#if !__has_feature(objc_arc)
        [settings release];
        [mode release];
        [display release];
        [descriptor release];
#endif
        return NULL;
    }

#if !__has_feature(objc_arc)
    [settings release];
    [mode release];
    [descriptor release];
    return display;
#else
    return (__bridge_retained void *)display;
#endif
}

uint32_t DBVirtualDisplayGetDisplayID(DBVirtualDisplayRef display) {
    if (display == NULL) {
        return 0;
    }

    return [(__bridge CGVirtualDisplay *)display displayID];
}

void DBVirtualDisplayRelease(DBVirtualDisplayRef display) {
    if (display == NULL) {
        return;
    }

#if !__has_feature(objc_arc)
    [(id)display release];
#else
    CFRelease(display);
#endif
}
