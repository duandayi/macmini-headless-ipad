// vmenu — 菜单栏分辨率切换（点一下就能改 iPad 的分辨率）
// 实现方式：解析 displayplacer list，选中后调用 displayplacer 应用
// 依赖：displayplacer（开源，brew install displayplacer）

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

#ifndef VD_ICON_DY
#define VD_ICON_DY 1.0
#endif

static NSStatusItem *gItem;
static NSString *gDisplayplacer;

static void vlog(NSString *fmt, ...) {
    va_list a; va_start(a, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:a];
    va_end(a);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], m];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vmenu.log"];
    if (!fh) [[NSFileManager defaultManager] createFileAtPath:@"/tmp/vmenu.log" contents:nil attributes:nil];
    fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/vmenu.log"];
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

static NSString *runCmd(NSString *path, NSArray *args) {
    NSTask *t = [NSTask new];
    t.launchPath = path;
    t.arguments = args;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = p;
    @try { [t launch]; [t waitUntilExit]; }
    @catch (NSException *e) { vlog(@"launch 失败 %@: %@", path, e.reason); return @""; }
    NSData *d = [[p fileHandleForReading] readDataToEndOfFile];
    return [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] ?: @"";
}

// 解析 displayplacer list → @[ @{@"id":.., @"title":.., @"current":.., @"modes":@[@{@"w":,@"h":,@"scale":}]} ]
static NSArray *parseDisplays(void) {
    NSString *out = runCmd(@"/bin/bash", @[@"-lc",
        [NSString stringWithFormat:@"%@ list 2>/dev/null", gDisplayplacer]]);
    NSMutableArray *displays = [NSMutableArray array];
    NSMutableDictionary *cur = nil;
    for (NSString *raw in [out componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line hasPrefix:@"Persistent screen id:"]) {
            if (cur) [displays addObject:cur];
            NSString *sid = [[line substringFromIndex:21]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            cur = [@{ @"id": sid,
                      @"modes": [NSMutableArray array] } mutableCopy];
        } else if (cur) {
            if ([line hasPrefix:@"Resolution:"]) {
                cur[@"res"] = [[line substringFromIndex:11] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            } else if ([line hasPrefix:@"Type:"]) {
                cur[@"type"] = [line substringFromIndex:5];
            } else if ([line hasPrefix:@"mode "]) {
                // mode 14: res:1180x820 hz:60 color_depth:4 scaling:on
                NSArray *parts = [line componentsSeparatedByString:@" "];
                NSString *res = nil; BOOL scale = NO;
                for (NSString *p in parts) {
                    if ([p hasPrefix:@"res:"]) res = [p substringFromIndex:4];
                    if ([p hasPrefix:@"scaling:on"]) scale = YES;
                }
                if (res) {
                    NSArray *wh = [res componentsSeparatedByString:@"x"];
                    if (wh.count == 2)
                        [(NSMutableArray *)cur[@"modes"] addObject:@{@"w": wh[0], @"h": wh[1], @"scale": @(scale)}];
                }
            } else if ([line hasPrefix:@"Scaling:"]) {
                cur[@"curScale"] = [[line substringFromIndex:8] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            }
        }
    }
    if (cur) [displays addObject:cur];
    return displays;
}


// ── 彩色经典 Mac 图标 ───────────────────────────────────────────────
// 位图内嵌（72×64 @4x，原始 18×16pt），按参考图比例与实测配色绘制
static NSImage *makeColorIcon(CGFloat scale) {
    static NSString *b64 = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        b64 = @"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";
    });
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    if (!data) return nil;
    NSImage *img = [[NSImage alloc] initWithData:data];
    [img setSize:NSMakeSize(18, 16)];
    return img;
}


// 读取第一块屏的当前逻辑分辨率（形如 @"1180x820"）
static NSString *currentLogical(void) {
    NSString *out = runCmd(@"/bin/bash", @[@"-lc",
        [NSString stringWithFormat:@"%@ list 2>/dev/null | head -6", gDisplayplacer]]);
    for (NSString *raw in [out componentsSeparatedByString:@"\n"]) {
        NSString *line = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([line hasPrefix:@"Resolution:"]) {
            return [[line substringFromIndex:11]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }
    return @"";
}

@interface VM : NSObject <NSMenuDelegate>
@end
@implementation VM
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSArray *displays = parseDisplays();
    if (displays.count == 0) {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"找不到 displayplacer" action:nil keyEquivalent:@""]];
        return;
    }
    // 只处理第一块屏（iPad 主屏），其余不展示
    NSDictionary *d = displays.firstObject;
    NSString *curRes = d[@"res"] ?: @"";
    BOOL curScale = [d[@"curScale"] isEqualToString:@"on"];
    // 当前逻辑尺寸
    NSArray *wh = [curRes componentsSeparatedByString:@"x"];
    NSInteger curLogW = 0, curLogH = 0;
    if (wh.count == 2) {
        // displayplacer 的 Resolution 行给的就是逻辑尺寸，不要再除 2
        curLogW = [wh[0] integerValue];
        curLogH = [wh[1] integerValue];
    }

    // 悬浮在图标上就能看到当前分辨率
    gItem.button.toolTip = [NSString stringWithFormat:@"当前 %ld×%ld（点一下切换）",
                            (long)curLogW, (long)curLogH];
    // 只留最有用的 4 档（按面板能力挑选）
    NSArray *preferred = @[
        @[@"1180", @"820"],
        @[@"1323", @"919"],
        @[@"1001", @"696"],
        @[@"800",  @"600"],
    ];

    CGFloat rowW = 262, rowH = 22;
    for (NSArray *pref in preferred) {
        NSString *w = pref[0], *h = pref[1];
        for (NSDictionary *m in d[@"modes"]) {
            if (![m[@"w"] isEqualToString:w] || ![m[@"h"] isEqualToString:h] || ![m[@"scale"] boolValue]) continue;
            BOOL isCur = (curScale && curLogW == [w integerValue] && curLogH == [h integerValue]);
            NSString *plain = [NSString stringWithFormat:@"%@×%@", w, h];
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:plain
                                                        action:@selector(apply:)
                                                 keyEquivalent:@""];
            it.target = self;
            it.representedObject = @[d[@"id"], w, h, @YES];
            if (isCur) {
                // 浅蓝玻璃：该行文字加半透明底色（纯视觉标记，无文字提示）
                NSMutableParagraphStyle *ps = [NSMutableParagraphStyle new];
                [ps setLineBreakMode:NSLineBreakByClipping];
                NSMutableAttributedString *as =
                    [[NSMutableAttributedString alloc] initWithString:plain attributes:@{
                        NSFontAttributeName: [NSFont menuFontOfSize:0],
                        NSForegroundColorAttributeName: [NSColor whiteColor],
                        NSParagraphStyleAttributeName: ps,
                        NSBackgroundColorAttributeName:
                            [NSColor colorWithCalibratedRed:0.30 green:0.62 blue:1.0 alpha:0.55]
                    }];
                it.attributedTitle = as;
            }
            [menu addItem:it];
            break;
        }
    }

    [menu addItem:[NSMenuItem separatorItem]];
    BOOL paused = [[NSFileManager defaultManager] fileExistsAtPath:
                   [NSHomeDirectory() stringByAppendingPathComponent:@".sidecar-pause"]];
    NSMenuItem *pauseItem = [[NSMenuItem alloc] initWithTitle:(paused ? @"恢复自动重连" : @"暂停自动重连")
                                                       action:@selector(togglePause:)
                                                keyEquivalent:@"p"];
    pauseItem.target = self;
    [menu addItem:pauseItem];

    NSMenuItem *rf = [[NSMenuItem alloc] initWithTitle:@"重新扫描" action:@selector(refresh:) keyEquivalent:@"r"];
    rf.target = self; [menu addItem:rf];
    NSMenuItem *q = [[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    q.target = self; [menu addItem:q];
}

- (void)apply:(NSMenuItem *)it {
    NSArray *a = it.representedObject;
    vlog(@"点击: %@", it.title);
    NSString *cmd = [NSString stringWithFormat:@"%@ \"id:%@ res:%@x%@ hz:60 color_depth:4 scaling:%@\"",
                     gDisplayplacer, a[0], a[1], a[2], [a[3] boolValue] ? @"on" : @"off"];
    NSString *want = [NSString stringWithFormat:@"%@x%@", a[1], a[2]];
    vlog(@"执行: %@", cmd);
    runCmd(@"/bin/bash", @[@"-lc", cmd]);
    // 校验：没切过去就再试一次（切换偶发被系统回滚）
    for (int i = 0; i < 3; i++) {
        usleep(350000);
        NSString *now = currentLogical();
        if ([now isEqualToString:want]) { vlog(@"生效: %@", now); return; }
        if (i == 1) { vlog(@"未生效(%@ != %@)，重试一次", now, want); runCmd(@"/bin/bash", @[@"-lc", cmd]); }
    }
    vlog(@"最终状态: %@ (期望 %@)", currentLogical(), want);
}
- (void)togglePause:(id)sender {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@".sidecar-pause"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:path]) {
        [fm removeItemAtPath:path error:nil];
    } else {
        [fm createFileAtPath:path contents:nil attributes:nil];
    }
}
- (void)refresh:(id)sender { }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc > 2 && strcmp(argv[1], "--export") == 0) {
            NSImage *ic = makeColorIcon(8.0);   // 导出用 8 倍，便于放大查看
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[ic TIFFRepresentation]];
            NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            [png writeToFile:[NSString stringWithUTF8String:argv[2]] atomically:YES];
            printf("exported %s\n", argv[2]);
            return 0;
        }
        gDisplayplacer = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/displayplacer"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:gDisplayplacer]) gDisplayplacer = @"/opt/homebrew/bin/displayplacer";
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        gItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

        // 彩色经典 Mac 图标（非 template，保留颜色）
        NSImage *icon = makeColorIcon(4.0);
        gItem.button.image = icon;
        gItem.button.imagePosition = NSImageOnly;
        gItem.button.imageScaling = NSImageScaleProportionallyDown;
        gItem.button.toolTip = @"分辨率（点一下切换）";
        NSMenu *menu = [NSMenu new];
        VM *vm = [VM new];
        menu.delegate = vm;
        gItem.menu = menu;
        [app run];
    }
    return 0;
}
