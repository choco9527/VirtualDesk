#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface SLVirtualDisplayMode : NSObject
+ (instancetype)modeWithDictionaryRepresentation:(NSDictionary *)dictionaryRepresentation;
- (NSDictionary *)dictionaryRepresentation;
@end

static void tryDictionary(NSDictionary *dictionary, NSString *label) {
    id mode = [NSClassFromString(@"SLVirtualDisplayMode") modeWithDictionaryRepresentation:dictionary];
    NSLog(@"%@: %@", label, mode);
    if ([mode respondsToSelector:@selector(dictionaryRepresentation)]) {
        NSLog(@"%@ dictionary=%@", label, [mode dictionaryRepresentation]);
    }
}

int main(void) {
    @autoreleasepool {
        if (NSClassFromString(@"SLVirtualDisplayMode") == nil) {
            printf("SLVirtualDisplayMode unavailable.\n");
            return 1;
        }

        tryDictionary(@{
            @"SLVirtualDisplayModeSizeInPixels": @{@"width": @1440, @"height": @900},
            @"SLVirtualDisplayModeSizeInPoints": @{@"width": @1440, @"height": @900},
            @"SLVirtualDisplayModeRefreshRate": @60.0f,
        }, @"basicMode");

        tryDictionary(@{
            @"CDVirtualDisplayModeWidth": @1440,
            @"CDVirtualDisplayModeHeight": @900,
            @"CDVirtualDisplayModeRefreshRate": @60.0f,
        }, @"coreDisplayMode");

        tryDictionary(@{
            @"SLVirtualDisplayModeSizeInPixels": @{@"width": @1440, @"height": @900},
            @"SLVirtualDisplayModeSizeInPoints": @{@"width": @720, @"height": @450},
            @"SLVirtualDisplayModeRefreshRate": @60.0f,
            @"CDVirtualDisplayModeWidth": @1440,
            @"CDVirtualDisplayModeHeight": @900,
            @"CDVirtualDisplayModeRefreshRate": @60.0f,
        }, @"combinedMode");
    }
    return 0;
}
