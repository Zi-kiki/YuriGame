#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <dlfcn.h>
#include <assert.h>
#include <limits.h>
#include <sys/mman.h>
#import "litehook/utils.h"
#import "litehook/LCMachOUtils.h"
#import "litehook/litehook.h"

@interface NSBundle(private)
- (id)_cfBundle;
@end

@interface NSUserDefaults(private)
+ (void)setStandardUserDefaults:(id)defaults;
- (void)_setIdentifier:(NSString *)identifier;
@end

@interface _CFXPreferences : NSObject
+ (instancetype)copyDefaultPreferences;
@end

@interface CFPrefsPlistSource2 : NSObject
- (id)hook_initWithDomain:(CFStringRef)arg1 user:(CFStringRef)arg2 byHost:(bool)arg3 containerPath:(CFStringRef)arg4 containingPreferences:(id)arg5;
@end

extern CFBundleRef CFBundleGetMainBundle(void);
bool performHookDyldApi(const char *functionName, uint32_t adrpOffset, void **origFunction, void *hookFunction);
void *dlopenBypassingLock(const char *path, int mode);
void *getGuestAppHeader(void);
void DyldHooksInit(void);
extern uint32_t appMainImageIndex;
extern void *appExecutableHandle;

static int (*appMain)(int, char **);
static NSBundle *overwrittenBundle;
static NSString *ygContainerPath = nil;

@implementation NSBundle(LC_iOS14)
+ (id)hooked_mainBundle {
    return overwrittenBundle ? overwrittenBundle : [self hooked_mainBundle];
}
@end

@implementation NSString(YGRealpath)
- (NSString *)yg_realpath {
    char result[PATH_MAX];
    realpath(self.fileSystemRepresentation, result);
    return [NSString stringWithUTF8String:result];
}
@end

@implementation NSBundle(YGMainBundle)
- (instancetype)initWithPathForMainBundle:(NSString *)path {
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path.yg_realpath];
    id cfBundle = CFBridgingRelease(CFBundleCreate(NULL, url));
    if (!cfBundle) return nil;
    self = [self initWithPath:path];
    object_setIvar(self, class_getInstanceVariable(self.class, "_cfBundle"), cfBundle);
    return self;
}
@end

typedef struct {
    void *gap_0x0[2];
    char *mainExecutablePath_old;
    void *gap_0x18;
    char *mainExecutablePath_18_4;
    size_t mainExecutablePathLen_27_0;
} DyldConfig;

typedef struct {
    void *gap_0x0;
    DyldConfig *dyldConfig;
} DyldAPI;

static BOOL ygIsIOS14(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion < 15;
}

static BOOL ygIsAtLeastMajor(NSInteger major) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= major;
}

static uint64_t yg_aarch64_get_tbnz_jump_address(uint32_t instruction, uint64_t pc) {
    if ((instruction & 0xFF000000) != 0x37000000) {
        return 0;
    }
    uint32_t imm = ((instruction >> 5) & 0xFFFF) * 4;
    return imm + pc;
}

static uint64_t yg_aarch64_emulate_adrp(uint32_t instruction, uint64_t pc) {
    if ((instruction & 0x9F000000) != 0x90000000) {
        return 0;
    }
    int32_t imm_hi_lo = (instruction & 0xFFFFE0) >> 3;
    imm_hi_lo |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        imm_hi_lo |= 0xFFE00000;
    }
    int64_t imm = ((int64_t)imm_hi_lo << 12);
    return (pc & ~(0xFFFULL)) + imm;
}

static bool yg_aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm) {
    if ((instruction & 0xFF000000) != 0x91000000) {
        return false;
    }
    int32_t imm12 = (instruction & 0x3FFC00) >> 10;
    uint8_t shift = (instruction & 0xC00000) >> 22;
    switch (shift) {
        case 0:
            *imm = imm12;
            break;
        case 1:
            *imm = imm12 << 12;
            break;
        default:
            return false;
    }
    *dst = instruction & 0x1F;
    *src = (instruction >> 5) & 0x1F;
    return true;
}

static uint64_t yg_aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc) {
    uint64_t adrp_target = yg_aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    uint32_t addDst;
    uint32_t addSrc;
    uint32_t addImm;
    if (!yg_aarch64_emulate_add_imm(addInstruction, &addDst, &addSrc, &addImm)) {
        return 0;
    }
    if ((instruction & 0x1F) != addSrc) {
        return 0;
    }
    return adrp_target + (uint64_t)addImm;
}

static BOOL ygIsAppleIdentifier(NSString *identifier) {
    return [identifier hasPrefix:@"com.apple."]
        || [identifier hasPrefix:@"group.com.apple."]
        || [identifier hasPrefix:@"systemgroup.com.apple."];
}

static void ygSwizzle(Class class, SEL originalAction, Class class2, SEL swizzledAction) {
    Method m1 = class_getInstanceMethod(class2, swizzledAction);
    class_addMethod(class, swizzledAction, method_getImplementation(m1), method_getTypeEncoding(m1));
    method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
}

@implementation CFPrefsPlistSource2
- (id)hook_initWithDomain:(CFStringRef)domain user:(CFStringRef)user byHost:(bool)host containerPath:(CFStringRef)containerPath containingPreferences:(id)arg5 {
    if (ygIsAppleIdentifier((__bridge NSString *)domain)) {
        return [self hook_initWithDomain:domain user:user byHost:host containerPath:containerPath containingPreferences:arg5];
    }
    if (user == kCFPreferencesAnyUser) {
        user = kCFPreferencesCurrentUser;
    }
    return [self hook_initWithDomain:domain user:user byHost:host containerPath:(__bridge CFStringRef)ygContainerPath containingPreferences:arg5];
}
@end

static void *ygGetAppEntryPointByIndex(uint32_t imageIndex) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
    if (!header) return NULL;
    uint8_t *imageHeaderPtr = (uint8_t *)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for (int i = 0; i < header->ncmds; ++i) {
        if (command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            return (void *)((uintptr_t)header + ucmd.entryoff);
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    return NULL;
}

static void ygOverwriteMainCFBundle(void) {
    uint32_t *pc = (uint32_t *)CFBundleGetMainBundle;
    void **mainBundleAddr = 0;
    if (ygIsAtLeastMajor(27)) {
        while (true) {
            bool isTbz = ((*pc) & 0x7F000000) == 0x36000000;
            if (isTbz) {
                mainBundleAddr = (void **)aarch64_emulate_adrp_ldr(*(pc - 1), *(uint32_t *)(pc + 1), (uint64_t)(pc - 1));
                break;
            }
            ++pc;
        }
    } else {
        while (true) {
            uint64_t addr = yg_aarch64_get_tbnz_jump_address(*pc, (uint64_t)pc);
            if (addr) {
                mainBundleAddr = (void **)aarch64_emulate_adrp_ldr(*(pc - 1), *(uint32_t *)addr, (uint64_t)(pc - 1));
                break;
            }
            ++pc;
        }
    }
    assert(mainBundleAddr != NULL);
    *mainBundleAddr = (__bridge void *)NSBundle.mainBundle._cfBundle;
}

static void ygOverwriteMainNSBundle(NSBundle *newBundle) {
    NSString *oldPath = NSBundle.mainBundle.executablePath;
    uint32_t *mainBundleImpl = (uint32_t *)method_getImplementation(class_getClassMethod(NSBundle.class, @selector(mainBundle)));
    for (int i = 0; i < 20; i++) {
        void **_MergedGlobals = (void **)yg_aarch64_emulate_adrp_add(mainBundleImpl[i], mainBundleImpl[i + 1], (uint64_t)&mainBundleImpl[i]);
        if (!_MergedGlobals) continue;
        if ((mainBundleImpl[i + 4] & 0xFF000000) == 0xF8000000) {
            uint64_t ptr = (uint64_t)_MergedGlobals - 4;
            _MergedGlobals = (void **)ptr;
        }
        for (int mgIdx = 0; mgIdx < 20; mgIdx++) {
            if (_MergedGlobals[mgIdx] == (__bridge void *)NSBundle.mainBundle) {
                _MergedGlobals[mgIdx] = (__bridge void *)newBundle;
                break;
            }
        }
    }
    assert(![NSBundle.mainBundle.executablePath isEqualToString:oldPath]);
}

static int hook__NSGetExecutablePath_overwriteExecPath(DyldAPI *dyldApiInstancePtr, char *newPath, uint32_t *bufsize) {
    assert(dyldApiInstancePtr != 0);
    DyldConfig *dyldConfig = dyldApiInstancePtr->dyldConfig;
    assert(dyldConfig != 0);
    char **mainExecutablePathPtr = 0;
    if (dyldConfig->mainExecutablePath_old != 0 && dyldConfig->mainExecutablePath_old[0] == '/') {
        mainExecutablePathPtr = &(dyldConfig->mainExecutablePath_old);
    } else if (dyldConfig->mainExecutablePath_18_4 != 0 && dyldConfig->mainExecutablePath_18_4[0] == '/') {
        mainExecutablePathPtr = &(dyldConfig->mainExecutablePath_18_4);
    } else {
        assert(mainExecutablePathPtr != 0);
    }
    kern_return_t ret = builtin_vm_protect(mach_task_self(), (mach_vm_address_t)dyldConfig, sizeof(dyldConfig), false, PROT_READ | PROT_WRITE);
    if (ret != KERN_SUCCESS) {
        assert(os_tpro_is_supported());
        os_thread_self_restrict_tpro_to_rw();
    }
    *mainExecutablePathPtr = newPath;
    if (ygIsAtLeastMajor(27)) {
        dyldConfig->mainExecutablePathLen_27_0 = strlen(newPath);
    }
    if (ret != KERN_SUCCESS) {
        os_thread_self_restrict_tpro_to_ro();
    }
    return 0;
}

static void ygOverwriteExecPath(const char *newExecPath) {
    int (*orig__NSGetExecutablePath)(void *dyldPtr, char *buf, uint32_t *bufsize);
    performHookDyldApi("_NSGetExecutablePath", 2, (void **)&orig__NSGetExecutablePath, hook__NSGetExecutablePath_overwriteExecPath);
    _NSGetExecutablePath((char *)newExecPath, NULL);
    performHookDyldApi("_NSGetExecutablePath", 2, (void **)&orig__NSGetExecutablePath, orig__NSGetExecutablePath);
}

static void *ygGetAppEntryPoint(void) {
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)getGuestAppHeader();
    uint8_t *imageHeaderPtr = (uint8_t *)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for (int i = 0; i < header->ncmds; ++i) {
        if (command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            entryoff = ucmd.entryoff;
            break;
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    assert(entryoff > 0);
    return (void *)header + entryoff;
}

static void ygNUDGuestHooksInit(NSString *guestBundleId) {
    ygContainerPath = [NSString stringWithUTF8String:getenv("HOME")];
    Class CFPrefsPlistSourceClass = NSClassFromString(@"CFPrefsPlistSource");
    ygSwizzle(CFPrefsPlistSourceClass, @selector(initWithDomain:user:byHost:containerPath:containingPreferences:), CFPrefsPlistSource2.class, @selector(hook_initWithDomain:user:byHost:containerPath:containingPreferences:));
    Class CFXPreferencesClass = NSClassFromString(@"_CFXPreferences");
    NSMutableDictionary *sources = object_getIvar([CFXPreferencesClass copyDefaultPreferences], class_getInstanceVariable(CFXPreferencesClass, "_sources"));
    [sources removeObjectForKey:@"C/A//B/L"];
    [sources removeObjectForKey:@"C/C//*/L"];
    const char *coreFoundationPath = "/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation";
    LCGetLoadedImageHeader(2, coreFoundationPath);
    CFStringRef *_CFPrefsCurrentAppIdentifierCache = litehook_find_dsc_symbol(coreFoundationPath, "__CFPrefsCurrentAppIdentifierCache");
    if (_CFPrefsCurrentAppIdentifierCache) {
        *_CFPrefsCurrentAppIdentifierCache = (__bridge CFStringRef)guestBundleId;
    }
    NSUserDefaults *newStandardUserDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"yg.guest"];
    [newStandardUserDefaults _setIdentifier:guestBundleId];
    [NSUserDefaults setStandardUserDefaults:newStandardUserDefaults];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *libraryPath = [fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask].lastObject;
    NSURL *preferenceFolderPath = [libraryPath URLByAppendingPathComponent:@"Preferences"];
    if (![fm fileExistsAtPath:preferenceFolderPath.path]) {
        [fm createDirectoryAtPath:preferenceFolderPath.path withIntermediateDirectories:YES attributes:@{} error:nil];
    }
}

static void invokeAppMainIOS14(NSString *selectedApp, int argc, char *argv[]) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    if (!appBundle) return;
    NSString *appDataPath = [NSString stringWithFormat:@"%@/%@", docPath, appBundle.bundleIdentifier];
    setenv("CFFIXED_USER_HOME", appDataPath.UTF8String, 1);
    setenv("HOME", appDataPath.UTF8String, 1);
    setenv("TMPDIR", [appDataPath stringByAppendingPathComponent:@"tmp"].UTF8String, 1);
    NSArray *dirs = @[@"tmp", @"Library/Caches", @"Library/Preferences", @"Documents"];
    for (NSString *dir in dirs) {
        NSString *dirPath = [appDataPath stringByAppendingPathComponent:dir];
        [NSFileManager.defaultManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    method_exchangeImplementations(
        class_getClassMethod(NSBundle.class, @selector(mainBundle)),
        class_getClassMethod(NSBundle.class, @selector(hooked_mainBundle))
    );
    overwrittenBundle = appBundle;
    const char **path = _CFGetProcessPath();
    if (path && *path) {
        *path = appBundle.executablePath.UTF8String;
    }
    uint32_t appImageIndex = _dyld_image_count();
    void *appHandle = dlopen(appBundle.executablePath.UTF8String, RTLD_LAZY | RTLD_GLOBAL);
    if (!appHandle) return;
    appMain = ygGetAppEntryPointByIndex(appImageIndex);
    [appBundle loadAndReturnError:nil];
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    if (objcArgv.count > 0) {
        objcArgv[0] = appBundle.executablePath;
        [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    }
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"] ?: appBundle.bundleIdentifier;
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    if (!appMain) return;
    argv[0] = (char *)appBundle.executablePath.UTF8String;
    appMain(argc, argv);
}

static void invokeAppMainModern(NSString *selectedApp, int argc, char *argv[]) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    NSBundle *appBundle = [[NSBundle alloc] initWithPathForMainBundle:bundlePath];
    if (!appBundle) return;
    NSString *appDataPath = [NSString stringWithFormat:@"%@/%@", docPath, appBundle.bundleIdentifier];
    NSString *newTmpPath = [appDataPath stringByAppendingPathComponent:@"tmp"];
    remove(newTmpPath.UTF8String);
    symlink(getenv("TMPDIR"), newTmpPath.UTF8String);
    setenv("CFFIXED_USER_HOME", appDataPath.UTF8String, 1);
    setenv("HOME", appDataPath.UTF8String, 1);
    NSArray *dirs = @[@"Library/Caches", @"Library/Preferences", @"Documents"];
    for (NSString *dir in dirs) {
        NSString *dirPath = [appDataPath stringByAppendingPathComponent:dir];
        [NSFileManager.defaultManager createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    const char *appExecPath = appBundle.executablePath.fileSystemRepresentation;
    const char **path = _CFGetProcessPath();
    *path = appExecPath;
    ygOverwriteExecPath(appExecPath);
    ygOverwriteMainNSBundle(appBundle);
    ygOverwriteMainCFBundle();
    if (!appBundle.executablePath) return;
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    if (objcArgv.count > 0) {
        objcArgv[0] = appBundle.executablePath;
        [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    }
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"] ?: appBundle.bundleIdentifier;
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    Class swiftNSProcessInfo = NSClassFromString(@"_NSSwiftProcessInfo");
    if (swiftNSProcessInfo) {
        SEL selector = @selector(arguments);
        method_setImplementation(class_getInstanceMethod(swiftNSProcessInfo, selector), class_getMethodImplementation(NSProcessInfo.class, selector));
    }
    ygNUDGuestHooksInit(appBundle.bundleIdentifier);
    appMainImageIndex = _dyld_image_count();
    void *appHandle = dlopenBypassingLock(appExecPath, RTLD_LAZY | RTLD_GLOBAL | RTLD_FIRST);
    appExecutableHandle = appHandle;
    if (!appHandle) return;
    DyldHooksInit();
    [appBundle loadAndReturnError:nil];
    appMain = ygGetAppEntryPoint();
    if (!appMain) return;
    argv[0] = (char *)appExecPath;
    appMain(argc, argv);
}

static void invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    if (ygIsIOS14()) {
        invokeAppMainIOS14(selectedApp, argc, argv);
    } else {
        invokeAppMainModern(selectedApp, argc, argv);
    }
}

int YuriGameMain(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *selected = [[NSUserDefaults standardUserDefaults] stringForKey:@"selected"];
        if (selected.length > 0) {
            invokeAppMain(selected, argc, argv);
        }
        return UIApplicationMain(argc, argv, nil, @"YiAppDelegate");
    }
}

int main(int argc, char *argv[]) {
    return YuriGameMain(argc, argv);
}
