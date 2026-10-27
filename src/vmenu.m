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

static NSString *runCmd(NSString *path, NSArray *args) {
    NSTask *t = [NSTask new];
    t.launchPath = path;
    t.arguments = args;
    NSPipe *p = [NSPipe pipe];
    t.standardOutput = p;
    t.standardError = [NSFileHandle fileHandleWithNullDevice];
    @try { [t launch]; [t waitUntilExit]; } @catch (NSException *e) { return @""; }
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
            cur = [@{ @"id": [line substringFromIndex:21],
                      @"modes": [NSMutableArray array] } mutableCopy];
        } else if (cur) {
            if ([line hasPrefix:@"Resolution:"]) {
                cur[@"res"] = [line substringFromIndex:11];
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
                cur[@"curScale"] = [line substringFromIndex:8];
            }
        }
    }
    if (cur) [displays addObject:cur];
    return displays;
}

@interface VM : NSObject <NSMenuDelegate>
@end
@implementation VM
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSArray *displays = parseDisplays();
    if (displays.count == 0) {
        [menu addItem:[[NSMenuItem alloc] initWithTitle:@"找不到 displayplacer" action:nil keyEquivalent:@""]];
    }
    int idx = 0;
    for (NSDictionary *d in displays) {
        idx++;
        BOOL isMain = [d[@"res"] isEqualToString:[displays.firstObject objectForKey:@"res"]] && idx == 1;
        NSString *title = [NSString stringWithFormat:@"%@  %@", (idx == 1 ? @"主屏 iPad" : [NSString stringWithFormat:@"屏幕 %d", idx]),
                           d[@"res"] ?: @"?"];
        NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        NSMenu *sub = [NSMenu new];
        // 去重：同一 res 只留 scaling:on 与 off 各一条
        NSMutableSet *seen = [NSMutableSet set];
        for (NSDictionary *m in d[@"modes"]) {
            NSString *key = [NSString stringWithFormat:@"%@x%@-%d", m[@"w"], m[@"h"], [m[@"scale"] boolValue]];
            if ([seen containsObject:key]) continue;
            [seen addObject:key];
            NSString *t = [NSString stringWithFormat:@"%@×%@%@", m[@"w"], m[@"h"],
                           [m[@"scale"] boolValue] ? @"   Retina" : @"   1x"];
            NSMenuItem *it = [[NSMenuItem alloc] initWithTitle:t action:@selector(apply:) keyEquivalent:@""];
            it.target = self;
            it.representedObject = @[d[@"id"], m[@"w"], m[@"h"], m[@"scale"]];
            [sub addItem:it];
        }
        top.submenu = sub;
        [menu addItem:top];
    }
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *rf = [[NSMenuItem alloc] initWithTitle:@"重新扫描" action:@selector(refresh:) keyEquivalent:@"r"];
    rf.target = self; [menu addItem:rf];
    NSMenuItem *q = [[NSMenuItem alloc] initWithTitle:@"退出" action:@selector(quit:) keyEquivalent:@"q"];
    q.target = self; [menu addItem:q];
}
- (void)apply:(NSMenuItem *)it {
    NSArray *a = it.representedObject;
    NSString *cmd = [NSString stringWithFormat:@"%@ \"id:%@ res:%@x%@ hz:60 color_depth:4 scaling:%@\"",
                     gDisplayplacer, a[0], a[1], a[2], [a[3] boolValue] ? @"on" : @"off"];
    runCmd(@"/bin/bash", @[@"-lc", cmd]);
}
- (void)refresh:(id)sender { }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
@end

int main(void) {
    @autoreleasepool {
        gDisplayplacer = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin/displayplacer"];
        if (![[NSFileManager defaultManager] isExecutableFileAtPath:gDisplayplacer]) gDisplayplacer = @"/opt/homebrew/bin/displayplacer";
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        gItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];

        // 图标：手绘显示器轮廓（无支架下垂），与相邻状态栏图标同高、同视觉重心
        NSSize canvasSize = NSMakeSize(18, 16);
        NSImage *icon = [[NSImage alloc] initWithSize:canvasSize];
        [icon lockFocus];
        [[NSColor blackColor] setStroke];
        // 屏幕
        NSBezierPath *screen = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(1.7, 3.5, 14.6, 9.6)
                                                               xRadius:2.2 yRadius:2.2];
        [screen setLineWidth:1.4];
        [screen stroke];
        // 底座
        NSBezierPath *base = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(6.9, 2.0, 4.2, 1.3)
                                                             xRadius:0.7 yRadius:0.7];
        [base setLineWidth:1.1];
        [base stroke];
        [icon unlockFocus];
        [icon setTemplate:YES];
        gItem.button.image = icon;
        gItem.button.imagePosition = NSImageOnly;
        gItem.button.imageScaling = NSImageScaleNone;
        gItem.button.toolTip = @"分辨率（点一下切换）";
        NSMenu *menu = [NSMenu new];
        VM *vm = [VM new];
        menu.delegate = vm;
        gItem.menu = menu;
        [app run];
    }
    return 0;
}
