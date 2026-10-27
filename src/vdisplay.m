// vdisplay — 自建 macOS 虚拟显示器（原创实现，MIT）
// 与 BetterDisplay 无关：只用系统私有 CGVirtualDisplay API。
// 注意：vendorID/productID/serialNum 必须与系统里其它虚拟屏不同，否则 macOS 会拒绝创建
//       （WindowServer: "no displayID available"）。
// 用法：vdisplay [--name iPadLink-HD] [--w 1323] [--h 919] [--scale 2] [--hz 60]
//       进程存活 = 虚拟屏存在；退出即销毁。

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint32_t vendorID, productID, maxPixelsWide, maxPixelsHigh;
@property (nonatomic) uint64_t serialNum;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) id terminationHandler;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)d;
- (BOOL)applySettings:(id)s;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(uint32_t)w height:(uint32_t)h refreshRate:(double)r;
@end
@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) uint32_t hiDPI;
@property (nonatomic, copy) NSArray *modes;
@end

static NSString *gName; static uint32_t gW, gH, gScale, gHz;
static id gDisplay = nil;

@interface AppD : NSObject <NSApplicationDelegate> @end
@implementation AppD
- (void)applicationDidFinishLaunching:(NSNotification *)n {
    CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
    d.name = gName;
    // 固定且唯一（不要改成 2198/18970/3491416317 —— 那是 BetterDisplay 的身份）
    d.vendorID = 0x4D41;          // "MA"
    d.productID = 0x4944;         // "ID"
    d.serialNum = 0x49504144ULL;  // "IPAD"
    d.maxPixelsWide = gW * gScale;
    d.maxPixelsHigh = gH * gScale;
    d.sizeInMillimeters = NSMakeSize(gW * 0.19, gH * 0.18);
    d.queue = dispatch_get_main_queue();

    CGVirtualDisplay *v = [[CGVirtualDisplay alloc] initWithDescriptor:d];
    if (!v) { fprintf(stderr, "创建虚拟屏失败（可能身份冲突）\n"); [NSApp terminate:nil]; return; }
    // 多档模式：随航端切成别的分辨率时，镜像源要跟得上
    NSMutableArray *modes = [NSMutableArray array];
    NSArray *sizes = @[ @[@(gW), @(gH)], @[@1323, @919], @[@1180, @820], @[@1001, @696], @[@800, @600] ];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSArray *wh in sizes) {
        NSString *key = [NSString stringWithFormat:@"%@x%@", wh[0], wh[1]];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];
        CGVirtualDisplayMode *mm = [[CGVirtualDisplayMode alloc] initWithWidth:[wh[0] unsignedIntValue]
                                                                      height:[wh[1] unsignedIntValue]
                                                                 refreshRate:(double)gHz];
        if (mm) [modes addObject:mm];
    }
    CGVirtualDisplaySettings *s = [CGVirtualDisplaySettings new];
    s.hiDPI = 1; s.modes = modes;
    if (![v applySettings:s]) { fprintf(stderr, "applySettings 失败\n"); [NSApp terminate:nil]; return; }
    gDisplay = v;
    printf("OK name=%s panel=%ux%u logical=%ux%u hz=%u hidpi=1\n",
           [gName UTF8String], gW*gScale, gH*gScale, gW, gH, gHz);
    fflush(stdout);
}
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        gName = @"iPadLink-HD"; gW = 1323; gH = 919; gScale = 2; gHz = 60;
        for (int i = 1; i < argc; i++) {
            NSString *a = [NSString stringWithUTF8String:argv[i]];
            if ([a isEqualToString:@"--name"] && i+1 < argc) gName = [NSString stringWithUTF8String:argv[++i]];
            else if ([a isEqualToString:@"--w"] && i+1 < argc) gW = (uint32_t)atoi(argv[++i]);
            else if ([a isEqualToString:@"--h"] && i+1 < argc) gH = (uint32_t)atoi(argv[++i]);
            else if ([a isEqualToString:@"--scale"] && i+1 < argc) gScale = (uint32_t)atoi(argv[++i]);
            else if ([a isEqualToString:@"--hz"] && i+1 < argc) gHz = (uint32_t)atoi(argv[++i]);
        }
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppD *dg = [AppD new]; app.delegate = dg; [app run];
    }
    return 0;
}
