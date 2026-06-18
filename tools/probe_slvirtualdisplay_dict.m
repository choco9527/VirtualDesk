#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef struct {
    float width;
    float height;
} SLSizeInMillimeters;

typedef struct {
    uint32_t width;
    uint32_t height;
} SLMaximumSizeInPixels;

typedef struct {
    float x;
    float y;
} SLChromaticityPoint;

typedef struct {
    SLChromaticityPoint redPrimary;
    SLChromaticityPoint greenPrimary;
    SLChromaticityPoint bluePrimary;
    SLChromaticityPoint whitePoint;
} SLChromaticities;

@interface SLVirtualDisplayConfiguration : NSObject
+ (instancetype)configurationWithBackendOptions:(NSDictionary *)backendOptions;
+ (instancetype)configurationWithDictionaryRepresentation:(NSDictionary *)dictionaryRepresentation;
+ (instancetype)configurationWithDisplayInfo:(NSDictionary *)displayInfo;
- (instancetype)initWithName:(NSString *)name
                    vendorID:(uint64_t)vendorID
                   productID:(uint64_t)productID
                serialNumber:(uint64_t)serialNumber
           sizeInMillimeters:(SLSizeInMillimeters)sizeInMillimeters
         maximumSizeInPixels:(SLMaximumSizeInPixels)maximumSizeInPixels
              chromaticities:(SLChromaticities)chromaticities
                       error:(NSError **)error;
- (NSDictionary *)dictionaryRepresentation;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t maxPixelsWide;
@property (nonatomic) uint32_t maxPixelsHigh;
@property (nonatomic) uint32_t vendorID;
@property (nonatomic) uint32_t productID;
@property (nonatomic) uint32_t serialNumber;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) CGPoint redPrimary;
@property (nonatomic) CGPoint greenPrimary;
@property (nonatomic) CGPoint bluePrimary;
@property (nonatomic) CGPoint whitePoint;
@property (nonatomic, readonly) NSDictionary *displayInfo;
- (void)setDisplayInfoValue:(id)value forKey:(id)key;
@end

static SLChromaticities defaultChromaticities(void) {
    SLChromaticities chromaticities;
    chromaticities.redPrimary = (SLChromaticityPoint){ .x = 0.64f, .y = 0.33f };
    chromaticities.greenPrimary = (SLChromaticityPoint){ .x = 0.30f, .y = 0.60f };
    chromaticities.bluePrimary = (SLChromaticityPoint){ .x = 0.15f, .y = 0.06f };
    chromaticities.whitePoint = (SLChromaticityPoint){ .x = 0.3127f, .y = 0.3290f };
    return chromaticities;
}

static CGVirtualDisplayDescriptor *makeDescriptor(void) {
    CGVirtualDisplayDescriptor *descriptor = [[CGVirtualDisplayDescriptor alloc] init];
    descriptor.name = @"VirtualDesk Virtual Display";
    descriptor.maxPixelsWide = 1440;
    descriptor.maxPixelsHigh = 900;
    descriptor.vendorID = 0x4442;
    descriptor.productID = 0x0001;
    descriptor.serialNumber = 1;
    descriptor.sizeInMillimeters = CGSizeMake(344, 194);
    descriptor.redPrimary = CGPointMake(0.64, 0.33);
    descriptor.greenPrimary = CGPointMake(0.30, 0.60);
    descriptor.bluePrimary = CGPointMake(0.15, 0.06);
    descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
    return descriptor;
}

static void tryDisplayInfoConfig(
    Class configurationClass,
    NSString *label,
    void (^mutate)(CGVirtualDisplayDescriptor *descriptor)
) {
    CGVirtualDisplayDescriptor *descriptor = makeDescriptor();
    if (mutate != nil) {
        mutate(descriptor);
    }

    NSDictionary *displayInfo = descriptor.displayInfo;
    id configuration = [configurationClass configurationWithDisplayInfo:displayInfo];
    NSLog(@"%@: %@", label, configuration);
    if ([configuration respondsToSelector:@selector(dictionaryRepresentation)]) {
        NSLog(@"%@ dictionary=%@", label, [configuration dictionaryRepresentation]);
    }
}

int main(void) {
    @autoreleasepool {
        Class configurationClass = objc_getClass("SLVirtualDisplayConfiguration");
        if (configurationClass == Nil) {
            printf("SLVirtualDisplayConfiguration unavailable.\n");
            return 1;
        }

        NSError *error = nil;
        SLVirtualDisplayConfiguration *configuration =
            [[configurationClass alloc]
                initWithName:@"VirtualDesk Virtual Display"
                    vendorID:0x4442
                   productID:0x0001
                serialNumber:1
           sizeInMillimeters:(SLSizeInMillimeters){ .width = 344.0f, .height = 194.0f }
         maximumSizeInPixels:(SLMaximumSizeInPixels){ .width = 1440, .height = 900 }
              chromaticities:defaultChromaticities()
                       error:&error];

        if (configuration != nil) {
            NSLog(@"dictionaryRepresentation=%@", [configuration dictionaryRepresentation]);
        } else {
            NSLog(@"init error=%@ reason=%@", error.localizedDescription, error.localizedFailureReason);
        }

        NSDictionary *candidateDictionary = @{
            @"SLVirtualDisplayName": @"VirtualDesk Virtual Display",
            @"SLVirtualDisplayVendorID": @0x4442,
            @"SLVirtualDisplayProductID": @0x0001,
            @"SLVirtualDisplaySerialNumber": @1,
            @"SLVirtualDisplaySizeInMillimeters": @{@"width": @344.0f, @"height": @194.0f},
            @"SLVirtualDisplayMaximumSizeInPixels": @{@"width": @1440, @"height": @900},
        };
        id fromDictionary = [configurationClass configurationWithDictionaryRepresentation:candidateDictionary];
        NSLog(@"fromDictionary=%@", fromDictionary);

        NSDictionary *backendOptions = @{
            @"com.apple.windowserver.virtualDisplayWidth": @1440,
            @"com.apple.windowserver.virtualDisplayHeight": @900,
            @"com.apple.windowserver.virtualDisplayResolution": @60,
            @"SidecarDeviceTypeIdentifier": @"Generic Virtual Display",
        };
        id fromBackendOptions = [configurationClass configurationWithBackendOptions:backendOptions];
        NSLog(@"fromBackendOptions=%@", fromBackendOptions);
        if ([fromBackendOptions respondsToSelector:@selector(dictionaryRepresentation)]) {
            NSLog(@"fromBackendOptions.dictionaryRepresentation=%@", [fromBackendOptions dictionaryRepresentation]);
        }

        tryDisplayInfoConfig(configurationClass, @"baseDisplayInfo", nil);
        tryDisplayInfoConfig(configurationClass, @"withVirtualMaxPixels", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(1440) forKey:@"VirtualDisplayMaxPixelsWide"];
            [descriptor setDisplayInfoValue:@(900) forKey:@"VirtualDisplayMaxPixelsHigh"];
        });
        tryDisplayInfoConfig(configurationClass, @"withDisplaySize", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(344) forKey:@"DisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"DisplayVerticalImageSize"];
        });
        tryDisplayInfoConfig(configurationClass, @"withVirtualImageSize", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(344) forKey:@"VirtualDisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"VirtualDisplayVerticalImageSize"];
        });
        tryDisplayInfoConfig(configurationClass, @"withAllDisplayInfoKeys", ^(CGVirtualDisplayDescriptor *descriptor) {
            [descriptor setDisplayInfoValue:@(344) forKey:@"DisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"DisplayVerticalImageSize"];
            [descriptor setDisplayInfoValue:@(1440) forKey:@"VirtualDisplayMaxPixelsWide"];
            [descriptor setDisplayInfoValue:@(900) forKey:@"VirtualDisplayMaxPixelsHigh"];
            [descriptor setDisplayInfoValue:@(344) forKey:@"VirtualDisplayHorizontalImageSize"];
            [descriptor setDisplayInfoValue:@(194) forKey:@"VirtualDisplayVerticalImageSize"];
        });
    }
    return 0;
}
