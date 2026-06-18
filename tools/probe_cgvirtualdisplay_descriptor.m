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
@property (nonatomic, readonly) NSDictionary *displayInfo;
- (void)setDisplayInfoValue:(id)value forKey:(id)key;
@end

static CGVirtualDisplayDescriptor *makeDescriptor(void) {
    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    descriptor.name = @"VirtualDesk Virtual Display";
    descriptor.maxPixelsWide = 1440;
    descriptor.maxPixelsHigh = 900;
    descriptor.vendorID = 0x4442;
    descriptor.productID = 0x0001;
    descriptor.serialNumber = 0x00000001;
    descriptor.serialNum = 0x00000001;
    descriptor.sizeInMillimeters = CGSizeMake(344, 194);
    descriptor.redPrimary = CGPointMake(0.64, 0.33);
    descriptor.greenPrimary = CGPointMake(0.30, 0.60);
    descriptor.bluePrimary = CGPointMake(0.15, 0.06);
    descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
    descriptor.queue = dispatch_get_main_queue();
    descriptor.terminationHandler = ^{};
    return descriptor;
}

int main(void) {
    @autoreleasepool {
        CGVirtualDisplayDescriptor *descriptor = makeDescriptor();
        NSLog(@"displayInfo=%@", descriptor.displayInfo);
    }
    return 0;
}
