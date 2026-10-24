#import "SpaceAPILegacyKeychain.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

static BOOL DRFail(NSString **failureReason, NSString *message) {
    if (failureReason != NULL) {
        *failureReason = message;
    }
    return NO;
}

static NSData * _Nullable DRTrustedApplicationData(SecTrustedApplicationRef application,
                                                   NSString **failureReason) {
    CFDataRef data = NULL;
    OSStatus status = SecTrustedApplicationCopyData(application, &data);
    if (status != errSecSuccess) {
        DRFail(failureReason, [NSString stringWithFormat:
            @"Could not verify Keychain access controls (OSStatus %d).", (int)status]);
        return nil;
    }
    if (data == NULL) {
        DRFail(failureReason, @"A trusted-app entry did not contain identity data.");
        return nil;
    }
    return CFBridgingRelease(data);
}

SecAccessRef _Nullable DRCreateSpaceAPIKeychainAccess(NSString *executablePath, OSStatus *status) {
    SecTrustedApplicationRef application = NULL;
    OSStatus result = SecTrustedApplicationCreateFromPath(executablePath.fileSystemRepresentation,
                                                          &application);
    if (result != errSecSuccess) {
        if (status != NULL) *status = result;
        return NULL;
    }

    const void *applications[] = { application };
    CFArrayRef trustedApplications = CFArrayCreate(kCFAllocatorDefault, applications, 1,
                                                   &kCFTypeArrayCallBacks);
    if (trustedApplications == NULL) {
        CFRelease(application);
        if (status != NULL) *status = errSecAllocate;
        return NULL;
    }

    SecAccessRef access = NULL;
    result = SecAccessCreate(CFSTR("DesktopRenamer SpaceAPI access policy"),
                             trustedApplications, &access);
    CFRelease(trustedApplications);
    CFRelease(application);
    if (status != NULL) *status = result;
    return result == errSecSuccess ? access : NULL;
}

BOOL DRValidateSpaceAPIKeychainAccess(CFTypeRef value, NSString *executablePath,
                                     NSString **failureReason) {
    if (value == NULL) {
        return DRFail(failureReason, @"Reading the policy did not return a Keychain item.");
    }

    CFTypeRef itemValue = value;
    if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
        itemValue = CFDictionaryGetValue((CFDictionaryRef)value, kSecValueRef);
    }
    if (itemValue == NULL || CFGetTypeID(itemValue) != SecKeychainItemGetTypeID()) {
        return DRFail(failureReason, @"Reading the policy did not return a Keychain item reference.");
    }

    SecKeychainItemRef item = (SecKeychainItemRef)itemValue;
    SecAccessRef access = NULL;
    OSStatus status = SecKeychainItemCopyAccess(item, &access);
    if (status != errSecSuccess) {
        return DRFail(failureReason, [NSString stringWithFormat:
            @"Could not verify Keychain access controls (OSStatus %d).", (int)status]);
    }
    if (access == NULL) {
        return DRFail(failureReason, @"Keychain returned no access-control object for the policy.");
    }

    CFArrayRef aclList = NULL;
    status = SecAccessCopyACLList(access, &aclList);
    CFRelease(access);
    if (status != errSecSuccess) {
        return DRFail(failureReason, [NSString stringWithFormat:
            @"Could not verify Keychain access controls (OSStatus %d).", (int)status]);
    }
    if (aclList == NULL || CFArrayGetCount(aclList) == 0) {
        if (aclList != NULL) CFRelease(aclList);
        return DRFail(failureReason, @"Keychain returned no readable access-control entries for the policy.");
    }

    SecTrustedApplicationRef selfApplication = NULL;
    status = SecTrustedApplicationCreateFromPath(executablePath.fileSystemRepresentation,
                                                  &selfApplication);
    if (status != errSecSuccess) {
        CFRelease(aclList);
        return DRFail(failureReason, [NSString stringWithFormat:
            @"Could not identify DesktopRenamer for Keychain access (OSStatus %d).", (int)status]);
    }
    NSData *selfData = DRTrustedApplicationData(selfApplication, failureReason);
    CFRelease(selfApplication);
    if (selfData == nil) {
        CFRelease(aclList);
        return NO;
    }

    BOOL hasRestrictedDataAccess = NO;
    BOOL hasAccessControlChange = NO;
    for (CFIndex index = 0; index < CFArrayGetCount(aclList); index++) {
        SecACLRef acl = (SecACLRef)CFArrayGetValueAtIndex(aclList, index);
        CFArrayRef authorizationValues = SecACLCopyAuthorizations(acl);
        if (authorizationValues == NULL || CFArrayGetCount(authorizationValues) == 0) {
            if (authorizationValues != NULL) CFRelease(authorizationValues);
            CFRelease(aclList);
            return DRFail(failureReason, @"A Keychain access-control entry did not return its authorization list.");
        }
        NSArray<NSString *> *authorizations = CFBridgingRelease(authorizationValues);

        if ([authorizations isEqualToArray:@[(__bridge NSString *)kSecACLAuthorizationEncrypt]]
            || [authorizations isEqualToArray:@[(__bridge NSString *)kSecACLAuthorizationIntegrity]]
            || [authorizations isEqualToArray:@[(__bridge NSString *)kSecACLAuthorizationPartitionID]]) {
            continue;
        }

        CFArrayRef applications = NULL;
        CFStringRef description = NULL;
        SecKeychainPromptSelector promptSelector = {};
        status = SecACLCopyContents(acl, &applications, &description, &promptSelector);
        if (description != NULL) CFRelease(description);
        if (status != errSecSuccess || applications == NULL) {
            if (applications != NULL) CFRelease(applications);
            CFRelease(aclList);
            return DRFail(failureReason, [NSString stringWithFormat:
                @"Could not read Keychain access-control entry %ld (OSStatus %d).",
                (long)index, (int)status]);
        }
        NSArray *trustedApps = CFBridgingRelease(applications);

        if ([authorizations isEqualToArray:@[(__bridge NSString *)kSecACLAuthorizationChangeACL]]) {
            hasAccessControlChange = YES;
            BOOL ownerIsRestricted = NO;
            if (trustedApps.count == 0) {
                ownerIsRestricted = YES;
            } else if (trustedApps.count == 1) {
                NSData *ownerData = DRTrustedApplicationData((__bridge SecTrustedApplicationRef)trustedApps[0],
                                                             failureReason);
                ownerIsRestricted = ownerData != nil && [ownerData isEqualToData:selfData];
            }
            if (!ownerIsRestricted) {
                CFRelease(aclList);
                return DRFail(failureReason, @"The Keychain access-control owner entry is not restricted to DesktopRenamer.");
            }
            continue;
        }

        hasRestrictedDataAccess = hasRestrictedDataAccess
            || [authorizations containsObject:(__bridge NSString *)kSecACLAuthorizationDecrypt];
        hasAccessControlChange = hasAccessControlChange
            || [authorizations containsObject:(__bridge NSString *)kSecACLAuthorizationChangeACL];
        if (trustedApps.count != 1) {
            CFRelease(aclList);
            return DRFail(failureReason, [NSString stringWithFormat:
                @"Keychain access-control entry %ld contains %lu trusted apps; expected exactly one.",
                (long)index, (unsigned long)trustedApps.count]);
        }
        NSData *trustedData = DRTrustedApplicationData((__bridge SecTrustedApplicationRef)trustedApps[0],
                                                       failureReason);
        if (trustedData == nil || ![trustedData isEqualToData:selfData]) {
            CFRelease(aclList);
            if (trustedData != nil) {
                return DRFail(failureReason, [NSString stringWithFormat:
                    @"Keychain access-control entry %ld does not identify this DesktopRenamer executable.",
                    (long)index]);
            }
            return NO;
        }
    }
    CFRelease(aclList);

    if (!hasRestrictedDataAccess) {
        return DRFail(failureReason, @"The saved policy has no restricted data-access entry.");
    }
    if (!hasAccessControlChange) {
        return DRFail(failureReason, @"The saved policy has no access-control change entry.");
    }
    return YES;
}

#pragma clang diagnostic pop
