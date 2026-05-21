#import "Headers.h"

Class YTILikeResponseClass, YTIDislikeResponseClass, YTIRemoveLikeResponseClass;

// Background playback
%group BackgroundPlayback
%hook YTIBackgroundOfflineSettingCategoryEntryRenderer
%new(B@:)
- (BOOL)isBackgroundEnabled { return YES; }
%end
%end

%hook MLVideo
- (BOOL)playableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
%end

%hook YTIPlayabilityStatus
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
- (BOOL)isPlayable { return YES; }
- (BOOL)isPlayableNowOrAfterUserAction { return YES; }
%end

%hook YTPlaybackData
- (BOOL)isPlayableInBackground { return IS_ENABLED(BackgroundPlayback) ? YES : %orig; }
- (BOOL)isPlayable { return YES; }
%end

// Hook InnerTube request to see if streaming data is fetched
%hook YTInnerTubeResponseWrapper
- (id)initWithResponse:(id)response cacheContext:(id)arg2 requestStatistics:(id)arg3 mutableSharedData:(id)arg4 {
    NSString *cls = response ? NSStringFromClass([response class]) : @"nil";
    if (![cls isEqualToString:@"YTIEventLoggingResponse"] && ![cls isEqualToString:@"YTIAttestationChallengeResponse"]) {
        YouModLogInfo([NSString stringWithFormat:@"InnerTube response: %@", cls]);
    }
    return %orig;
}
%end

%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSArray *classesToCheck = @[
            @"YTPlayerResponse",
            @"YTIPlayerResponse",
            @"YTPlaybackData",
            @"YTIPlayabilityStatus",
            @"YTIPlayabilityStatusEnum",
            @"YTInnerTubeResponseWrapper",
            @"YTPlayabilityResolutionUserActionUIController",
            @"YTPlayabilityResolutionUserActionUIControllerImpl",
            @"YTPlayabilityResolutionOverlayViewControllerImpl"
        ];
        for (NSString *clsName in classesToCheck) {
            Class cls = NSClassFromString(clsName);
            YouModLogInfo([NSString stringWithFormat:@"Class check: %@ = %@", clsName, cls ? @"EXISTS" : @"MISSING"]);
            if (cls) {
                unsigned int count;
                Method *methods = class_copyMethodList(cls, &count);
                if (methods) {
                    for (unsigned int i = 0; i < count && i < 20; i++) {
                        SEL sel = method_getName(methods[i]);
                        YouModLogInfo([NSString stringWithFormat:@"  Method: %@", NSStringFromSelector(sel)]);
                    }
                    free(methods);
                }
            }
        }
        
        Class ytpr = NSClassFromString(@"YTPlayerResponse");
        if (ytpr) {
            id dummy = [[ytpr alloc] init];
            SEL sel = NSSelectorFromString(@"playabilityStatus");
            if ([dummy respondsToSelector:sel]) {
                ((id(*)(id, SEL))objc_msgSend)(dummy, sel);
            }
        }
    });
}

// Block error overlay
%hook YTPlayabilityResolutionOverlayViewControllerImpl
- (void)showError {
    if (IS_ENABLED(DebugMode)) YouModLogWarn(@"Blocking error overlay");
}
%end

// Auto-confirm resolution
%hook YTPlayabilityResolutionUserActionUIControllerImpl
- (void)showConfirmAlert {
    if (IS_ENABLED(DebugMode)) YouModLogWarn(@"Auto-confirming");
    [self confirmAlertDidPressConfirm];
}
%end

%hook YTPlayabilityResolutionUserActionUIController
- (void)showConfirmAlert {
    if (IS_ENABLED(DebugMode)) YouModLogWarn(@"Auto-confirming legacy");
    [self confirmAlertDidPressConfirm];
}
%end

// Try to disable Shorts PiP
%hook YTColdConfig
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPicture { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureIos { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTHotConfig
- (BOOL)shortsPlayerGlobalConfigEnableReelsPictureInPictureAllowedFromPlayer { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelModel
- (BOOL)isPiPSupported { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelPlayerViewController
- (BOOL)isPictureInPictureAllowed { return IS_ENABLED(DisablesShortsPiP) ? NO : %orig; }
%end

%hook YTReelWatchRootViewController
- (void)switchToPictureInPicture { if (!IS_ENABLED(DisablesShortsPiP)) %orig; }
%end

// Block upgrade dialogs
%hook YTGlobalConfig
- (BOOL)shouldBlockUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? YES : %orig; }
- (BOOL)shouldShowUpgradeDialog { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldShowUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
- (BOOL)shouldForceUpgrade { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
%end

// Prevent YouTube from asking "Are you there?"
%hook YTColdConfig
- (BOOL)enableYouthereCommandsOnIos { return IS_ENABLED(BlockUpgradeDialogs) ? NO : %orig; }
%end

%hook YTYouThereController
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

%hook YTYouThereControllerImpl
- (BOOL)shouldShowYouTherePrompt { return IS_ENABLED(HideAreYouThereDialog) ? NO : %orig; }
- (void)showYouTherePrompt { if (!IS_ENABLED(HideAreYouThereDialog)) %orig; }
%end

// Fixes slow miniplayer
%hook YTColdConfig
- (BOOL)enableIosFloatingMiniplayerDoubleTapToResize { return IS_ENABLED(FixesSlowMiniPlayer) ? NO : %orig; }
%end

// Use old miniplayer
%hook YTColdConfig
- (BOOL)enableIosFloatingMiniplayer { return IS_ENABLED(DisablesNewMiniPlayer) ? NO : %orig; }
%end

// Disables Snackbar
%hook GOOHUDManagerInternal
- (id)sharedInstance { return IS_ENABLED(DisablesSnackBar) ? nil : %orig; }
- (void)showMessageMainThread:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)activateOverlay:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
- (void)displayHUDViewForMessage:(id)arg { if (!IS_ENABLED(DisablesSnackBar)) %orig; }
%end

// Hide startup animations
%hook YTColdConfig
- (BOOL)mainAppCoreClientIosEnableStartupAnimation { return IS_ENABLED(HideStartupAni) ? NO : %orig; }
%end

// Remove "Play next in queue" from the menu
%hook YTMenuItemVisibilityHandler
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (renderer.icon.iconType == 251 && IS_ENABLED(HidePlayInNextQueue)) {
        return NO;
    } return %orig;
}
%end

%hook YTMenuItemVisibilityHandlerImpl
- (BOOL)shouldShowServiceItemRenderer:(YTIMenuConditionalServiceItemRenderer *)renderer {
    if (renderer.icon.iconType == 251 && IS_ENABLED(HidePlayInNextQueue)) {
        return NO;
    } return %orig;
}
%end

// YTSlientVote
%group SlientVote
%hook YTInnerTubeResponseWrapper
- (id)initWithResponse:(id)response cacheContext:(id)arg2 requestStatistics:(id)arg3 mutableSharedData:(id)arg4 {
    if ([response isKindOfClass:YTILikeResponseClass]
        || [response isKindOfClass:YTIDislikeResponseClass]
        || [response isKindOfClass:YTIRemoveLikeResponseClass]) return nil;
    return %orig;
}
%end
%end

%ctor {
    YTILikeResponseClass = %c(YTILikeResponse);
    YTIDislikeResponseClass = %c(YTIDislikeResponse);
    YTIRemoveLikeResponseClass = %c(YTIRemoveLikeResponse);
    %init;
    if (IS_ENABLED(HideLikeDislikeVotes)) {
        %init(SlientVote);
    }
    if (IS_ENABLED(BackgroundPlayback)) {
        %init(BackgroundPlayback);
    }
}
