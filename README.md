# Mac mini 无头模式 · 用 iPad 当唯一屏幕

把一台 **没有接显示器** 的 Mac mini，变成「开机 → 自动连上 iPad → iPad 就是这块 Mac 的屏幕」的个人工作站。

整套方案 **不依赖任何付费软件**：虚拟屏是自己写的（78 行 Objective-C），连接守护是 Bash，唯一的第三方依赖是开源的 [SideLinker](https://github.com/wberry9813/SideLinker-Home)。

```
开机 → 自动登录 → launchd 拉起 vdisplay（虚拟屏）+ SideLinker
     → SideLinker 连随航、配镜像 → iPad 显示桌面
     → 键盘/触控板走「通用控制」（另一条独立通道）
```

---

## 为什么需要"虚拟屏"

Mac 如果一块显示器都没有，随航连上 iPad 后是**黑屏**——因为 macOS 需要一个「镜像源」。
实测（把唯一的虚拟屏删掉后连续观测 65 秒）：Sidecar 全程 offline。

所以必须有一块虚拟屏当锚点。商业软件 BetterDisplay 干的就是这件事（Pro 授权 ¥138），
本项目自己实现了它，参数可以做到完全一致。

---

## 效果（实测数据）

| 项 | 值 |
|---|---|
| 面板分辨率 | 2646 × 1838 |
| 逻辑分辨率 | 1323 × 919（HiDPI 2x） |
| 刷新率 | 60 Hz |
| 开机到连通 | 约 20 秒（含系统开机到登录的 10 秒） |
| 有线随航 | 支持，`connection_type: wired` |

---

## 前置条件

- macOS 26+（在 macOS 27.0 / Apple Silicon 上实测）
- 一台 iPad（同一 Apple ID、已信任、开启蓝牙 + Wi-Fi）
- [SideLinker Mac](https://github.com/wberry9813/SideLinker-Home)（开源，负责连随航 + 配镜像）
- Xcode 命令行工具（编译虚拟屏）：`xcode-select --install`
- **自动登录必须打开**（无头机器没人能输密码）；FileVault 会阻止自动登录，需要关闭

---

## 安装

```bash
git clone https://github.com/<你的用户名>/macmini-headless-ipad.git
cd macmini-headless-ipad
./install.sh
```

安装脚本会：
1. 编译 `src/vdisplay.m` → `~/.local/bin/vdisplay`
2. 安装 `sidecar-guard` / `sidecar-status` / `sidecar-pause` / `sidecar-resume`
3. 生成 `~/.config/sidecar/config.sh`（提示你填 SideLinker 的 API Token）
4. 生成并加载两个 launchd 任务（虚拟屏 + 连接守护）

安装后还需要 **手动做 4 件事**（一次性）：

1. SideLinker 里把「虚拟屏名称」设为 `SideLinker-HD`
2. SideLinker Mac 加入「登录项」
3. 系统设置 → 显示器：让 iPad 镜像到 `SideLinker-HD`
4. 重启一次，然后 `sidecar-status` 检查

---

## 菜单栏切换分辨率

装好后菜单栏会多一个 **显示器图标**，点开就是：

```
主屏 iPad  1180×820
  ├ 1180×820   Retina   ← 与面板 1:1，最清晰
  ├ 1323×919   Retina   ← 空间更大，略软
  ├ 1024×768   1x
  └ …
屏幕 2  2360×1640          ← 虚拟屏本身，一般不用动
重新扫描 ⌘R
退出 ⌘Q
```

选哪一档就立刻切换，不用开「系统设置」。带 **Retina** 的是 HiDPI（2x 渲染），清晰度更好。

> 依赖 [displayplacer](https://github.com/jakehilborn/displayplacer)（开源，`brew install displayplacer`）。

## 常用命令

```bash
sidecar-doctor     # 环境自检：一条命令告诉你哪里不符合（装完先跑这个）
sidecar-status     # 链路状态（守护 + SideLinker + 显示器 + 日志）
sidecar-pause      # 临时暂停自动重连（要拿 iPad 干别的时用）
sidecar-resume     # 恢复自动重连
```

---

## 自定义分辨率

面板分辨率 = 逻辑分辨率 × 2。

**想让文字最清晰：选"与面板 1:1"的那一档。**

以 iPad (A16) 11 吋为例，面板原生 **2360×1640**，对应逻辑 **1180×820 @2x**。
此时 Mac 渲染多少像素，iPad 就显示多少像素，中间没有任何缩放——这是清晰度的上限。

选更大的逻辑尺寸（如 1323×919 → 面板 2646×1838）会换来更多桌面空间，
但画面比面板大，iPad 端要缩小显示，文字会略微变软。两者不可兼得。

查看当前屏支持哪些 HiDPI 档位：

```bash
displayplacer list | grep "scaling:on"
```
改 `~/.config/sidecar/config.sh` 里的 `LOGICAL_W/LOGICAL_H`，
再改对应的 launchd plist 里的 `--w/--h`，然后重新加载：

```bash
launchctl kickstart -k gui/$(id -u)/com.example.vdisplay
```

也可以手动跑一下看效果：

```bash
~/.local/bin/vdisplay --name SideLinker-HD --w 1323 --h 919 --scale 2
```

---

## 排障

### 先跑自检

```bash
sidecar-doctor
```

它会逐项检查：系统版本、自动登录、FileVault、登录项、两个常驻组件、虚拟屏是否 HiDPI 2x、
是否有别的虚拟屏软件冲突、SideLinker API 是否连通，最后给出「通过/提醒/失败」计数。
大部分问题看输出就能定位。

### 开机后 iPad 黑屏
按顺序查：

```bash
# 1) 虚拟屏在不在
pgrep -lf vdisplay

# 2) SideLinker 在不在
pgrep -lf "SideLinker Mac"

# 3) SideLinker 自己怎么说
curl -H "Authorization: Bearer <token>" http://127.0.0.1:14792/status

# 4) 守护日志
tail -20 ~/Library/Logs/sidecar-guard.log
```

最常见的原因：**登录项被清空**（某些"优化/清理"软件、或系统更新后会这样），
导致 SideLinker 和虚拟屏都没被拉起。本项目的 launchd 任务不依赖登录项，但如果两者都没了，就检查登录项。

### 字突然变模糊
iPad 那块屏被切到了 **1x 模式**。正常应该是 `Resolution` 是 `UI Looks like` 的 **2 倍**：

```bash
system_profiler SPDisplaysDataType | grep -E "Resolution|UI Looks like"
```

修法（先用 `displayplacer list` 找到 iPad 那块屏的 id）：

```bash
displayplacer "id:<屏幕ID> res:1323x919 hz:60 color_depth:4 scaling:on"
```

### 虚拟屏起不来 / 报"身份冲突"
`vendorID / productID / serialNum` 必须与系统里其它虚拟屏**不同**，否则 macOS 拒绝创建，
WindowServer 日志是 `no displayID available`。改 `src/vdisplay.m` 里那三个值即可。

### 键盘（通用控制）掉线
这是另一条独立通道，与随航无关。常见诱因是 AirPods 等蓝牙设备抢占射频。
本项目暂未包含键盘看门狗，可自行用 `killall UniversalControl` 后等系统重连。

---

## 技术笔记

### 用到的私有 API

`CGVirtualDisplay` 系列（`CoreGraphics`，未公开但长期存在）：`CGVirtualDisplayDescriptor`、
`CGVirtualDisplaySettings`、`CGVirtualDisplayMode`、`CGVirtualDisplay`。

编译要点：

```bash
clang -fobjc-arc -framework Foundation -framework AppKit \
      -undefined dynamic_lookup -O2 -o vdisplay src/vdisplay.m
```

- `-undefined dynamic_lookup`：私有类不在 SDK 里，链接期不解析、运行期绑定
- 直接按真名声明 `@interface`，**不要**用 `NSInvocation` 传 `NSUInteger`（ABI 会错位，段错误）
- `initWithWidth:height:refreshRate:` 的真实签名是 `uint32, uint32, double`

### 已知限制

- 私有 API 未来可能被 Apple 收紧，届时需要切到别的方案
- 每台机器上虚拟屏的 `vendorID/productID/serialNum` 要保持唯一
- 未包含 root 级防篡改（可选，见 `docs/` 说明）

---

## 目录结构

```
src/vdisplay.m      虚拟屏实现（78 行）
scripts/            守护与状态命令
launchd/            开机自启模板
install.sh          一键安装
uninstall.sh        卸载
docs/               踩坑记录与排障
```

---

## 致谢

- [SideLinker](https://github.com/wberry9813/SideLinker-Home) —— 连随航 + 配镜像的开源实现
- 苹果的随航（Sidecar）与通用控制（Universal Control）

## License

MIT
