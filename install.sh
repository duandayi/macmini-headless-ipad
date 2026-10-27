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

say "3/6 安装脚本"
for f in sidecar-guard sidecar-status sidecar-pause sidecar-resume; do
    install -m 755 "$ROOT/scripts/$f" "$BIN/$f"
done
echo "    已安装 4 个命令到 $BIN"

say "4/6 生成配置"
if [ ! -f "$CFG/config.sh" ]; then
    printf "请输入 SideLinker 的本地 API Token（可先留空，稍后手填）: "
    read -r TOKEN || true
    cat > "$CFG/config.sh" <<CFGEOF
SIDELINKER_API="http://127.0.0.1:14792"
SIDELINKER_TOKEN="${TOKEN:-}"
VDISPLAY_NAME="SideLinker-HD"
LOGICAL_W=1323
LOGICAL_H=919
CFGEOF
    chmod 600 "$CFG/config.sh"
    echo "    已写入 $CFG/config.sh（权限 600）"
else
    echo "    配置已存在，跳过"
fi

say "5/6 生成 launchd 配置"
gen() {  # $1=模板  $2=输出名  $3=标签
    sed -e "s|__HOME__|$HOME|g" \
        -e "s|__LABEL_PREFIX__|$PREFIX|g" \
        -e "s|__VDISPLAY_NAME__|SideLinker-HD|g" \
        -e "s|__LOGICAL_W__|1323|g" \
        -e "s|__LOGICAL_H__|919|g" \
        "$1" > "$LA/$2"
    chmod 644 "$LA/$2"
    echo "    $LA/$2"
}
gen "$ROOT/launchd/vdisplay.plist.template"      "$PREFIX.vdisplay.plist"      "$PREFIX.vdisplay"
gen "$ROOT/launchd/sidecar-guard.plist.template" "$PREFIX.sidecar-guard.plist" "$PREFIX.sidecar-guard"

say "6/6 加载开机自启"
launchctl bootout "gui/$(id -u)/$PREFIX.vdisplay" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$PREFIX.sidecar-guard" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LA/$PREFIX.vdisplay.plist"
launchctl bootstrap "gui/$(id -u)" "$LA/$PREFIX.sidecar-guard.plist"

cat <<'TIP'

安装完成 ✅

接下来还需要（一次性）：
  1. 在 SideLinker Mac 里把「虚拟屏名称」设为 SideLinker-HD，目标设为你的 iPad
  2. 把 SideLinker Mac 加进「登录项」（系统设置 → 通用 → 登录项）
  3. 系统设置 → 显示器：让 iPad(Sidecar) 镜像到 SideLinker-HD
  4. 重新登录或重启后，检查：sidecar-status

常用命令：
  sidecar-status    看链路状态
  sidecar-pause     暂停自动重连
  sidecar-resume    恢复自动重连
TIP
