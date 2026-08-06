//
//  RSTExceptionCatcher.h
//  AltStoreCore
//
//  Swift's do/catch can only intercept NSError-based throwing; it cannot
//  catch a raised NSException. Some Core Data internal consistency checks
//  (e.g. "you never successfully opened the database corrupted") are raised
//  as NSExceptions, which otherwise crash the process with SIGABRT even
//  from inside a Swift do/catch block. This helper runs a block and, if it
//  raises an NSException, converts it into a returned NSError instead of
//  letting it propagate and crash.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RSTExceptionCatcher : NSObject

/// Runs `tryBlock`. If it raises an NSException, the exception is caught,
/// converted into an NSError (domain "RSTExceptionCatcherErrorDomain", the
/// exception's name/reason preserved in userInfo), and returned via `error`.
/// Returns YES on success (no exception raised), NO if an exception was caught.
+ (BOOL)catchException:(void (NS_NOESCAPE ^)(void))tryBlock error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
