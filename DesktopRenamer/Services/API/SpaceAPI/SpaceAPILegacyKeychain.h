#import <Foundation/Foundation.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT SecAccessRef _Nullable
DRCreateSpaceAPIKeychainAccess(NSString *executablePath, OSStatus *status) CF_RETURNS_RETAINED;

FOUNDATION_EXPORT BOOL
DRValidateSpaceAPIKeychainAccess(CFTypeRef _Nullable value, NSString *executablePath,
                                 NSString * _Nullable * _Nullable failureReason);

NS_ASSUME_NONNULL_END
