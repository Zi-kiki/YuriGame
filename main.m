#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include <dlfcn.h>

static int (*appMain)(int, char**);
static NSBundle *overwrittenBundle;

@implementation NSBundle(LC_iOS12)
+ (id)hooked_mainBundle {
    return overwrittenBundle ? overwrittenBundle : [self hooked_mainBundle];
}
@end

const char **_CFGetProgname(void);
const char **_CFGetProcessPath(void);

static void *getAppEntryPoint(uint32_t imageIndex) {
    const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(imageIndex);
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    
    for(int i = 0; i < header->ncmds; ++i) {
        if(command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            return (void *)((uintptr_t)header + ucmd.entryoff);
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    return NULL;
}

static void invokeAppMain(NSString *selectedApp, int argc, char *argv[]) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"selected"];
    
    NSString *docPath = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject.path;
    
    NSString *bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    NSBundle *appBundle = [[NSBundle alloc] initWithPath:bundlePath];
    
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
    
    appMain = getAppEntryPoint(appImageIndex);
    
    [appBundle loadAndReturnError:nil];
    
    NSMutableArray<NSString *> *objcArgv = NSProcessInfo.processInfo.arguments.mutableCopy;
    if (objcArgv.count > 0) {
        objcArgv[0] = appBundle.executablePath;
        [NSProcessInfo.processInfo performSelector:@selector(setArguments:) withObject:objcArgv];
    }
    
    NSProcessInfo.processInfo.processName = appBundle.infoDictionary[@"CFBundleExecutable"] ?: appBundle.bundleIdentifier;
    *_CFGetProgname() = NSProcessInfo.processInfo.processName.UTF8String;
    
    argv[0] = (char *)appBundle.executablePath.UTF8String;
    appMain(argc, argv);
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
