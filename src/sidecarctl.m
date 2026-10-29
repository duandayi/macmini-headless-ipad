// sidecarctl — 直接调用 macOS 私有 SidecarCore 管理随航（不依赖任何第三方 App）
// 用法：
//   sidecarctl list                 列出可用/已连接设备
//   sidecarctl connect [名称片段]    连接（默认第一台 iPad）
//   sidecarctl disconnect [名称片段] 断开
// 依赖：/System/Library/PrivateFrameworks/SidecarCore.framework（系统自带）

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <objc/message.h>

@interface SidecarDevice : NSObject
- (NSString *)name;
- (NSString *)model;
- (id)identifier;
- (long long)status;
@end
@interface SidecarDevice (ForceFetch)
+ (NSArray *)allDevicesByForcingFetchFromRelay:(BOOL)force;
@end
@interface SidecarDisplayManager : NSObject
+ (instancetype)sharedManager;
+ (BOOL)isSupported;
- (NSArray *)devices;
- (NSArray *)connectedDevices;
- (void)connectToDevice:(SidecarDevice *)d completion:(void (^)(NSError *))cb;
- (void)disconnectFromDevice:(SidecarDevice *)d completion:(void (^)(NSError *))cb;
@end

static SidecarDisplayManager *mgr(void) {
    Class DM = NSClassFromString(@"SidecarDisplayManager");
    return [DM sharedManager];
}

// 取可用设备；若为空，强制从 relay 拉一次（比等蓝牙广播快很多）
static NSArray *availableDevices(void) {
    NSArray *list = [mgr() devices];
    if (list.count > 0) return list;
    Class D = NSClassFromString(@"SidecarDevice");
    SEL sel = NSSelectorFromString(@"allDevicesByForcingFetchFromRelay:");
    if (D && [D respondsToSelector:sel]) {
        NSArray *forced = ((NSArray *(*)(id, SEL, BOOL))objc_msgSend)(D, sel, YES);
        if (forced.count) return forced;
    }
    return list ?: @[];
}

static SidecarDevice *findDevice(NSString *fragment, BOOL onlyConnected) {
    NSArray *list = onlyConnected ? [mgr() connectedDevices] : availableDevices();
    if (!list.count) return nil;
    if (!fragment.length) return list.firstObject;
    // 支持三种匹配：完整 UUID / UUID 前缀 / 设备名片段
    for (SidecarDevice *d in list) {
        NSString *ident = [[d identifier] description] ?: @"";
        if ([ident isEqualToString:fragment] || [ident hasPrefix:fragment]) return d;
        if ([[d name] containsString:fragment]) return d;
    }
    // 明确指定了目标却找不到 → 不退回“随便第一台”，避免连错设备
    fprintf(stderr, "未找到匹配 \"%s\" 的设备（可用 devices 查看）\n", [fragment UTF8String]);
    return nil;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/SidecarCore.framework/SidecarCore", RTLD_NOW)) {
            fprintf(stderr, "无法加载 SidecarCore\n"); return 1;
        }
        NSString *cmd = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"list";
        NSString *frag = argc > 2 ? [NSString stringWithUTF8String:argv[2]] : @"";

        if ([cmd isEqualToString:@"list"]) {
            printf("支持: %s\n", (BOOL)[(id)NSClassFromString(@"SidecarDisplayManager") isSupported] ? "是" : "否");
            NSArray *av = availableDevices();
            printf("\n可用设备 %lu:\n", (unsigned long)av.count);
            for (SidecarDevice *d in availableDevices())
                printf("  %-20s %-12s id=%s\n", [[d name] UTF8String], [[d model] UTF8String],
                       [[[d identifier] description] UTF8String]);
            printf("\n已连接 %lu:\n", (unsigned long)[[mgr() connectedDevices] count]);
            for (SidecarDevice *d in [mgr() connectedDevices])
                printf("  %s\n", [[d name] UTF8String]);
            return 0;
        }

        if ([cmd isEqualToString:@"connect"] || [cmd isEqualToString:@"disconnect"]) {
            BOOL connecting = [cmd isEqualToString:@"connect"];
            SidecarDevice *d = findDevice(frag, connecting ? [mgr() connectedDevices].count > 0 : YES);
            if (!d) { fprintf(stderr, "找不到设备\n"); return 2; }
            printf("%s → %s\n", connecting ? "连接" : "断开", [[d name] UTF8String]);
            __block BOOL done = NO; __block NSError *err = nil;
            if (connecting) {
                [mgr() connectToDevice:d completion:^(NSError *e) { err = e; done = YES; }];
            } else {
                [mgr() disconnectFromDevice:d completion:^(NSError *e) { err = e; done = YES; }];
            }
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:25];
            while (!done && [deadline timeIntervalSinceNow] > 0)
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
            if (!done) { fprintf(stderr, "超时（25s 无回调）\n"); return 3; }
            if (err) { fprintf(stderr, "失败: %s\n", [[err localizedDescription] UTF8String]); return 4; }
            printf("成功\n");
            return 0;
        }
        fprintf(stderr, "用法: sidecarctl list|connect|disconnect [名称片段]\n");
    }
    return 0;
}
