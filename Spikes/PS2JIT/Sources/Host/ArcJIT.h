#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Code-signing and debugger state of the current process.
typedef struct {
    /// Return value of csops(CS_OPS_STATUS); 0 means the flags are valid.
    int csopsResult;
    /// CS_* flags from <kern/cs_blobs.h>.
    uint32_t flags;
    /// CS_GET_TASK_ALLOW: the app was signed with get-task-allow.
    bool getTaskAllow;
    /// CS_DEBUGGED: a debugger is or was attached. The flag stays set after detaching.
    bool debugged;
    /// P_TRACED: a debugger is attached right now.
    bool traced;
} ArcJITProcessStatus;

ArcJITProcessStatus ArcJITReadProcessStatus(void);

/// Mirrors StikDebug's TXM heuristic (StikDebug/Support/ProcessInfo+TXM.swift):
/// from iOS 27 every device except iPad8,11 and iPad8,12 counts as TXM, on
/// iOS 26 iPhones from iPhone14,2 and iPads from iPad14,5.
bool ArcJITAssumesTXM(const char *hardwareIdentifier, int osMajorVersion);

/// One executable mapping and a writable alias of the same pages.
typedef struct {
    void *executable;
    void *writable;
    size_t size;
} ArcJITRegion;

typedef enum {
    /// The universal script allocates the region (x0 = NULL).
    ArcJITRegionSourceDebugger = 0,
    /// The app maps the region read-execute and hands it to the script.
    ArcJITRegionSourceSelfMapped = 1,
} ArcJITRegionSource;

/// Asks an attached debugger that runs StikDebug's universal.js to prepare an
/// executable region (brk #0xf00d, x16 = 1) and creates the writable alias.
/// Refuses to trap when no debugger is attached, because an unhandled brk
/// kills the process. Always fails in the simulator.
bool ArcJITPrepareRegion(ArcJITRegionSource source, size_t size, ArcJITRegion *region,
                         char *message, size_t messageSize);

/// Tells universal.js to detach (brk #0xf00d, x16 = 0). Regions must be
/// prepared before this call.
bool ArcJITDetach(char *message, size_t messageSize);

/// Maps a region read-execute and aliases it read-write without a debugger.
/// This works where the kernel does not enforce W^X through code signing,
/// such as the iOS Simulator on a Mac. It proves nothing about a device.
bool ArcJITCreateLocalRegion(size_t size, ArcJITRegion *region, char *message, size_t messageSize);

typedef enum {
    ArcJITProbeNotExecutable = 0,
    ArcJITProbeWrongResult = 1,
    ArcJITProbePassed = 2,
} ArcJITProbeOutcome;

/// Writes `mov w0, #42; ret` through the writable alias and calls the
/// executable view, but only if the kernel reports the page as executable.
/// `protection` receives the VM protection of the executable view.
ArcJITProbeOutcome ArcJITProbeRegion(const ArcJITRegion *region, int *protection);

#ifdef __cplusplus
}
#endif
