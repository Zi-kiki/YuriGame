#ifndef LIVECONTAINER_LCUTILS_H
#define LIVECONTAINER_LCUTILS_H

#import <Foundation/Foundation.h>
#import "LCMachOUtils.h"

int dyld_get_program_sdk_version(void);

@interface LCUtils : NSObject

+ (NSData *)certificateData;
+ (NSString *)certificatePassword;

+ (NSProgress *)signAppBundleWithZSign:(NSURL *)path completionHandler:(void (^)(BOOL success, NSError *error))completionHandler;
+ (BOOL)signMachOAtURL:(NSURL *)url;
+ (int)validateCertificateWithCompletionHandler:(void(^)(int status, NSDate *expirationDate, NSString *error))completionHandler;

@end

#endif /* LIVECONTAINER_LCUTILS_H */
