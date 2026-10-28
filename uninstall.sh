#!/bin/bash
# 卸载：停掉自启并清理本项目的组件（不影响系统与其它软件）
set -uo pipefail
PREFIX="${PREFIX:-com.example}"
LA="$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)/$PREFIX.vdisplay" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$PREFIX.sidecar-guard" 2>/dev/null || true
rm -f "$LA/$PREFIX.vdisplay.plist" "$LA/$PREFIX.sidecar-guard.plist"
rm -f "$HOME/.local/bin"/{vdisplay,sidecar-guard,sidecar-status,sidecar-pause,sidecar-resume}
echo "已卸载。配置保留在 ~/.config/sidecar/（要彻底删除请手动 rm）"
