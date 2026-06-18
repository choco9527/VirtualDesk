#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNumber;
@property (nonatomic) uint32_t serialNum;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) id terminationHandler;
- (void)setDisplayInfoValue:(id)value forKey:(id)key;
@end

@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (uint32_t)displayID;
@end

static CGVirtualDisplayDescriptor *baseDescriptor(void) {
    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    descriptor.name = @"VirtualDesk Virtual Display";
    descriptor.maxPixelsWide = 1440;
    descriptor.maxPixelsHigh = 900;
    descriptor.vendorID = 0x4442;
    descriptor.productID = 0x0001;
    descriptor.serialNumber = 0x00000001;
    descriptor.sizeInMillimeters = CGSizeMake(344, 194);
    return descriptor;
}

static void tryDescriptor(NSString *label, void (^configure)(CGVirtualDisplayDescriptor *descriptor)) {
    CGVirtualDisplayDescriptor *descriptor = baseDescriptor();
    if (configure != nil) {
        configure(descriptor);
    }

    CGVirtualDisplay *display = [[CGVirtualDisplay alloc] initWithDescriptor:descriptor];
    printf("%s => %s\n", label.UTF8String, display != nil ? "OK" : "NIL");
    if (display != nil) {
        printf("displayID=%u\n", [display displayID]);
    }
}

int main(void) {
    @autoreleasepool {
        tryDescriptor(@"base", nil);
        tryDescriptor(@"with_queue", ^(CGVirtualDisplayDescriptor *descriptor) {
            descriptor.queue = dispatch_get_main_queue();
        });
        tryDescriptor(@"with_queue_handler", ^(CGVirtualDisplayDescriptor *descriptor) {
            descriptor.queue = dispatch_get_main_queue();
            descriptor.terminationHandler = ^{};
        });
        tryDescriptor(@"with_queue_colors", ^(CGVirtualDisplayDescriptor *descriptor) {
            descriptor.queue = dispatch_get_main_queue();
            descriptor.redPrimary = CGPointMake(0.64, 0.33);
            descriptor.greenPrimary = CGPointMake(0.30, 0.60);
            descriptor.bluePrimary = CGPointMake(0.15, 0.06);
            descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        });
        tryDescriptor(@"with_queue_colors_handler", ^(CGVirtualDisplayDescriptor *descriptor) {
            descriptor.queue = dispatch_get_main_queue();
            descriptor.terminationHandler = ^{};
            descriptor.redPrimary = CGPointMake(0.64, 0.33);
            descriptor.greenPrimary = CGPointMake(0.30, 0.60);
            descriptor.bluePrimary = CGPointMake(0.15, 0.06);
            descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        });
        tryDescriptor(@"with_serial_num_alias", ^(CGVirtualDisplayDescriptor *descriptor) {
            descriptor.queue = dispatch_get_main_queue();
            descriptor.serialNum = 1;
        });
        tryDescriptor(@"with_virtual_max_pixels_keys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(1440) forKey:@"VirtualDisplayMaxPixelsWide"];
            [descriptor setDisplayInfoValue:@(900) forKey:@"VirtualDisplayMaxPixelsHigh"];
        });
        tryDescriptor(@"with_virtual_size_keys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(344) forKey:@"VirtualDisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"VirtualDisplayVerticalImageSize"];
        });
        tryDescriptor(@"with_display_size_keys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(344) forKey:@"DisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"DisplayVerticalImageSize"];
        });
        tryDescriptor(@"with_virtual_max_and_size_keys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(1440) forKey:@"VirtualDisplayMaxPixelsWide"];
            [descriptor setDisplayInfoValue:@(900) forKey:@"VirtualDisplayMaxPixelsHigh"];
            [descriptor setDisplayInfoValue:@(344) forKey:@"VirtualDisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"VirtualDisplayVerticalImageSize"];
        });
        tryDescriptor(@"with_all_size_keys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(1440) forKey:@"VirtualDisplayMaxPixelsWide"];
            [descriptor setDisplayInfoValue:@(900) forKey:@"VirtualDisplayMaxPixelsHigh"];
            [descriptor setDisplayInfoValue:@(344) forKey:@"VirtualDisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"VirtualDisplayVerticalImageSize"];
            [descriptor setDisplayInfoValue:@(344) forKey:@"DisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"DisplayVerticalImageSize"];
        });
    }
    return 0;
}
