#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

typedef struct {
    uint32_t width;
    uint32_t height;
} SLSize2D;

@interface SLVirtualDisplayMode : NSObject
- (instancetype)initWithSizeInPixels:(SLSize2D)sizeInPixels
                        sizeInPoints:(SLSize2D)sizeInPoints
                         refreshRate:(float)refreshRate
                               error:(NSError **)error;
- (NSDictionary *)dictionaryRepresentation;
@end

static void tryMode(uint32_t pixelWidth, uint32_t pixelHeight, uint32_t pointWidth, uint32_t pointHeight, float refreshRate) {
    NSError *error = nil;
    SLVirtualDisplayMode *mode =
        [[NSClassFromString(@"SLVirtualDisplayMode") alloc]
            initWithSizeInPixels:(SLSize2D){ .width = pixelWidth, .height = pixelHeight }
                  sizeInPoints:(SLSize2D){ .width = pointWidth, .height = pointHeight }
                   refreshRate:refreshRate
                         error:&error];

    if (mode == nil) {
        printf(
            "mode %ux%u points %ux%u @ %.1f => ERROR: %s",
            pixelWidth,
            pixelHeight,
            pointWidth,
            pointHeight,
            refreshRate,
            error.localizedDescription.UTF8String
        );
        if (error.localizedFailureReason != nil) {
            printf(" | reason: %s", error.localizedFailureReason.UTF8String);
        }
        printf("\n");
        return;
    }

    NSLog(@"mode %ux%u points %ux%u @ %.1f => %@", pixelWidth, pixelHeight, pointWidth, pointHeight, refreshRate, [mode dictionaryRepresentation]);
}

int main(void) {
    @autoreleasepool {
        if (NSClassFromString(@"SLVirtualDisplayMode") == nil) {
            printf("SLVirtualDisplayMode unavailable.\n");
            return 1;
        }

        tryMode(1440, 900, 1440, 900, 60.0f);
        tryMode(1440, 900, 720, 450, 60.0f);
        tryMode(1280, 800, 1280, 800, 60.0f);
        tryMode(1280, 800, 640, 400, 60.0f);
        tryMode(1920, 1080, 1920, 1080, 60.0f);
        tryMode(1920, 1080, 960, 540, 60.0f);
    }
    return 0;
}
