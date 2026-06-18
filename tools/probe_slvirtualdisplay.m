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
- (instancetype)initWithName:(NSString *)name
                    vendorID:(uint64_t)vendorID
                   productID:(uint64_t)productID
                serialNumber:(uint64_t)serialNumber
           sizeInMillimeters:(SLSizeInMillimeters)sizeInMillimeters
         maximumSizeInPixels:(SLMaximumSizeInPixels)maximumSizeInPixels
              chromaticities:(SLChromaticities)chromaticities
                       error:(NSError **)error;
@end

static SLChromaticities defaultChromaticities(void) {
    SLChromaticities chromaticities;
    chromaticities.redPrimary = (SLChromaticityPoint){ .x = 0.64f, .y = 0.33f };
    chromaticities.greenPrimary = (SLChromaticityPoint){ .x = 0.30f, .y = 0.60f };
    chromaticities.bluePrimary = (SLChromaticityPoint){ .x = 0.15f, .y = 0.06f };
    chromaticities.whitePoint = (SLChromaticityPoint){ .x = 0.3127f, .y = 0.3290f };
    return chromaticities;
}

int main(void) {
    @autoreleasepool {
        Class configurationClass = objc_getClass("SLVirtualDisplayConfiguration");
        if (configurationClass == Nil) {
            printf("SLVirtualDisplay runtime classes unavailable.\n");
            return 10;
        }

        const SLMaximumSizeInPixels candidates[] = {
            { .width = 640, .height = 480 },
            { .width = 800, .height = 600 },
            { .width = 1024, .height = 768 },
            { .width = 1280, .height = 720 },
            { .width = 1280, .height = 800 },
            { .width = 1280, .height = 900 },
            { .width = 1440, .height = 900 },
            { .width = 1600, .height = 900 },
            { .width = 1728, .height = 1117 },
            { .width = 1920, .height = 1080 },
            { .width = 2048, .height = 1280 },
        };

        const size_t count = sizeof(candidates) / sizeof(candidates[0]);
        for (size_t index = 0; index < count; index++) {
            SLMaximumSizeInPixels pixels = candidates[index];
            id configurationInstance = [configurationClass alloc];
            NSError *configurationError = nil;
            id configuration =
                [(SLVirtualDisplayConfiguration *)configurationInstance
                    initWithName:@"VirtualDesk Virtual Display"
                        vendorID:0x4442
                       productID:0x0001
                    serialNumber:0x00000001 + (uint64_t)index
               sizeInMillimeters:(SLSizeInMillimeters){ .width = 344.0f, .height = 194.0f }
             maximumSizeInPixels:pixels
                  chromaticities:defaultChromaticities()
                           error:&configurationError];

            if (configuration == nil) {
                printf(
                    "%ux%u => CONFIG ERROR: %s",
                    pixels.width,
                    pixels.height,
                    configurationError.localizedDescription.UTF8String
                );
                if (configurationError.localizedFailureReason != nil) {
                    printf(" | reason: %s", configurationError.localizedFailureReason.UTF8String);
                }
                printf("\n");
            } else {
                printf("%ux%u => CONFIG OK\n", pixels.width, pixels.height);
            }
        }
    }
    return 0;
}
