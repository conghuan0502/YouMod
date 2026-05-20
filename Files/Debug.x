#import "Headers.h"

static void YouModDebugLog(NSString *msg) {
    if (!IS_ENABLED(DebugMode)) return;
    NSLog(@"[YouMod Debug] %@", msg);
}

static void YouModDebugToast(NSString *msg) {
    YouModDebugLog(msg);
    if (!IS_ENABLED(DebugMode)) return;
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
            status = (int)[s performSelector:@selector(status)];
        if ([s respondsToSelector:@selector(reason)])
            reason = [s performSelector:@selector(reason)];
        if ([s respondsToSelector:@selector(errorCode)])
            errorCode = (long long)[s performSelector:@selector(errorCode)];
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
            playable = (BOOL)[status performSelector:@selector(isPlayable)];
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
