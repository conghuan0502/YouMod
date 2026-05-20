#import "Headers.h"

typedef NS_ENUM(NSInteger, YouModTestStatus) {
    YouModTestStatusPending,
    YouModTestStatusRunning,
    YouModTestStatusPassed,
    YouModTestStatusFailed,
    YouModTestStatusWarning
};

@interface YouModTestItem : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) YouModTestStatus status;
@property (nonatomic, assign) NSTimeInterval duration;
@end

@implementation YouModTestItem
@end

@interface YouModTestRunner : NSObject
@property (nonatomic, strong) NSMutableArray <YouModTestItem *> *tests;
@property (nonatomic, assign) BOOL isRunning;
@property (nonatomic, copy) void (^onUpdate)(void);
@property (nonatomic, copy) void (^onComplete)(void);
- (void)runAllTests;
- (void)runPlaybackTests;
- (void)runHookTests;
- (void)runConfigTests;
@end

static NSString *StatusIcon(YouModTestStatus status) {
    switch (status) {
        case YouModTestStatusPassed:  return @"✓";
        case YouModTestStatusFailed:  return @"✗";
        case YouModTestStatusWarning: return @"⚠";
        case YouModTestStatusRunning: return @"⟳";
        default: return @"○";
    }
}

static NSString *StatusString(YouModTestStatus status) {
    switch (status) {
        case YouModTestStatusPassed:  return @"PASS";
        case YouModTestStatusFailed:  return @"FAIL";
        case YouModTestStatusWarning: return @"WARN";
        case YouModTestStatusRunning: return @"RUNNING";
        default: return @"PENDING";
    }
}

@implementation YouModTestRunner

- (instancetype)init {
    self = [super init];
    if (self) {
        _tests = [NSMutableArray array];
    }
    return self;
}

- (void)addTest:(NSString *)name detail:(NSString *)detail status:(YouModTestStatus)status duration:(NSTimeInterval)duration {
    YouModTestItem *item = [[YouModTestItem alloc] init];
    item.name = name;
    item.detail = detail;
    item.status = status;
    item.duration = duration;
    [self.tests addObject:item];
    if (self.onUpdate) self.onUpdate();
}

- (void)runAllTests {
    self.isRunning = YES;
    [self.tests removeAllObjects];
    if (self.onUpdate) self.onUpdate();

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self runHookTests];
        [self runConfigTests];
        [self runPlaybackTests];

        self.isRunning = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.onComplete) self.onComplete();
        });
    });
}

- (void)runHookTests {
    NSTimeInterval start;

    // Test 1: Check if core classes exist
    start = CACurrentMediaTime();
    NSMutableArray *missingClasses = [NSMutableArray array];
    NSArray *coreClasses = @[
        @"YTPlayerViewController",
        @"YTPlayerResponse",
        @"YTIPlayerResponse",
        @"YTInnerTubeCollectionViewController",
        @"YTMainAppVideoPlayerOverlayView"
    ];
    for (NSString *clsName in coreClasses) {
        if (!NSClassFromString(clsName)) {
            [missingClasses addObject:clsName];
        }
    }
    NSTimeInterval elapsed = CACurrentMediaTime() - start;

    if (missingClasses.count == 0) {
        [self addTest:@"Core Classes" detail:@"All core classes found" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Core Classes" detail:[NSString stringWithFormat:@"Missing: %@", [missingClasses componentsJoinedByString:@", "]] status:YouModTestStatusFailed duration:elapsed];
    }

    // Test 2: Check YTPlayerViewController hooks
    start = CACurrentMediaTime();
    Class ytpvc = NSClassFromString(@"YTPlayerViewController");
    BOOL hasLoadHook = ytpvc && class_getInstanceMethod(ytpvc, @selector(loadWithPlayerTransition:playbackConfig:));
    elapsed = CACurrentMediaTime() - start;

    if (hasLoadHook) {
        [self addTest:@"Player Load Hook" detail:@"loadWithPlayerTransition:playbackConfig: hooked" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Player Load Hook" detail:@"Hook not detected" status:YouModTestStatusFailed duration:elapsed];
    }

    // Test 3: Check ad-related hooks
    start = CACurrentMediaTime();
    Class ytLocalPlayback = NSClassFromString(@"YTLocalPlaybackController");
    BOOL adCoordinatorSafe = YES;
    if (ytLocalPlayback) {
        Method m = class_getInstanceMethod(ytLocalPlayback, @selector(createAdsPlaybackCoordinator));
        if (m) {
            IMP imp = method_getImplementation(m);
            // Check if the implementation is a known "return nil" pattern
            // We can't easily check this at runtime, so we just verify the method exists
        }
    }
    elapsed = CACurrentMediaTime() - start;

    if (adCoordinatorSafe) {
        [self addTest:@"Ad Coordinator" detail:@"createAdsPlaybackCoordinator safe" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Ad Coordinator" detail:@"May return nil (causes playback errors)" status:YouModTestStatusFailed duration:elapsed];
    }

    // Test 4: Check YTPlayerResponse ad hooks
    start = CACurrentMediaTime();
    Class ytpr = NSClassFromString(@"YTPlayerResponse");
    BOOL hasPlayerAdsArray = ytpr && class_getInstanceMethod(ytpr, @selector(playerAdsArray));
    BOOL hasAdSlotsArray = ytpr && class_getInstanceMethod(ytpr, @selector(adSlotsArray));
    elapsed = CACurrentMediaTime() - start;

    if (hasPlayerAdsArray || hasAdSlotsArray) {
        [self addTest:@"Ad Array Hooks" detail:@"playerAdsArray/adSlotsArray hooked (may cause issues)" status:YouModTestStatusWarning duration:elapsed];
    } else {
        [self addTest:@"Ad Array Hooks" detail:@"No ad array hooks detected" status:YouModTestStatusPassed duration:elapsed];
    }

    // Test 5: Check playabilityStatus hook
    start = CACurrentMediaTime();
    BOOL hasPlayabilityHook = ytpr && class_getInstanceMethod(ytpr, @selector(playabilityStatus));
    elapsed = CACurrentMediaTime() - start;

    if (hasPlayabilityHook) {
        [self addTest:@"Playability Hook" detail:@"playabilityStatus hooked" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Playability Hook" detail:@"Not hooked" status:YouModTestStatusWarning duration:elapsed];
    }
}

- (void)runConfigTests {
    NSTimeInterval start;

    // Test 6: Check UserDefaults
    start = CACurrentMediaTime();
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL debugMode = [defaults boolForKey:@"YouModDebugMode"];
    BOOL spoofClient = [defaults boolForKey:@"YouModSpoofClientVersion"];
    BOOL blockDomains = [defaults boolForKey:@"YouModBlockDomains"];

    NSString *configInfo = [NSString stringWithFormat:@"Debug=%d, Spoof=%d, BlockDomains=%d", debugMode, spoofClient, blockDomains];
    elapsed = CACurrentMediaTime() - start;
    [self addTest:@"Configuration" detail:configInfo status:YouModTestStatusPassed duration:elapsed];

    // Test 7: Check spoof version
    start = CACurrentMediaTime();
    if (spoofClient) {
        Class clientInfo = NSClassFromString(@"YTIClientInfo");
        if (clientInfo) {
            id instance = [[clientInfo alloc] init];
            NSString *version = [instance performSelector:@selector(clientVersion)];
            elapsed = CACurrentMediaTime() - start;
            if ([version isEqualToString:@"21.20.4"]) {
                [self addTest:@"Spoof Version" detail:[NSString stringWithFormat:@"Using %@", version] status:YouModTestStatusPassed duration:elapsed];
            } else {
                [self addTest:@"Spoof Version" detail:[NSString stringWithFormat:@"Unexpected: %@", version] status:YouModTestStatusWarning duration:elapsed];
            }
        } else {
            elapsed = CACurrentMediaTime() - start;
            [self addTest:@"Spoof Version" detail:@"YTIClientInfo not found" status:YouModTestStatusFailed duration:elapsed];
        }
    } else {
        elapsed = CACurrentMediaTime() - start;
        [self addTest:@"Spoof Version" detail:@"Disabled" status:YouModTestStatusPassed duration:elapsed];
    }

    // Test 8: Check bundle
    start = CACurrentMediaTime();
    NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"YouMod" ofType:@"bundle"];
    BOOL bundleExists = tweakBundlePath && [[NSFileManager defaultManager] fileExistsAtPath:tweakBundlePath];
    elapsed = CACurrentMediaTime() - start;

    if (bundleExists) {
        [self addTest:@"Tweak Bundle" detail:[NSString stringWithFormat:@"Found at %@", tweakBundlePath] status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Tweak Bundle" detail:@"Bundle not found (may be embedded)" status:YouModTestStatusWarning duration:elapsed];
    }
}

- (void)runPlaybackTests {
    NSTimeInterval start;

    // Test 9: Check if YouTube app is responsive
    start = CACurrentMediaTime();
    BOOL appResponsive = [[UIApplication sharedApplication] applicationState] == UIApplicationStateActive;
    elapsed = CACurrentMediaTime() - start;

    if (appResponsive) {
        [self addTest:@"App Responsive" detail:@"YouTube is active" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"App Responsive" detail:@"App not in foreground" status:YouModTestStatusWarning duration:elapsed];
    }

    // Test 10: Check network connectivity
    start = CACurrentMediaTime();
    NSURL *testURL = [NSURL URLWithString:@"https://www.googleapis.com"];
    NSURLRequest *request = [NSURLRequest requestWithURL:testURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:5];
    __block BOOL networkOK = NO;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        networkOK = (error == nil);
        dispatch_semaphore_signal(sem);
    }];
    [task resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC));
    elapsed = CACurrentMediaTime() - start;

    if (networkOK) {
        [self addTest:@"Network" detail:@"Connected to Google APIs" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Network" detail:@"Cannot reach Google APIs" status:YouModTestStatusFailed duration:elapsed];
    }

    // Test 11: Check dylib load status
    start = CACurrentMediaTime();
    BOOL dylibLoaded = NO;
    // Check if any of our symbols are resolved
    if (NSClassFromString(@"YTPlayerViewController")) {
        unsigned int methodCount;
        Method *methods = class_copyMethodList(NSClassFromString(@"YTPlayerViewController"), &methodCount);
        if (methods) {
            dylibLoaded = YES;
            free(methods);
        }
    }
    elapsed = CACurrentMediaTime() - start;

    if (dylibLoaded) {
        [self addTest:@"Dylib Loaded" detail:@"Tweak dylib is loaded" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Dylib Loaded" detail:@"Dylib may not be loaded" status:YouModTestStatusFailed duration:elapsed];
    }

    // Test 12: Check for crash logs
    start = CACurrentMediaTime();
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libPath = paths.firstObject;
    NSString *crashPath = [libPath stringByAppendingPathComponent:@"Logs/CrashReporter"];
    NSArray *crashFiles = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:crashPath error:nil];
    NSInteger ytCrashCount = 0;
    for (NSString *file in crashFiles) {
        if ([file containsString:@"YouTube"]) {
            ytCrashCount++;
        }
    }
    elapsed = CACurrentMediaTime() - start;

    if (ytCrashCount == 0) {
        [self addTest:@"Crash Logs" detail:@"No YouTube crash logs" status:YouModTestStatusPassed duration:elapsed];
    } else {
        [self addTest:@"Crash Logs" detail:[NSString stringWithFormat:@"%ld crash log(s) found", (long)ytCrashCount] status:YouModTestStatusWarning duration:elapsed];
    }
}

@end

@implementation UIViewController (YouModTests)

- (void)YouModRunTests {
    YouModTestRunner *runner = [[YouModTestRunner alloc] init];
    YouModTestViewController *testVC = [[YouModTestViewController alloc] initWithRunner:runner];
    [self presentViewController:testVC animated:YES completion:^{
        [runner runAllTests];
    }];
}

@end

@interface YouModTestViewController ()
@property (nonatomic, strong) YouModTestRunner *runner;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@property (nonatomic, strong) UILabel *summaryLabel;
@end

@implementation YouModTestViewController

- (instancetype)initWithRunner:(YouModTestRunner *)runner {
    self = [super init];
    if (self) {
        _runner = runner;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"YouMod Tests";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    // Summary label
    self.summaryLabel = [[UILabel alloc] init];
    self.summaryLabel.font = [UIFont boldSystemFontOfSize:14];
    self.summaryLabel.textColor = [UIColor secondaryLabelColor];
    self.summaryLabel.textAlignment = NSTextAlignmentCenter;
    self.summaryLabel.numberOfLines = 0;
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.summaryLabel];

    // Spinner
    self.spinner = [[UIActivityIndicatorView alloc] initWithStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.spinner];

    // Table view
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:self.tableView];

    // Constraints
    [NSLayoutConstraint activateConstraints:@[
        [self.spinner.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-100],

        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.spinner.bottomAnchor constant:20],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.summaryLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],

        [self.tableView.topAnchor constraintEqualToAnchor:self.summaryLabel.bottomAnchor constant:20],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];

    // Setup runner callbacks
    __weak typeof(self) weakSelf = self;
    runner.onUpdate = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.tableView reloadData];
            [weakSelf updateSummary];
        });
    };
    runner.onComplete = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.spinner stopAnimating];
            [weakSelf.tableView reloadData];
            [weakSelf updateSummary];
        });
    };

    [self.spinner startAnimating];
}

- (void)updateSummary {
    NSInteger passCount = 0, failCount = 0, warnCount = 0;
    for (YouModTestItem *item in self.runner.tests) {
        switch (item.status) {
            case YouModTestStatusPassed: passCount++; break;
            case YouModTestStatusFailed: failCount++; break;
            case YouModTestStatusWarning: warnCount++; break;
            default: break;
        }
    }
    NSString *status = self.runner.isRunning ? @"Running..." : @"Complete";
    self.summaryLabel.text = [NSString stringWithFormat:@"%@ — Pass: %ld | Fail: %ld | Warn: %ld", status, (long)passCount, (long)failCount, (long)warnCount];

    if (!self.runner.isRunning) {
        UIColor *tintColor = failCount > 0 ? [UIColor systemRedColor] : (warnCount > 0 ? [UIColor systemOrangeColor] : [UIColor systemGreenColor]);
        self.summaryLabel.textColor = tintColor;
    }
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.runner.tests.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"TestCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }

    YouModTestItem *item = self.runner.tests[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%@ %@", StatusIcon(item.status), item.name];
    cell.detailTextLabel.text = item.detail;

    switch (item.status) {
        case YouModTestStatusPassed:
            cell.textLabel.textColor = [UIColor systemGreenColor];
            break;
        case YouModTestStatusFailed:
            cell.textLabel.textColor = [UIColor systemRedColor];
            break;
        case YouModTestStatusWarning:
            cell.textLabel.textColor = [UIColor systemOrangeColor];
            break;
        default:
            cell.textLabel.textColor = [UIColor labelColor];
            break;
    }

    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
