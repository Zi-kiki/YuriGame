#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "fishhook.h"
#import <unistd.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static NSString *redirectedPath;
static FILE *(*orig_fopen)(const char *, const char *);

FILE *redirected_fopen(const char *path, const char *mode) {
    if (path && redirectedPath) {
        NSString *originalPath = [NSString stringWithUTF8String:path];
        NSString *fileName = originalPath.lastPathComponent;
        NSString *extension = [fileName pathExtension];
        
        if ([extension isEqualToString:@"png"] || [extension isEqualToString:@"dat"]) {
            NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
            
            if ([originalPath hasPrefix:documentsPath]) {
                NSString *relativePath = [originalPath substringFromIndex:documentsPath.length];
                NSArray *pathComponents = [relativePath pathComponents];
                
                if (pathComponents.count == 2) {
                    NSString *newPath = [redirectedPath stringByAppendingPathComponent:fileName];
                    return orig_fopen([newPath UTF8String], mode);
                }
            } else {
                NSArray *pathComponents = [originalPath pathComponents];
                if (pathComponents.count == 1) {
                    NSString *newPath = [redirectedPath stringByAppendingPathComponent:fileName];
                    return orig_fopen([newPath UTF8String], mode);
                }
            }
        }
    }
    return orig_fopen(path, mode);
}

static NSArray<NSString *> *(*original_NSSearchPathForDirectoriesInDomains)(NSSearchPathDirectory, NSSearchPathDomainMask, BOOL);
static NSString *redirectBasePath = nil;

NSArray<NSString *> *redirected_NSSearchPathForDirectoriesInDomains(NSSearchPathDirectory directory, NSSearchPathDomainMask domainMask, BOOL expandTilde) {
    NSArray<NSString *> *originalPaths = original_NSSearchPathForDirectoriesInDomains(directory, domainMask, expandTilde);
    
    if (directory == NSDocumentDirectory && originalPaths.count > 0 && redirectBasePath) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:redirectBasePath]) {
            [fileManager createDirectoryAtPath:redirectBasePath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        
        return @[redirectBasePath];
    }
    
    return originalPaths;
}

@interface ArtemisRedirect : NSObject
+ (instancetype)sharedInstance;
- (const char *)redirectPathIfNeeded:(const char *)path;
@end

@implementation ArtemisRedirect {
    NSString *_documentsPath;
    NSString *_bundlePath;
    NSString *_currentWorkingDirectory;
    BOOL _enabled;
}

+ (instancetype)sharedInstance {
    static ArtemisRedirect *sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject stringByStandardizingPath];
        _bundlePath = [NSBundle mainBundle].bundlePath.stringByStandardizingPath;
        char cwd[PATH_MAX];
        _currentWorkingDirectory = getcwd(cwd, sizeof(cwd)) ? [NSString stringWithUTF8String:cwd].stringByStandardizingPath : _bundlePath;
        
        NSString *configPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/.preference/Game.txt"];
        NSData *configData = [NSData dataWithContentsOfFile:configPath];
        if (configData && configData.length > 0) {
            _enabled = YES;
        } else {
            _enabled = NO;
        }
    }
    return self;
}

- (NSString *)resolvePath:(const char *)path {
    if (!path) return nil;
    NSString *originalPath = [NSString stringWithUTF8String:path];
    if (!originalPath.absolutePath) {
        originalPath = [_currentWorkingDirectory stringByAppendingPathComponent:originalPath];
    }
    return originalPath.stringByStandardizingPath;
}

- (const char *)redirectPathIfNeeded:(const char *)path {
    if (!path || !_enabled) return path;
    NSString *resolvedPath = [self resolvePath:path];
    if ([resolvedPath hasPrefix:_bundlePath]) {
        NSString *relativePath = [resolvedPath substringFromIndex:_bundlePath.length];
        if ([relativePath hasPrefix:@"/"]) relativePath = [relativePath substringFromIndex:1];
        return [_documentsPath stringByAppendingPathComponent:relativePath].UTF8String;
    }
    return path;
}
@end

static FILE *(*orig_fopen2)(const char *, const char *);
FILE *new_fopen(const char *filename, const char *mode) {
    return orig_fopen2([ArtemisRedirect.sharedInstance redirectPathIfNeeded:filename], mode);
}

@implementation AVPlayerItem (Hook)
- (instancetype)hooked_initWithURL:(NSURL *)URL {
    NSString *extension = URL.pathExtension;
    BOOL isMP4 = [extension caseInsensitiveCompare:@"mp4"] == NSOrderedSame;
    
    if (!isMP4) {
        NSURL *dummyURL = [[NSBundle mainBundle] URLForResource:@"dummy" withExtension:@"mp4"];
        if (dummyURL) {
            return [self hooked_initWithURL:dummyURL];
        }
    }
    
    NSString *docDir = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *movieDir = [docDir stringByAppendingPathComponent:@"movie"];
    NSString *fileName = URL.lastPathComponent;
    
    __block NSString *foundPath = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([fileManager fileExistsAtPath:movieDir]) {
        NSDirectoryEnumerator *enumerator = [fileManager enumeratorAtPath:movieDir];
        
        for (NSString *path in enumerator) {
            if ([path.lastPathComponent isEqualToString:fileName]) {
                foundPath = [movieDir stringByAppendingPathComponent:path];
                break;
            }
        }
    }
    
    if (foundPath && isMP4) {
        return [self hooked_initWithURL:[NSURL fileURLWithPath:foundPath]];
    }
    
    NSURL *dummyURL = [[NSBundle mainBundle] URLForResource:@"dummy" withExtension:@"mp4"];
    if (dummyURL) {
        return [self hooked_initWithURL:dummyURL];
    }
    
    return [self hooked_initWithURL:URL];
}
@end

__attribute__((constructor)) static void init() {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *configPath = [documentsPath stringByAppendingPathComponent:@".preference/Game.txt"];
    NSString *gamePath = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
    
    if (gamePath && gamePath.length > 0) {
        redirectedPath = [gamePath stringByAppendingPathComponent:@"SaveData"];
        [[NSFileManager defaultManager] createDirectoryAtPath:redirectedPath withIntermediateDirectories:YES attributes:nil error:nil];
        struct rebinding rebind = {"fopen", (void *)redirected_fopen, (void **)&orig_fopen};
        rebind_symbols(&rebind, 1);
    }
    
    @autoreleasepool {
        NSArray<NSString *> *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        if (docPaths.count > 0) {
            NSString *docPath = [docPaths firstObject];
            NSString *configPath = [docPath stringByAppendingPathComponent:@".preference/Game.txt"];
            
            NSFileManager *fileManager = [NSFileManager defaultManager];
            if ([fileManager fileExistsAtPath:configPath]) {
                NSString *gamePath = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
                gamePath = [gamePath stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                
                if (gamePath.length > 0) {
                    redirectBasePath = [gamePath copy];
                }
            }
        }
        
        if (redirectBasePath) {
            struct rebinding rebind;
            rebind.name = "NSSearchPathForDirectoriesInDomains";
            rebind.replacement = redirected_NSSearchPathForDirectoriesInDomains;
            rebind.replaced = (void **)&original_NSSearchPathForDirectoriesInDomains;
            
            struct rebinding rebs[] = {rebind};
            rebind_symbols(rebs, 1);
        }
    }
    
    struct rebinding rebindings[] = {{"fopen", new_fopen, (void **)&orig_fopen2}};
    rebind_symbols(rebindings, 1);
    
    Class cls = NSClassFromString(@"AVPlayerItem");
    SEL orig = @selector(initWithURL:);
    SEL hook = @selector(hooked_initWithURL:);
    Method origM = class_getInstanceMethod(cls, orig);
    Method hookM = class_getInstanceMethod(cls, hook);
    method_exchangeImplementations(origM, hookM);
}