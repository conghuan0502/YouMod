#import "Headers.h"

#define MAX_LOG_ENTRIES 200

// YouModLogLevel enum is defined in Headers.h

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

static NSString *YouModLogLevelString(YouModLogLevel level) {
    switch (level) {
        case YouModLogLevelInfo:  return @"INFO";
        case YouModLogLevelWarn:  return @"WARN";
        case YouModLogLevelError: return @"ERROR";
    }
    return @"INFO";
}

static void YouModWriteLog(YouModLogLevel level, NSString *msg) {
    if (!YouModLogs) YouModLogs = [NSMutableArray array];
    NSString *ts = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
    NSString *entry = [NSString stringWithFormat:@"[%@] [%@] %@", ts, YouModLogLevelString(level), msg];
    [YouModLogs addObject:entry];
    if (YouModLogs.count > MAX_LOG_ENTRIES)
        [YouModLogs removeObjectsInRange:NSMakeRange(0, YouModLogs.count - MAX_LOG_ENTRIES)];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSString *line = [entry stringByAppendingString:@"\n"];
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

NSInteger YouModGetLogCount(void) {
    return YouModLogs.count;
}

void YouModClearDebugLogs(void) {
    [[NSFileManager defaultManager] removeItemAtPath:YouModLogPath() error:nil];
    [YouModLogs removeAllObjects];
}

void YouModLog(YouModLogLevel level, NSString *msg) {
    NSLog(@"[YouMod] [%@] %@", YouModLogLevelString(level), msg);
    YouModWriteLog(level, msg);
}

void YouModLogInfo(NSString *msg) { YouModLog(YouModLogLevelInfo, msg); }
void YouModLogWarn(NSString *msg) { YouModLog(YouModLogLevelWarn, msg); }
void YouModLogError(NSString *msg) { YouModLog(YouModLogLevelError, msg); }

static void YouModToast(NSString *msg) {
    if (!IS_ENABLED(DebugMode)) return;
    Class toastClass = %c(YTToastResponderEvent);
    if (toastClass) {
        id event = [toastClass eventWithMessage:[@"⚠️ " stringByAppendingString:msg] firstResponder:nil];
        if (event) [event send];
    }
}

%ctor {
    YouModLogInfo(@"YouMod debug initialized");
}

%hook YTIPlayabilityStatus
- (BOOL)isPlayable {
    BOOL playable = %orig;
    if (!playable) {
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
        YouModLogWarn([NSString stringWithFormat:@"isPlayable=NO status=%d reason=%@ errorCode=%lld", status, reason ?: @"nil", errorCode]);
        if (IS_ENABLED(DebugMode))
            YouModToast([NSString stringWithFormat:@"Playability: status=%d %@", status, reason ?: @""]);
    }
    return playable;
}
%end

%hook YTPlayerResponse
- (id)playabilityStatus {
    id status = %orig;
    if (status) {
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
            YouModLogWarn([NSString stringWithFormat:@"PlayerResponse not playable reason=%@ subreason=%@", reason ?: @"nil", subreason ?: @"nil"]);
        }
        if (IS_ENABLED(DebugMode)) {
            YouModLogInfo([NSString stringWithFormat:@"PlayerResponse loaded (playable=%d)", playable]);
        }
    }
    return status;
}
%end

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert {
    YouModLogError(@"Something went wrong - confirm alert shown");
    if (IS_ENABLED(DebugMode)) YouModToast(@"Something went wrong - confirm alert");
    %orig;
}
- (void)showError {
    YouModLogError(@"Playability error view displayed");
    if (IS_ENABLED(DebugMode)) YouModToast(@"Playability error view");
    %orig;
}
%end

%hook YTPlayabilityResolutionUserActionUIControllerImpl
- (void)showConfirmAlert {
    YouModLogError(@"Something went wrong - confirm alert shown");
    if (IS_ENABLED(DebugMode)) YouModToast(@"Something went wrong - confirm alert");
    %orig;
}
- (void)showError {
    YouModLogError(@"Playability error view displayed");
    if (IS_ENABLED(DebugMode)) YouModToast(@"Playability error view");
    %orig;
}
%end

%hook YTPlaybackData
- (id)initWithCoder:(NSCoder *)coder {
    self = %orig;
    if (self) {
        YouModLogInfo(@"PlaybackData loaded");
    }
    return self;
}
%end

@implementation UIViewController (YouModDebug)
- (void)YouModShareLogs {
    NSString *logs = YouModGetDebugLogs();
    if (![logs isEqual:@"(no logs)"]) {
        NSURL *fileURL = [NSURL fileURLWithPath:YouModLogPath()];
        UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
        [self presentViewController:activity animated:YES completion:nil];
    }
}
@end

#pragma mark - Network Logging

@interface _YouModLoggingURLProtocol : NSURLProtocol
@property (nonatomic, strong) NSURLSessionDataTask *task;
@property (nonatomic, copy) NSString *requestURL;
@property (nonatomic, copy) NSString *requestMethod;
@end

@implementation _YouModLoggingURLProtocol

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!IS_ENABLED(NetworkLogging)) return NO;
    if ([NSURLProtocol propertyForKey:@"YouModLogged" inRequest:request]) return NO;
    NSString *scheme = request.URL.scheme.lowercaseString;
    return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    self.requestURL = self.request.URL.absoluteString;
    self.requestMethod = self.request.HTTPMethod ?: @"GET";
    YouModLogInfo([NSString stringWithFormat:@"🌐 REQ %@ %@", self.requestMethod, self.requestURL]);

    NSMutableURLRequest *newReq = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"YouModLogged" inRequest:newReq];

    __weak typeof(self) weakSelf = self;
    self.task = [[NSURLSession sharedSession] dataTaskWithRequest:newReq completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                [strongSelf.client URLProtocol:strongSelf didFailWithError:error];
                YouModLogWarn([NSString stringWithFormat:@"🌐 ERR %@ - %@", strongSelf.requestURL, error.localizedDescription]);
            } else {
                [strongSelf.client URLProtocol:strongSelf didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
                [strongSelf.client URLProtocol:strongSelf didLoadData:data];
                [strongSelf.client URLProtocolDidFinishLoading:strongSelf];
                long statusCode = 0;
                if ([response isKindOfClass:[NSHTTPURLResponse class]])
                    statusCode = ((NSHTTPURLResponse *)response).statusCode;
                YouModLogInfo([NSString stringWithFormat:@"🌐 RSP %ld %@ (%lld bytes)", statusCode, strongSelf.requestURL, (long long)data.length]);
            }
        });
    }];
    [self.task resume];
}

- (void)stopLoading {
    [self.task cancel];
}

@end

%ctor {
    [NSURLProtocol registerClass:[_YouModLoggingURLProtocol class]];
}

%hook YTPlayerViewController
- (void)loadWithPlayerTransition:(id)arg1 playbackConfig:(id)arg2 {
    %orig;
    NSString *videoID = [self valueForKey:@"_contentVideoID"];
    if (videoID) {
        YouModLogInfo([NSString stringWithFormat:@"Playing video: %@", videoID]);
    }
}
%end

%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (!text) return;
    if ([text containsString:@"Something went wrong"] || [text containsString:@"Tap to retry"]) {
        YouModLogWarn([NSString stringWithFormat:@"🚨 Error UI shown: \"%@\"", text]);
        if (IS_ENABLED(DebugMode)) YouModToast(@"🚨 Something went wrong detected!");
    }
    if ([text containsString:@"No internet"] || [text containsString:@"Check connection"]) {
        YouModLogWarn([NSString stringWithFormat:@"🚨 Network error UI: \"%@\"", text]);
    }
}
%end


