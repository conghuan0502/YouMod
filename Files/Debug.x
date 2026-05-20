#import "Headers.h"

#define MAX_LOG_ENTRIES 200

static NSMutableArray *YouModLogs;
static NSString *YouModLogPath(void) {
    static NSString *path;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        path = [docs stringByAppendingPathComponent:@"YouModDebug.log"];
    });
    return path;
}

static void YouModWriteLog(NSString *msg) {
    if (!YouModLogs) YouModLogs = [NSMutableArray array];
    [YouModLogs addObject:msg];
    if (YouModLogs.count > MAX_LOG_ENTRIES)
        [YouModLogs removeObjectsInRange:NSMakeRange(0, YouModLogs.count - MAX_LOG_ENTRIES)];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:YouModLogPath()];
        if (!fh) {
            [line writeToFile:YouModLogPath() atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            [fh seekToEndOfFile];
            [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fh closeFile];
        }
    });
}

NSString *YouModGetDebugLogs(void) {
    NSString *fileLogs = [NSString stringWithContentsOfFile:YouModLogPath() encoding:NSUTF8StringEncoding error:nil];
    if (fileLogs.length) return fileLogs;
    if (YouModLogs.count) return [YouModLogs componentsJoinedByString:@"\n"];
    return @"(no logs)";
}

void YouModClearDebugLogs(void) {
    [[NSFileManager defaultManager] removeItemAtPath:YouModLogPath() error:nil];
    [YouModLogs removeAllObjects];
}

static void YouModDebugLog(NSString *msg) {
    if (!IS_ENABLED(DebugMode)) return;
    NSLog(@"[YouMod Debug] %@", msg);
    YouModWriteLog(msg);
}

static void YouModDebugToast(NSString *msg) {
    if (!IS_ENABLED(DebugMode)) return;
    YouModDebugLog(msg);
    Class toastClass = %c(YTToastResponderEvent);
    if (toastClass) {
        id event = [toastClass eventWithMessage:[@"⚠️ Debug: " stringByAppendingString:msg] firstResponder:nil];
        if (event) [event send];
    }
}

%hook YTIPlayabilityStatus
- (BOOL)isPlayable {
    BOOL playable = %orig;
    if (!playable && IS_ENABLED(DebugMode)) {
        id s = self;
        int status = 0;
        NSString *reason = nil;
        long long errorCode = 0;
        if ([s respondsToSelector:@selector(status)])
            status = (int)(NSInteger)[s performSelector:@selector(status)];
        if ([s respondsToSelector:@selector(reason)])
            reason = [s performSelector:@selector(reason)];
        if ([s respondsToSelector:@selector(errorCode)])
            errorCode = (long long)(NSInteger)[s performSelector:@selector(errorCode)];
        YouModDebugToast([NSString stringWithFormat:@"isPlayable=NO status=%d reason=%@ errorCode=%lld", status, reason ?: @"nil", errorCode]);
    }
    return playable;
}
%end

%hook YTPlayerResponse
- (id)playabilityStatus {
    id status = %orig;
    if (IS_ENABLED(DebugMode) && status) {
        BOOL playable = YES;
        if ([status respondsToSelector:@selector(isPlayable)])
            playable = (BOOL)(NSInteger)[status performSelector:@selector(isPlayable)];
        if (!playable) {
            NSString *reason = nil;
            NSString *subreason = nil;
            if ([status respondsToSelector:@selector(reason)])
                reason = [status performSelector:@selector(reason)];
            if ([status respondsToSelector:@selector(subReason)])
                subreason = [status performSelector:@selector(subReason)];
            YouModDebugToast([NSString stringWithFormat:@"PlayerResponse: not playable reason=%@ subreason=%@", reason ?: @"nil", subreason ?: @"nil"]);
        }
    }
    return status;
}
%end

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert {
    if (IS_ENABLED(DebugMode)) YouModDebugToast(@"Something went wrong - confirm alert");
    %orig;
}
- (void)showError {
    if (IS_ENABLED(DebugMode)) YouModDebugToast(@"Playability error displayed");
    %orig;
}
%end

%hook YTPlayabilityResolutionUserActionUIControllerImpl
- (void)showConfirmAlert {
    if (IS_ENABLED(DebugMode)) YouModDebugToast(@"Something went wrong - confirm alert");
    %orig;
}
- (void)showError {
    if (IS_ENABLED(DebugMode)) YouModDebugToast(@"Playability error displayed");
    %orig;
}
%end

%hook YTPlaybackData
- (id)initWithCoder:(NSCoder *)coder {
    self = %orig;
    if (IS_ENABLED(DebugMode) && self) {
        YouModDebugLog([NSString stringWithFormat:@"PlaybackData loaded: %@", self]);
    }
    return self;
}
%end
