#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdlib.h>
#include <sys/mman.h>
#import "litehook.h"
#import "LCMachOUtils.h"
#import "utils.h"

typedef struct {
    uint32_t platform;
    uint32_t version;
} dyld_build_version_t;

uint32_t guestAppSdkVersion = 0;
uint32_t guestAppSdkVersionSet = 0;
static uint32_t appMainImageIndex = 0;

#pragma mark - SDK Version Helpers

static dyld_build_version_t getDyldImageBuildVersion(const struct mach_header *mh) {
    dyld_build_version_t result = { .platform = 0xffffffff, .version = 0 };
    assert(mh != NULL);

    const uint8_t *ptr = ((const uint8_t *)mh) + sizeof(struct mach_header_64);
    uint32_t ncmds = mh->ncmds;

    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        if (lc->cmd == LC_BUILD_VERSION) {
            const struct build_version_command *bvc = (const struct build_version_command *)ptr;
            result.platform = bvc->platform;
            result.version  = bvc->sdk;
            return result;
        }
        ptr += lc->cmdsize;
    }

    ptr = ((const uint8_t *)mh) + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        if (lc->cmd == LC_VERSION_MIN_IPHONEOS ||
            lc->cmd == LC_VERSION_MIN_MACOSX) {
            const struct version_min_command *vm = (const struct version_min_command *)ptr;
            result.platform = 0xffffffff;
            result.version  = vm->sdk;
            return result;
        }
        ptr += lc->cmdsize;
    }
    return result;
}

void* getGuestAppHeader(void) {
    return (void*)_dyld_get_image_header(appMainImageIndex);
}

bool initGuestSDKVersionInfo(void) {
    void* dyldBase = getDyldBase();
    const char* dyldPath = "/usr/lib/dyld";
    uint64_t offset = LCFindSymbolOffset(dyldPath, "__ZN5dyld3L11sVersionMapE");
    uint32_t *versionMapPtr = (uint32_t*)((uintptr_t)dyldBase + offset);

    assert(versionMapPtr);
    uint32_t* versionMapEnd = versionMapPtr + 2560;
    assert(versionMapPtr[0] == 0x07db0901 && versionMapPtr[2] == 0x00050000);

    uint32_t size = 0;
    for (int i = 1; i < 128; ++i) {
        if (versionMapPtr[i] == 0x07dc0901) {
            size = i;
            break;
        }
    }
    assert(size);

    NSOperatingSystemVersion currentVersion = [[NSProcessInfo processInfo] operatingSystemVersion];
    uint32_t maxVersion = ((uint32_t)currentVersion.majorVersion << 16) |
                          ((uint32_t)currentVersion.minorVersion << 8);
    uint32_t candidateVersionEquivalent = 0;
    uint32_t newVersionSetVersion = 0;

    for (uint32_t* nowVersionMapItem = versionMapPtr; nowVersionMapItem < versionMapEnd; nowVersionMapItem += size) {
        newVersionSetVersion = nowVersionMapItem[2];
        if (newVersionSetVersion > guestAppSdkVersion) break;
        candidateVersionEquivalent = nowVersionMapItem[0];
        if (newVersionSetVersion >= maxVersion) break;
    }

    if (newVersionSetVersion == 0xffffffff && candidateVersionEquivalent == 0) {
        candidateVersionEquivalent = newVersionSetVersion;
    }

    guestAppSdkVersionSet = candidateVersionEquivalent;
    return true;
}

bool hook_dyld_program_sdk_at_least(void* dyldApiInstancePtr,
                                    dyld_build_version_t version) {
    switch (version.platform) {
        case 0xffffffff:
            return version.version <= guestAppSdkVersionSet;
        case 2:
            return version.version <= guestAppSdkVersion;
        default:
            return false;
    }
}

uint32_t hook_dyld_get_program_sdk_version(void* dyldApiInstancePtr) {
    return guestAppSdkVersion;
}

bool performHookDyldApi(const char* functionName, uint32_t adrpOffset,
                        void** origFunction, void* hookFunction) {
    uint32_t* baseAddr = (uint32_t*)dlsym(RTLD_DEFAULT, functionName);
    assert(baseAddr != 0);

    uint32_t* adrpInstPtr = baseAddr + adrpOffset;
    if ((*adrpInstPtr & 0x9f000000) != 0x90000000) {
        adrpOffset += 20;
        adrpInstPtr = baseAddr + adrpOffset;
    }
    assert((*adrpInstPtr & 0x9f000000) == 0x90000000);

    void* gdyldPtr = (void*)aarch64_emulate_adrp_ldr(*adrpInstPtr,
                                                     *(baseAddr + adrpOffset + 1),
                                                     (uint64_t)(baseAddr + adrpOffset));
    assert(gdyldPtr != 0);
    assert(*(void**)gdyldPtr != 0);

    void* vtablePtr = **(void***)gdyldPtr;
    void* vtableFunctionPtr = 0;
    uint32_t* movInstPtr = baseAddr + adrpOffset + 6;

    if ((*movInstPtr & 0x7F800000) == 0x52800000) {
        uint32_t imm16 = (*movInstPtr & 0x1FFFE0) >> 5;
        vtableFunctionPtr = vtablePtr + imm16;
    } else if ((*movInstPtr & 0xFFE00C00) == 0xF8400C00) {
        uint32_t imm9 = (*movInstPtr & 0x1FF000) >> 12;
        vtableFunctionPtr = vtablePtr + imm9;
    } else {
        uint32_t* ldrInstPtr2 = baseAddr + adrpOffset + 3;
        assert((*ldrInstPtr2 & 0xBFC00000) == 0xB9400000);
        uint32_t size2 = (*ldrInstPtr2 & 0xC0000000) >> 30;
        uint32_t imm12_2 = (*ldrInstPtr2 & 0x3FFC00) >> 10;
        vtableFunctionPtr = vtablePtr + (imm12_2 << size2);
    }

    kern_return_t ret = builtin_vm_protect(mach_task_self(),
                                           (mach_vm_address_t)vtableFunctionPtr,
                                           sizeof(uintptr_t), false,
                                           PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);

    if (origFunction != NULL) {
        *origFunction = (void*)*(void**)vtableFunctionPtr;
    }

    *(uint64_t*)vtableFunctionPtr = (uint64_t)hookFunction;
    builtin_vm_protect(mach_task_self(),
                       (mach_vm_address_t)vtableFunctionPtr,
                       sizeof(uintptr_t), false, PROT_READ);
    return true;
}

void DyldHooksInit(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        int imageCount = _dyld_image_count();
        for (int i = 0; i < imageCount; ++i) {
            const struct mach_header* hdr = _dyld_get_image_header(i);
            if (hdr->filetype == MH_EXECUTE) {
                appMainImageIndex = i;
                break;
            }
        }

        guestAppSdkVersion = getDyldImageBuildVersion(getGuestAppHeader()).version;

        if (!initGuestSDKVersionInfo() ||
            !performHookDyldApi("dyld_program_sdk_at_least", 1, NULL, hook_dyld_program_sdk_at_least) ||
            !performHookDyldApi("dyld_get_program_sdk_version", 0, NULL, hook_dyld_get_program_sdk_version)) {
            exit(0);
        }
    });
}

#pragma mark - Fix black screen (lock bypass)
static void *lockPtrToIgnore = NULL;

void hook_libdyld_os_unfair_recursive_lock_lock_with_options(void *ptr, void* lock, uint32_t options) {
    if (!lockPtrToIgnore) lockPtrToIgnore = lock;
    if (lock != lockPtrToIgnore)
        os_unfair_recursive_lock_lock_with_options(lock, options);
}

void hook_libdyld_os_unfair_recursive_lock_unlock(void *ptr, void* lock) {
    if (lock != lockPtrToIgnore)
        os_unfair_recursive_lock_unlock(lock);
}

void *dlopenBypassingLock(const char *path, int mode) {
    const char *libdyldPath = "/usr/lib/system/libdyld.dylib";
    mach_header_u *libdyldHeader = LCGetLoadedImageHeader(0, libdyldPath);
    assert(libdyldHeader != NULL);

    void **lockUnlockPtr = NULL;
    void **vtableLibSystemHelpers = litehook_find_dsc_symbol(libdyldPath,
                                   "__ZTVN5dyld416LibSystemHelpersE");
    void *lockFunc = litehook_find_dsc_symbol(libdyldPath,
                                   "__ZNK5dyld416LibSystemHelpers42os_unfair_recursive_lock_lock_with_optionsEP26os_unfair_recursive_lock_s24os_unfair_lock_options_t");
    void *unlockFunc = litehook_find_dsc_symbol(libdyldPath,
                                   "__ZNK5dyld416LibSystemHelpers31os_unfair_recursive_lock_unlockEP26os_unfair_recursive_lock_s");

    while (!lockUnlockPtr) {
        if (vtableLibSystemHelpers[0] == lockFunc) {
            lockUnlockPtr = vtableLibSystemHelpers;
            NSCAssert(vtableLibSystemHelpers[1] == unlockFunc,
                      @"dyld has changed: lock and unlock functions are not next to each other");
            break;
        }
        vtableLibSystemHelpers++;
    }

    kern_return_t ret;
    ret = builtin_vm_protect(mach_task_self(),
                             (mach_vm_address_t)lockUnlockPtr,
                             sizeof(uintptr_t[2]), false,
                             PROT_READ | PROT_WRITE | VM_PROT_COPY);
    assert(ret == KERN_SUCCESS);

    void *origLockPtr = lockUnlockPtr[0];
    void *origUnlockPtr = lockUnlockPtr[1];
    lockUnlockPtr[0] = hook_libdyld_os_unfair_recursive_lock_lock_with_options;
    lockUnlockPtr[1] = hook_libdyld_os_unfair_recursive_lock_unlock;

    void *result = dlopen(path, mode);

    ret = builtin_vm_protect(mach_task_self(),
                             (mach_vm_address_t)lockUnlockPtr,
                             sizeof(uintptr_t[2]), false,
                             PROT_READ | PROT_WRITE);
    assert(ret == KERN_SUCCESS);
    lockUnlockPtr[0] = origLockPtr;
    lockUnlockPtr[1] = origUnlockPtr;

    ret = builtin_vm_protect(mach_task_self(),
                             (mach_vm_address_t)lockUnlockPtr,
                             sizeof(uintptr_t[2]), false,
                             PROT_READ);
    assert(ret == KERN_SUCCESS);
    return result;
}