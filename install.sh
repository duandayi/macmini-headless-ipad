#!/bin/bash
# macmini-headless-ipad 安装脚本
# 作用：编译并安装虚拟屏 vdisplay + 连接守护 sidecar-guard + launchd 自启
set -euo pipefail

PREFIX="${PREFIX:-com.example}"     # launchd 标签前缀，可自定义
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CFG="$HOME/.config/sidecar"
LA="$HOME/Library/LaunchAgents"

say() { printf "\033[1;36m==>\033[0m %s\n" "$*"; }

[ "$(uname -s)" = "Darwin" ] || { echo "仅支持 macOS"; exit 1; }
command -v clang >/dev/null || { echo "缺少 clang，请先装 Xcode 命令行工具：xcode-select --install"; exit 1; }

say "1/6 创建目录"
mkdir -p "$BIN" "$CFG" "$LA"

say "2/6 编译虚拟屏 vdisplay"
clang -fobjc-arc -framework Foundation -framework AppKit \
      -undefined dynamic_lookup -O2 \
      -o "$BIN/vdisplay" "$ROOT/src/vdisplay.m"
echo "    已安装: $BIN/vdisplay"

say "2a/6 编译随航连接工具 sidecarctl（调用系统私有 SidecarCore）"
clang -fobjc-arc -framework Foundation -O2 -o "$BIN/sidecarctl" "$ROOT/src/sidecarctl.m"
echo "    已安装: $BIN/sidecarctl"

say "2b/6 编译菜单栏分辨率切换 vmenu（可选，需要 displayplacer）"
if [ -x "$BIN/displayplacer" ] || command -v displayplacer >/dev/null; then
    clang -fobjc-arc -framework Foundation -framework AppKit \
          -O2 -o "$BIN/vmenu" "$ROOT/src/vmenu.m"
    echo "    已安装: $BIN/vmenu"
else
    echo "    跳过：未装 displayplacer（brew install displayplacer 后可重跑本步）"
fi

say "3/6 安装脚本"
for f in sidecar-guard sidecar-status sidecar-pause sidecar-resume sidecar-doctor sidecar-report; do
    install -m 755 "$ROOT/scripts/$f" "$BIN/$f"
done
echo "    已安装 6 个命令到 $BIN"

say "4/6 生成配置"
if [ ! -f "$CFG/config.sh" ]; then
    cat > "$CFG/config.sh" <<CFGEOF
# 虚拟屏名称（第一次连接后，系统会记住这个镜像关系，之后不要随意改）
VDISPLAY_NAME="iPadLink-HD"
LABEL_PREFIX="$PREFIX"
# 绑定设备 UUID：只连这一台，别人的 iPad 一律拒绝。
# 装完运行 \`sidecarctl list\` 复制 id= 后面的 UUID 填进来
SIDECAR_DEVICE_ID=""
CFGEOF
    chmod 600 "$CFG/config.sh"
    echo "    已写入 $CFG/config.sh（权限 600）"
else
    echo "    配置已存在，跳过"
fi

# 读取配置里的虚拟屏名
# shellcheck disable=SC1090
[ -f "$CFG/config.sh" ] && . "$CFG/config.sh"
VDNAME="${VDISPLAY_NAME:-iPadLink-HD}"

say "5/6 生成 launchd 配置"
gen() {  # $1=模板  $2=输出名  $3=标签
    sed -e "s|__HOME__|$HOME|g" \
        -e "s|__LABEL_PREFIX__|$PREFIX|g" \
        -e "s|__VDISPLAY_NAME__|$VDNAME|g" \
        -e "s|__LOGICAL_W__|1323|g" \
        -e "s|__LOGICAL_H__|919|g" \
        "$1" > "$LA/$2"
    chmod 644 "$LA/$2"
    echo "    $LA/$2"
}
gen "$ROOT/launchd/vdisplay.plist.template"      "$PREFIX.vdisplay.plist"      "$PREFIX.vdisplay"
gen "$ROOT/launchd/sidecar-guard.plist.template" "$PREFIX.sidecar-guard.plist" "$PREFIX.sidecar-guard"

if [ "${SKIP_LAUNCHD:-0}" = "1" ]; then
    say "6/6 跳过 launchd（SKIP_LAUNCHD=1，仅用于测试）"
    echo "SKIP_LAUNCHD_OK"; exit 0
fi

say "6/6 加载开机自启"
launchctl bootout "gui/$(id -u)/$PREFIX.vdisplay" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$PREFIX.sidecar-guard" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PREFIX.vdisplay.plist"
launchctl bootstrap "gui/$(id -u)" "$LA/$PREFIX.sidecar-guard.plist"
[ -f "$LA/$PREFIX.vmenu.plist" ] && launchctl bootstrap "gui/$(id -u)" "$LA/$PREFIX.vmenu.plist"

cat <<'TIP'

安装完成 ✅

接下来还需要（一次性）：
  1. iPad 与 Mac 登录同一个 Apple ID，开蓝牙 + Wi-Fi（iPad 端无需安装任何 App）
  2. 系统设置 → 显示器：让 iPad(Sidecar) 镜像到 iPadLink-HD（只需配一次，之后会记住）
  3. 重新登录或重启后，检查：sidecar-status

常用命令：
  sidecar-doctor    环境自检（装机后先跑这个）
  sidecar-report    测试期报告：每次开机耗时/干预次数
  sidecar-status    看链路状态
  sidecar-pause     暂停自动重连
  sidecar-resume    恢复自动重连
TIP
