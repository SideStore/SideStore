//
//  RSTExceptionCatcher.m
//  AltStoreCore
//

#import "RSTExceptionCatcher.h"

NSErrorDomain const RSTExceptionCatcherErrorDomain = @"RSTExceptionCatcherErrorDomain";

@implementation RSTExceptionCatcher

+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))tryBlock error:(NSError **)error
{
    @try
    {
        tryBlock();
        return YES;
    }
    @catch (NSException *exception)
    {
        if (error != NULL)
        {
            NSMutableDictionary<NSErrorUserInfoKey, id> *userInfo = [NSMutableDictionary dictionary];
            userInfo[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            userInfo[@"NSExceptionName"] = exception.name;
            if (exception.reason != nil)
            {
                userInfo[@"NSExceptionReason"] = exception.reason;
            }
            if (exception.userInfo != nil)
            {
                userInfo[@"NSExceptionUserInfo"] = exception.userInfo;
            }

            *error = [NSError errorWithDomain:RSTExceptionCatcherErrorDomain code:-1 userInfo:userInfo];
        }

        return NO;
    }
}

@end
