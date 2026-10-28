# AGENTS.md —— 给 AI Agent 的部署说明

> 这份文件是给**编码 Agent**（Claude Code / Codex / DeepSeek / Cursor 等）读的。
> 人类用户请直接看 [README.md](README.md)。

## 目标

在一台**没有显示器**的 Apple Silicon Mac 上，让 iPad 成为唯一屏幕，并且开机自动连接、断线自愈。

完成后应满足：

1. `sidecar-doctor` 全部通过（0 失败）
2. 重启后 60 秒内 iPad 自动出现桌面，无人工干预
3. 所有组件由 `launchd` 管理，无第三方 App 依赖

## 前置检查（缺一不可，先跑再动手）

```bash
sw_vers                       # 需要 macOS 26+（实测 27.0）
uname -m                      # 需要 arm64
xcode-select -p               # 需要 Command Line Tools
/usr/bin/pgrep -x WindowServer >/dev/null && echo "有图形会话"
```

再确认 Apple ID 与 iPad 一致：

```bash
# 设备能否被发现（未装本项目时会话还不存在，可先跳过这一步）
# 安装后用 sidecarctl list 验证
```

**如果 Mac 上没有任何可用显示输出（无头）**，请先通过 SSH 或屏幕共享操作，否则装完会立刻"看不见"。

## 部署步骤

### 1. 克隆并安装

```bash
git clone https://github.com/daxiong6666/macmini-headless-ipad.git
cd macmini-headless-ipad
./install.sh
```

`install.sh` 会：编译 `vdisplay` / `sidecarctl` / `vmenu` → 装到 `~/.local/bin` → 写 LaunchAgent → 跑自检。
若只想装组件不注册开机启动：`SKIP_LAUNCHD=1 ./install.sh`。

### 2. 让 iPad 出现并被记住

```bash
sidecarctl list        # 期望：可用设备 >= 1，名称是你的 iPad
sidecarctl connect     # 建立第一次会话
```

**首次连接 macOS 会记住镜像配置**。确认镜像关系：

```bash
system_profiler SPDisplaysDataType | grep -A4 "Sidecar Display"
# 期望：出现 Sidecar Display，且 Mirror: On
```

如果 iPad 连上但**黑屏**，说明没有镜像源，检查虚拟屏：

```bash
pgrep -lf vdisplay            # 必须有 1 个进程
system_profiler SPDisplaysDataType | grep -A2 "iPadLink-HD"
```

### 3. 绑定设备（强烈建议）

```bash
sidecarctl list | grep id=    # 复制 iPad 的 UUID
echo 'SIDECAR_DEVICE_ID="<UUID>"' >> ~/.config/sidecar/config.sh
```

绑定后只会连这一台，别的设备一律拒绝（`sidecarctl` 未匹配时直接返回错误，不会退回任意设备）。

### 4. 系统级保护（可选，但本项目推荐）

```bash
sudo ./protectd/install-protectd.sh
```

它会：

- 把组件复制到 `/usr/local/libexec/dsh-sidecar/`（`root:wheel` + `schg`）
- 给 `~/.local/bin/` 下的副本加 `uchg`
- 注册 `com.dsh.sidecar-protect`（`StartInterval 20`），负责还原/补锁/重载/救援

安装后**主副本不可修改**。要更新组件，必须：

```bash
sudo chflags noschg /usr/local/libexec/dsh-sidecar/*
# 改 /tmp 里的副本并测试
sudo install -o root -g wheel -m 755 /tmp/xxx /usr/local/libexec/dsh-sidecar/xxx
sudo install -o $USER -g staff -m 755 /usr/local/libexec/dsh-sidecar/xxx ~/.local/bin/xxx
sudo chflags schg /usr/local/libexec/dsh-sidecar/*
```

> ⚠️ **只改用户侧会被 20 秒内还原**——这是保护在工作，不是 bug。遇到"代码改了但行为没变"，先检查是否被还原。

### 5. 验证

```bash
sidecar-doctor           # 期望：全部 ✔，0 失败
sidecar-status           # 期望：state=running, connected=yes
sidecar-report           # 期望：能看到本次开机耗时
```

**重启验证（最关键的一步）**

```bash
sudo shutdown -r now
```

重启后 60 秒内应自动连上。检查：

```bash
tail -20 ~/Library/Logs/sidecar-guard.log
# 期望看到：启动 → [开机阶段] 未连接 → 连接成功
cat /tmp/vdisplay.err    # 期望：空（非空说明虚拟屏创建失败）
```

## 常见失败与处理

| 现象 | 原因 | 处理 |
|---|---|---|
| `sidecarctl list` 可用设备 0 | iPad 关机 / 蓝牙未开 / 不同 Apple ID | 让用户确认；同一账号是硬条件 |
| 连上但黑屏 | 没有虚拟屏 / 没镜像 | 检查 `vdisplay` 进程与 `Mirror: On` |
| `applySettings 失败` / 创建虚拟屏失败 | `vendorID/productID/serialNum` 与别的虚拟屏软件冲突 | 本项目已用唯一 ID（0x4D41/0x4944/0x49504144），若冲突需改 `src/vdisplay.m` |
| 连接后从 2x 变模糊 | 系统把模式改回 1x | `displayplacer "id:<Sidecar ID> res:1180x820 hz:60 color_depth:4 scaling:on"` |
| 守护反复重连 | 设备 UUID 绑错 / 会话被系统抢占 | 看 `~/Library/Logs/sidecar-guard.log`，确认 `target=` 与 `sidecarctl list` 一致 |
| 菜单栏不出现 | LaunchAgent 未加载 | `launchctl print gui/$(id -u)/com.dsh.vmenu` |

## 硬约束（不要违反）

1. **不要**删除或修改 `/usr/local/libexec/dsh-sidecar/`（除非走上面的解锁流程）
2. **不要**同时跑两个 `vdisplay`（虚拟屏必须单一所有者，守护只 `kickstart`，不自己 spawn）
3. **不要**引入第三方运行时依赖（Node/Python）；安装脚本只用系统自带 `clang`/`bash`
4. **不要**在没有备用屏幕的情况下做破坏性改动——用户可能立刻失去画面
5. 修改任何组件后必须验证：`bash -n` → 装到 master → 跑 `sidecar-doctor` → 观察 2 分钟日志

## 验收清单

- [ ] `sidecar-doctor` 0 失败
- [ ] `sidecarctl list` 能看到绑定的 iPad
- [ ] 断开后 10 秒内自动重连（`sidecarctl disconnect` 后观察）
- [ ] 重启后 60 秒内自动连上，`/tmp/vdisplay.err` 为空
- [ ] 若装了 protectd：`ls -lO /usr/local/libexec/dsh-sidecar` 全部 `schg`
- [ ] 菜单栏图标存在，点开能看到 4 档分辨率
