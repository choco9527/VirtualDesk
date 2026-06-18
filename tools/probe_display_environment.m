#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

int main(void) {
    @autoreleasepool {
        uint32_t displayCount = 0;
        CGError error = CGGetOnlineDisplayList(0, NULL, &displayCount);
        printf("CGGetOnlineDisplayList error=%d count=%u\n", error, displayCount);

        if (displayCount > 0) {
            CGDirectDisplayID displays[32] = {0};
            uint32_t actualCount = 0;
            error = CGGetOnlineDisplayList(32, displays, &actualCount);
            printf("CGGetOnlineDisplayList fetch error=%d actualCount=%u\n", error, actualCount);
            for (uint32_t index = 0; index < actualCount; index++) {
                CGRect bounds = CGDisplayBounds(displays[index]);
                printf(
                    "display[%u] id=%u bounds=(%.0f,%.0f %.0fx%.0f)\n",
                    index,
                    displays[index],
                    bounds.origin.x,
                    bounds.origin.y,
                    bounds.size.width,
                    bounds.size.height
                );
            }
        }

        NSArray<NSScreen *> *screens = [NSScreen screens];
        printf("NSScreen count=%lu\n", (unsigned long)screens.count);
        for (NSUInteger index = 0; index < screens.count; index++) {
            NSScreen *screen = screens[index];
            NSDictionary *description = screen.deviceDescription;
            NSNumber *screenNumber = description[@"NSScreenNumber"];
            NSRect frame = screen.frame;
            printf(
                "screen[%lu] id=%u frame=(%.0f,%.0f %.0fx%.0f)\n",
                (unsigned long)index,
                screenNumber.unsignedIntValue,
                frame.origin.x,
                frame.origin.y,
                frame.size.width,
                frame.size.height
            );
        }
    }
    return 0;
}
