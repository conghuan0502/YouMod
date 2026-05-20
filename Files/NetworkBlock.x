#import "Headers.h"

@interface _YouModBlockedURLProtocol : NSURLProtocol
@end

static NSArray *blockedDomains;

@implementation _YouModBlockedURLProtocol

+ (void)initialize {
    if (self == [_YouModBlockedURLProtocol class]) {
        blockedDomains = @[
            @"play.googleapis.com",
            @"s.youtube.com"
        ];
    }
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    NSString *host = request.URL.host.lowercaseString;
    if (host.length == 0) return NO;
    for (NSString *domain in blockedDomains) {
        if ([host containsString:domain]) {
            return YES;
        }
    }
    return NO;
}

+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {
    return request;
}

- (void)startLoading {
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:@{NSLocalizedDescriptionKey: @"Blocked by YouMod"}];
    [self.client URLProtocol:self didFailWithError:error];
}

- (void)stopLoading {}

@end

%ctor {
    [NSURLProtocol registerClass:[_YouModBlockedURLProtocol class]];
}
