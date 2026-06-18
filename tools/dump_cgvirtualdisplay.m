#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static void dumpClass(const char *className) {
    Class cls = objc_getClass(className);
    if (cls == Nil) {
        printf("CLASS %s NOT FOUND\n", className);
        return;
    }

    printf("CLASS %s\n", className);

    unsigned int propertyCount = 0;
    objc_property_t *properties = class_copyPropertyList(cls, &propertyCount);
    for (unsigned int index = 0; index < propertyCount; index++) {
        const char *name = property_getName(properties[index]);
        const char *attributes = property_getAttributes(properties[index]);
        printf("PROPERTY %s ATTRS %s\n", name, attributes);
    }
    free(properties);

    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    for (unsigned int index = 0; index < methodCount; index++) {
        printf("METHOD %s\n", sel_getName(method_getName(methods[index])));
    }
    free(methods);

    Class metaClass = object_getClass((id)cls);
    unsigned int classMethodCount = 0;
    Method *classMethods = class_copyMethodList(metaClass, &classMethodCount);
    for (unsigned int index = 0; index < classMethodCount; index++) {
        printf("CLASS_METHOD %s\n", sel_getName(method_getName(classMethods[index])));
    }
    free(classMethods);
}

int main(void) {
    @autoreleasepool {
        dumpClass("CGVirtualDisplayDescriptor");
        dumpClass("CGVirtualDisplaySettings");
        dumpClass("CGVirtualDisplayMode");
        dumpClass("CGVirtualDisplay");
        dumpClass("SLVirtualDisplayConfiguration");
        dumpClass("SLVirtualDisplay");
        dumpClass("SLVirtualDisplayCapabilities");
        dumpClass("SLVirtualDisplayMode");
        dumpClass("SLVirtualDisplaySettings");
    }
    return 0;
}
