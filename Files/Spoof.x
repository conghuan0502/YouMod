#import "Headers.h"
#import <objc/message.h>

%ctor {
    %init;
    dispatch_async(dispatch_get_main_queue(), ^{
        Class cls = NSClassFromString(@"YTIClientInfo");
        if (!cls) {
            YouModLogWarn(@"Spoof: YTIClientInfo not found");
            return;
        }

        SEL sel = @selector(clientVersion);
        Method m = class_getInstanceMethod(cls, sel);
        IMP orig = NULL;

        if (!m) {
            id dummy = ((id(*)(id, SEL))objc_msgSend)((id)cls, sel_registerName("alloc"));
            dummy = ((id(*)(id, SEL))objc_msgSend)(dummy, sel_registerName("init"));
            ((id(*)(id, SEL))objc_msgSend)(dummy, sel);
            m = class_getInstanceMethod(cls, sel);
        }

        if (!m) {
            YouModLogWarn(@"Spoof: clientVersion not resolved");
            return;
        }

        orig = method_getImplementation(m);
        IMP newImp = imp_implementationWithBlock(^NSString*(id _self) {
            if (IS_ENABLED(SpoofClientVersion)) {
                return @"21.20.4";
            }
            return ((NSString*(*)(id, SEL))orig)(_self, sel);
        });

        method_setImplementation(m, newImp);
        YouModLogInfo(@"Spoof: clientVersion -> 21.20.4");
    });
}
