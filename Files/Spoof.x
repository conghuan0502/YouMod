#import "Headers.h"

static NSString *(*orig_YTIClientInfo_clientVersion)(id, SEL);

static NSString *repl_YTIClientInfo_clientVersion(id self, SEL _cmd) {
    if (IS_ENABLED(SpoofClientVersion)) {
        return @"21.20.4";
    }
    if (orig_YTIClientInfo_clientVersion)
        return orig_YTIClientInfo_clientVersion(self, _cmd);
    return nil;
}

%ctor {
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"YTIClientInfo");
        if (!cls) {
            YouModLogWarn(@"Spoof: YTIClientInfo not found");
            return;
        }
        Method m = class_getInstanceMethod(cls, @selector(clientVersion));
        if (!m) {
            [(id)[[cls alloc] init] clientVersion];
            m = class_getInstanceMethod(cls, @selector(clientVersion));
        }
        if (m) {
            orig_YTIClientInfo_clientVersion = (void *)method_getImplementation(m);
            class_replaceMethod(cls, @selector(clientVersion), (IMP)repl_YTIClientInfo_clientVersion, method_getTypeEncoding(m));
        } else {
            class_addMethod(cls, @selector(clientVersion), (IMP)repl_YTIClientInfo_clientVersion, "@@:");
        }
        YouModLogInfo(@"Spoof: clientVersion hooked -> 21.20.4");
    });
}
