#import "Headers.h"

@interface _YouModBlockedURLProtocol : NSURLProtocol
@end

static NSArray *blockedDomains;

@implementation _YouModBlockedURLProtocol

+ (void)initialize {
    if (self == [_YouModBlockedURLProtocol class]) {
        blockedDomains = @[
            @"iosantiabuse-pa.googleapis.com",
            @"play.googleapis.com",
            @"clients3.googleapis.com",
            @"s.youtube.com"
        ];
    }
}

+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if ([NSURLProtocol propertyForKey:@"YouModBlocked" inRequest:request]) {
        return NO;
    }
    NSString *host = request.URL.host.lowercaseString;
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
    NSMutableURLRequest *request = [self.request mutableCopy];
    [NSURLProtocol setProperty:@YES forKey:@"YouModBlocked" inRequest:request];
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotConnectToHost userInfo:nil];
    [self.client URLProtocol:self didFailWithError:error];
}

- (void)stopLoading {}

@end

%ctor {
    [NSURLProtocol registerClass:[_YouModBlockedURLProtocol class]];
}
