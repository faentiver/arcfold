#include "ArcJIT.h"

#include <TargetConditionals.h>
#include <errno.h>
#include <libkern/OSCacheControl.h>
#include <mach/mach.h>
#include <mach/mach_error.h>
#include <mach/vm_map.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/proc.h>
#include <sys/sysctl.h>
#include <unistd.h>

// Private but stable syscall wrapper exported by libSystem (bsd/sys/codesign.h in XNU).
extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

// Values from XNU osfmk/kern/cs_blobs.h.
enum {
    ArcCSOpsStatus = 0,
    ArcCSGetTaskAllow = 0x00000004,
    ArcCSDebugged = 0x10000000,
};

static bool ArcJITIsTraced(void) {
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    if (sysctl(mib, 4, &info, &size, NULL, 0) != 0) {
        return false;
    }
    return (info.kp_proc.p_flag & P_TRACED) != 0;
}

ArcJITProcessStatus ArcJITReadProcessStatus(void) {
    ArcJITProcessStatus status;
    memset(&status, 0, sizeof(status));
    uint32_t flags = 0;
    status.csopsResult = csops(getpid(), ArcCSOpsStatus, &flags, sizeof(flags));
    if (status.csopsResult == 0) {
        status.flags = flags;
        status.getTaskAllow = (flags & ArcCSGetTaskAllow) != 0;
        status.debugged = (flags & ArcCSDebugged) != 0;
    }
    status.traced = ArcJITIsTraced();
    return status;
}

// "iPhone14,2" -> 14.2, "iPad14,10" -> 14.1 (StikDebug divides the minor by
// its power of ten in the same way).
static bool ArcJITModelVersion(const char *identifier, const char *prefix, double *version) {
    size_t prefixLength = strlen(prefix);
    if (strncmp(identifier, prefix, prefixLength) != 0) {
        return false;
    }
    int major = 0;
    int minor = 0;
    if (sscanf(identifier + prefixLength, "%d,%d", &major, &minor) != 2) {
        return false;
    }
    double divisor = 1.0;
    for (int remaining = minor; remaining > 0; remaining /= 10) {
        divisor *= 10.0;
    }
    if (minor == 0) {
        divisor = 10.0;
    }
    *version = major + minor / divisor;
    return true;
}

bool ArcJITAssumesTXM(const char *hardwareIdentifier, int osMajorVersion) {
    if (osMajorVersion >= 27) {
        return strcmp(hardwareIdentifier, "iPad8,11") != 0 && strcmp(hardwareIdentifier, "iPad8,12") != 0;
    }
    if (osMajorVersion == 26) {
        double version = 0;
        if (ArcJITModelVersion(hardwareIdentifier, "iPhone", &version)) {
            return version >= 14.2;
        }
        if (ArcJITModelVersion(hardwareIdentifier, "iPad", &version)) {
            return version >= 14.5;
        }
    }
    return false;
}

// The "universal" breakpoint protocol from StikJIT's INTEGRATION.md: the
// command goes in x16, arguments in x0 and x1, the result comes back in x0.
__attribute__((noinline, optnone, naked))
static void *ArcJIT26PrepareRegion(__attribute__((unused)) void *address,
                                   __attribute__((unused)) size_t length) {
    __asm__ volatile(
        "mov x16, #1\n"
        "brk #0xf00d\n"
        "ret\n");
}

__attribute__((noinline, optnone, naked))
static void ArcJIT26Detach(void) {
    __asm__ volatile(
        "mov x16, #0\n"
        "brk #0xf00d\n"
        "ret\n");
}

static bool ArcJITCreateAlias(void *executable, size_t size, ArcJITRegion *region,
                              char *message, size_t messageSize) {
    vm_address_t writable = 0;
    vm_prot_t current = VM_PROT_NONE;
    vm_prot_t maximum = VM_PROT_NONE;
    kern_return_t result = vm_remap(mach_task_self(), &writable, size, 0, VM_FLAGS_ANYWHERE,
                                    mach_task_self(), (vm_address_t)executable, FALSE,
                                    &current, &maximum, VM_INHERIT_NONE);
    if (result != KERN_SUCCESS) {
        snprintf(message, messageSize, "vm_remap failed: %d (%s)", result, mach_error_string(result));
        return false;
    }
    result = vm_protect(mach_task_self(), writable, size, FALSE, VM_PROT_READ | VM_PROT_WRITE);
    if (result != KERN_SUCCESS) {
        snprintf(message, messageSize, "vm_protect(rw) on alias failed: %d (%s), max protection %d",
                 result, mach_error_string(result), maximum);
        vm_deallocate(mach_task_self(), writable, size);
        return false;
    }
    region->executable = executable;
    region->writable = (void *)writable;
    region->size = size;
    return true;
}

static bool ArcJITCheckDebugger(char *message, size_t messageSize) {
#if TARGET_OS_SIMULATOR
    snprintf(message, messageSize, "the breakpoint protocol only exists on devices");
    return false;
#else
    ArcJITProcessStatus status = ArcJITReadProcessStatus();
    if (!status.traced) {
        snprintf(message, messageSize, "no debugger attached (CS_DEBUGGED %d, P_TRACED 0); a brk would kill the app",
                 status.debugged);
        return false;
    }
    return true;
#endif
}

bool ArcJITPrepareRegion(ArcJITRegionSource source, size_t size, ArcJITRegion *region,
                         char *message, size_t messageSize) {
    memset(region, 0, sizeof(*region));
    if (!ArcJITCheckDebugger(message, messageSize)) {
        return false;
    }
    void *requested = NULL;
    if (source == ArcJITRegionSourceSelfMapped) {
        requested = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (requested == MAP_FAILED) {
            snprintf(message, messageSize, "mmap(r-x) failed: %s", strerror(errno));
            return false;
        }
    }
    void *executable = ArcJIT26PrepareRegion(requested, size);
    uintptr_t value = (uintptr_t)executable;
    // An unserviced trap can leave arbitrary bits in x0, so only a page-aligned
    // address (and the requested one, if we mapped it) counts as an answer.
    bool plausible = value != 0 && (value & 0x3FFF) == 0 &&
                     (requested == NULL || executable == requested);
    if (!plausible) {
        snprintf(message, messageSize, "universal.js did not answer (x0 = 0x%lx)", (unsigned long)value);
        return false;
    }
    if (!ArcJITCreateAlias(executable, size, region, message, messageSize)) {
        return false;
    }
    snprintf(message, messageSize, "prepared %zu KiB at %p, writable alias %p", size / 1024, region->executable,
             region->writable);
    return true;
}

bool ArcJITDetach(char *message, size_t messageSize) {
    if (!ArcJITCheckDebugger(message, messageSize)) {
        return false;
    }
    ArcJIT26Detach();
    snprintf(message, messageSize, "detach requested");
    return true;
}

bool ArcJITCreateLocalRegion(size_t size, ArcJITRegion *region, char *message, size_t messageSize) {
    memset(region, 0, sizeof(*region));
    void *executable = mmap(NULL, size, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (executable == MAP_FAILED) {
        snprintf(message, messageSize, "mmap(r-x) failed: %s", strerror(errno));
        return false;
    }
    if (!ArcJITCreateAlias(executable, size, region, message, messageSize)) {
        munmap(executable, size);
        return false;
    }
    snprintf(message, messageSize, "mapped %zu KiB at %p, writable alias %p", size / 1024, region->executable,
             region->writable);
    return true;
}

// `mov w0, #value; ret`
static void ArcJITProbeCode(uint16_t value, uint32_t code[2]) {
    code[0] = 0x52800000u | ((uint32_t)value << 5); // movz w0, #value
    code[1] = 0xd65f03c0u;                          // ret
}

// Calls the probe code only when the kernel reports its page as executable,
// so a missing execute right shows up as a result instead of a crash.
static ArcJITProbeOutcome ArcJITCallIfExecutable(void *code, size_t length, uint16_t expected, int *protection) {
    sys_icache_invalidate(code, length);
    vm_address_t address = (vm_address_t)code;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &objectName);
    *protection = result == KERN_SUCCESS ? info.protection : -1;
    if (result != KERN_SUCCESS || (info.protection & VM_PROT_EXECUTE) == 0) {
        return ArcJITProbeNotExecutable;
    }
    int (*function)(void) = (int (*)(void))code;
    return function() == expected ? ArcJITProbePassed : ArcJITProbeWrongResult;
}

ArcJITProbeOutcome ArcJITProbeRegionAt(const ArcJITRegion *region, size_t offset, uint16_t value,
                                       int *protection) {
    uint32_t code[2];
    ArcJITProbeCode(value, code);
    *protection = -1;
    if (offset > region->size || region->size - offset < sizeof(code)) {
        return ArcJITProbeNotExecutable;
    }
    memcpy((uint8_t *)region->writable + offset, code, sizeof(code));
    return ArcJITCallIfExecutable((uint8_t *)region->executable + offset, sizeof(code), value, protection);
}

ArcJITProbeOutcome ArcJITProbeProtectFlip(int *protection, char *message, size_t messageSize) {
    vm_address_t address = 0;
    const vm_size_t size = 16384;
    *protection = -1;
    kern_return_t result = vm_allocate(mach_task_self(), &address, size, VM_FLAGS_ANYWHERE);
    if (result != KERN_SUCCESS) {
        snprintf(message, messageSize, "vm_allocate failed: %d (%s)", result, mach_error_string(result));
        return ArcJITProbeNotExecutable;
    }
    uint32_t code[2];
    ArcJITProbeCode(42, code);
    memcpy((void *)address, code, sizeof(code));
    result = vm_protect(mach_task_self(), address, size, FALSE, VM_PROT_READ | VM_PROT_EXECUTE);
    snprintf(message, messageSize, "vm_protect(r-x) returned %d (%s)", result, mach_error_string(result));
    if (result != KERN_SUCCESS) {
        return ArcJITProbeNotExecutable;
    }
    return ArcJITCallIfExecutable((void *)address, sizeof(code), 42, protection);
}
