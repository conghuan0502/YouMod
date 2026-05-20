#import "Headers.h"
#import <substrate.h>
#import <netdb.h>

static NSArray *blockedDomains;
static int (*orig_getaddrinfo)(const char *, const char *, const struct addrinfo *, struct addrinfo **);

static int hooked_getaddrinfo(const char *nodename, const char *servname, const struct addrinfo *hints, struct addrinfo **res) {
    if (nodename) {
        NSString *host = [NSString stringWithUTF8String:nodename];
        for (NSString *domain in blockedDomains) {
            if ([host containsString:domain]) {
                return EAI_NONAME;
            }
        }
    }
    return orig_getaddrinfo(nodename, servname, hints, res);
}

%ctor {
    blockedDomains = @[
        @"iosantiabuse-pa.googleapis.com",
        @"play.googleapis.com",
        @"clients3.googleapis.com",
        @"s.youtube.com"
    ];
    MSHookFunction((void *)&getaddrinfo, (void *)&hooked_getaddrinfo, (void **)&orig_getaddrinfo);
}
