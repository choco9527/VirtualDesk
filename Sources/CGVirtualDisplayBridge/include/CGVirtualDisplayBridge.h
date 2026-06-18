#ifndef CGVirtualDisplayBridge_h
#define CGVirtualDisplayBridge_h

#include <stddef.h>
#include <stdint.h>

typedef void *DBVirtualDisplayRef;

DBVirtualDisplayRef DBVirtualDisplayCreate(
    const char *name,
    uint32_t width,
    uint32_t height,
    double refreshRate,
    char *errorBuffer,
    size_t errorBufferLength
);

uint32_t DBVirtualDisplayGetDisplayID(DBVirtualDisplayRef display);

void DBVirtualDisplayRelease(DBVirtualDisplayRef display);

#endif
