#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

typedef BOOL (*BoolMsgSend)(id, SEL, SEL);
int main(void) {
    @autoreleasepool {
        Class displayClass = objc_getClass("SLVirtualDisplay");
        if (displayClass == Nil) {
            printf("SLVirtualDisplay unavailable.\n");
            return 1;
        }

        SEL respondsSelector = sel_registerName("respondsToSelector:");
        SEL capabilitiesSelector = sel_registerName("capabilities");

        BOOL classResponds = ((BoolMsgSend)objc_msgSend)((id)displayClass, respondsSelector, capabilitiesSelector);
        printf("classResponds=%s\n", classResponds ? "YES" : "NO");

        id metaClassObject = object_getClass((id)displayClass);
        BOOL metaResponds = ((BoolMsgSend)objc_msgSend)((id)metaClassObject, respondsSelector, capabilitiesSelector);
        printf("metaResponds=%s\n", metaResponds ? "YES" : "NO");

        if ([metaClassObject respondsToSelector:capabilitiesSelector]) {
            printf("metaClassObject responds via NSObject path.\n");
        }

        if (classResponds) {
            id capabilities = ((id (*)(id, SEL))objc_msgSend)((id)displayClass, capabilitiesSelector);
            printf("capabilities=%s\n", capabilities == nil ? "nil" : "non-nil");
            if (capabilities != nil) {
                NSLog(@"capabilities=%@", capabilities);
                if ([capabilities respondsToSelector:@selector(dictionaryRepresentation)]) {
                    NSLog(@"capabilities.dictionary=%@", [capabilities performSelector:@selector(dictionaryRepresentation)]);
                }
            }
        }
    }
    return 0;
}
