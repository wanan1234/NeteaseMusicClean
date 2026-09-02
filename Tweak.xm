// =============================================================
//  NeteaseMusicClean — 网易云音乐净化插件（诊断版）
//  改用三指长按（规避手势拦截）
// =============================================================
#import <UIKit/UIKit.h>
#import <substrate.h>
#import <stdarg.h>

// ---------- 日志工具 ----------
static void WriteLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"NeteaseMusic.log"];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:documentsDirectory]) {
        [fm createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", timestamp, msg];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (!fh) {
        [line writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"[NeteaseMusic-Diag] %@", msg);
}

// ---------- 诊断：递归打印视图层级 ----------
static void dumpViewHierarchy(UIView *view, NSInteger depth, NSMutableString *output) {
    if (!view) return;
    NSMutableString *indent = [NSMutableString string];
    for (NSInteger i = 0; i < depth; i++) [indent appendString:@"  "];

    NSString *className = NSStringFromClass([view class]);
    NSString *frame = NSStringFromCGRect(view.frame);
    NSString *hidden = view.hidden ? @"YES" : @"NO";
    NSString *alpha = [NSString stringWithFormat:@"%.2f", view.alpha];
    NSString *tag = [NSString stringWithFormat:@"%ld", (long)view.tag];
    NSString *a11y = view.accessibilityLabel ?: @"(无)";

    [output appendFormat:@"%@[%@] frame=%@ hidden=%@ alpha=%@ tag=%@ a11y=%@\n",
     indent, className, frame, hidden, alpha, tag, a11y];

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        [output appendFormat:@"%@  TEXT: \"%@\"\n", indent, label.text ?: @"(空)"];
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *btn = (UIButton *)view;
        [output appendFormat:@"%@  BUTTON title: \"%@\"\n", indent, [btn titleForState:UIControlStateNormal] ?: @"(无)"];
    }
    if ([view isKindOfClass:[UITabBar class]]) {
        UITabBar *tabBar = (UITabBar *)view;
        [output appendFormat:@"%@  TABBAR items count: %lu\n", indent, (unsigned long)tabBar.items.count];
        for (UITabBarItem *item in tabBar.items) {
            [output appendFormat:@"%@    item: %@\n", indent, item.title ?: @"(无)"];
        }
    }

    for (UIView *sub in view.subviews) {
        dumpViewHierarchy(sub, depth + 1, output);
    }
}

// ---------- 诊断主函数 ----------
static void diagnoseNeteaseMusic(UIViewController *vc) {
    if (!vc) return;
    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"\n===== 诊断网易云音乐视图层级 =====\n"];
    [output appendFormat:@"控制器类: %@\n", NSStringFromClass([vc class])];
    [output appendFormat:@"view frame: %@\n", NSStringFromCGRect(vc.view.frame)];
    dumpViewHierarchy(vc.view, 0, output);
    [output appendString:@"===== 诊断结束 =====\n"];
    WriteLog(@"%@", output);
}

// ---------- 查找主 TabBarController ----------
static void diagnoseTabBarController(UIViewController *root) {
    if (!root) return;

    UITabBarController *tabController = nil;
    if ([root isKindOfClass:[UITabBarController class]]) {
        tabController = (UITabBarController *)root;
    } else {
        for (UIViewController *child in root.childViewControllers) {
            if ([child isKindOfClass:[UITabBarController class]]) {
                tabController = (UITabBarController *)child;
                break;
            }
        }
    }

    if (!tabController) {
        WriteLog(@"未找到 UITabBarController");
        return;
    }

    NSMutableString *output = [NSMutableString string];
    [output appendFormat:@"\n===== TabBarController 诊断 =====\n"];
    [output appendFormat:@"类名: %@\n", NSStringFromClass([tabController class])];
    [output appendFormat:@"viewControllers count: %lu\n", (unsigned long)tabController.viewControllers.count];
    for (NSInteger i = 0; i < tabController.viewControllers.count; i++) {
        UIViewController *vc = tabController.viewControllers[i];
        [output appendFormat:@"  [%ld] %@ - %@\n", (long)i, vc.tabBarItem.title ?: @"(无)", NSStringFromClass([vc class])];
    }

    [output appendFormat:@"\ntabBar 子视图:\n"];
    for (UIView *sub in tabController.tabBar.subviews) {
        [output appendFormat:@"  %@ frame=%@\n", NSStringFromClass([sub class]), NSStringFromCGRect(sub.frame)];
    }

    WriteLog(@"%@", output);
    WriteLog(@"TabBarController 诊断完成");
}

// =============================================================
// 双指双击菜单
// =============================================================
static void showToast(NSString *msg, UIWindow *window) {
    UIViewController *top = window.rootViewController;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *toast = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
    [top presentViewController:toast animated:YES completion:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [toast dismissViewControllerAnimated:YES completion:nil];
    });
}

static void showSettingsMenu(UIWindow *window) {
    WriteLog(@"showSettingsMenu called");
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"网易云音乐诊断"
                                                                   message:@"点击查看日志"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:@"查看日志" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths firstObject];
        NSString *logPath = [documentsDirectory stringByAppendingPathComponent:@"NeteaseMusic.log"];
        NSString *logContent = [NSString stringWithContentsOfFile:logPath encoding:NSUTF8StringEncoding error:nil];
        if (!logContent) logContent = @"日志文件不存在或为空";
        UIAlertController *logAlert = [UIAlertController alertControllerWithTitle:@"诊断日志" message:logContent preferredStyle:UIAlertControllerStyleAlert];
        [logAlert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleDefault handler:nil]];
        UIViewController *top = window.rootViewController;
        while (top.presentedViewController) top = top.presentedViewController;
        [top presentViewController:logAlert animated:YES completion:nil];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [topVC presentViewController:alert animated:YES completion:nil];
}

// =============================================================
// Hook UIWindow：三指长按（更可靠，不易被拦截）
// =============================================================
%hook UIWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    if (self) {
        // 三指长按手势（1.2 秒）
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(nm_handleLongPress:)];
        gesture.numberOfTouchesRequired = 3;
        gesture.minimumPressDuration = 1.2;
        gesture.allowableMovement = 30;
        gesture.cancelsTouchesInView = NO;
        [self addGestureRecognizer:gesture];
        WriteLog(@"三指长按手势已添加");
    }
    return self;
}

%new
- (void)nm_handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    WriteLog(@"三指长按触发");

    // 触觉反馈
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare];
        [generator impactOccurred];
    }

    // 屏幕闪白视觉反馈
    UIView *flashView = [[UIView alloc] initWithFrame:self.bounds];
    flashView.backgroundColor = [UIColor whiteColor];
    flashView.alpha = 0.15;
    flashView.userInteractionEnabled = NO;
    [self addSubview:flashView];
    [UIView animateWithDuration:0.3 animations:^{
        flashView.alpha = 0;
    } completion:^(BOOL finished) {
        [flashView removeFromSuperview];
    }];

    showSettingsMenu(self);
}

%end

// =============================================================
// Hook 主控制器
// =============================================================
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            WriteLog(@"========================================");
            WriteLog(@"网易云音乐诊断版加载");
            WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
            WriteLog(@"========================================");

            UIWindow *window = [UIApplication sharedApplication].windows.firstObject;
            if (window && window.rootViewController) {
                diagnoseTabBarController(window.rootViewController);
                diagnoseNeteaseMusic(window.rootViewController);
            }
        });
    });
}

%end

// =============================================================
// 构造函数
// =============================================================
%ctor {
    WriteLog(@"========================================");
    WriteLog(@"NeteaseMusicClean 诊断版加载");
    WriteLog(@"Bundle ID: %@", [[NSBundle mainBundle] bundleIdentifier]);
    WriteLog(@"========================================");
}
