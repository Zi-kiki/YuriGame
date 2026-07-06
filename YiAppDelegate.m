#import "YiAppDelegate.h"
#import "MainUI.h"

static dispatch_queue_t pluginLinkQueue;

static BOOL safeCreateSymbolicLink(NSString *sourcePath, NSString *destPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:destPath]) {
        NSString *existingLink = [fm destinationOfSymbolicLinkAtPath:destPath error:nil];
        if (existingLink && [existingLink isEqualToString:sourcePath]) return NO;
        [fm removeItemAtPath:destPath error:nil];
    }
    
    return [fm createSymbolicLinkAtPath:destPath withDestinationPath:sourcePath error:nil];
}

static BOOL linkPluginsFolder(NSString *sourcePath, NSString *destPath) {
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL didLink = NO;
    
    [fm createDirectoryAtPath:destPath withIntermediateDirectories:YES attributes:nil error:nil];
    
    for (NSString *item in [fm contentsOfDirectoryAtPath:sourcePath error:nil]) {
        NSString *sourceItem = [sourcePath stringByAppendingPathComponent:item];
        NSString *destItem = [destPath stringByAppendingPathComponent:item];
        
        BOOL isDirectory;
        if ([fm fileExistsAtPath:sourceItem isDirectory:&isDirectory]) {
            if (isDirectory) {
                didLink |= linkPluginsFolder(sourceItem, destItem);
            } else {
                if (safeCreateSymbolicLink(sourceItem, destItem)) didLink = YES;
            }
        }
    }
    return didLink;
}

static void linkPluginsToDocuments() {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *pluginsPath = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"PlugIns"];
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *destPath = [documentsPath stringByAppendingPathComponent:@"Applications"];
    
    BOOL isDirectory;
    if (![fm fileExistsAtPath:pluginsPath isDirectory:&isDirectory] || !isDirectory) return;
    
    linkPluginsFolder(pluginsPath, destPath);
}

@implementation YiAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    pluginLinkQueue = dispatch_queue_create("com.pluginlinker.queue", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(pluginLinkQueue, ^{
        linkPluginsToDocuments();
    });
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [TSRootViewController new];
    [self.window makeKeyAndVisible];
    
    return YES;
}

@end
