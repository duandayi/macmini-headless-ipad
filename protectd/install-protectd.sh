#!/bin/bash
# 可选：把本项目所有组件锁成「系统级」——root 所有 + schg 不可变 + 20 秒自动还原
# 需要管理员权限。卸载：先 launchctl bootout，再 chflags noschg 后删除。
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M=/usr/local/libexec/dsh-sidecar
H="$HOME"
GU=$(id -u)
[ "$(id -u)" = "0" ] || { echo "请用 sudo 运行"; exit 1; }

mkdir -p "$M"
# 主副本
for f in vdisplay sidecarctl vmenu sidecar-guard sidecar-status sidecar-doctor sidecar-report sidecar-pause sidecar-resume; do
  [ -f "$H/.local/bin/$f" ] && install -o root -g wheel -m 755 "$H/.local/bin/$f" "$M/$f"
done
install -o root -g wheel -m 755 "$ROOT/protectd/protectd" "$M/protectd"
# 用户侧上锁
for f in vdisplay sidecarctl vmenu sidecar-guard sidecar-status sidecar-doctor sidecar-report sidecar-pause sidecar-resume; do
  [ -f "$H/.local/bin/$f" ] && { chflags nouchg "$H/.local/bin/$f" 2>/dev/null || true; chflags uchg "$H/.local/bin/$f" 2>/dev/null || true; }
done
# 系统级不可变
chflags schg "$M"/* 2>/dev/null || true
chflags schg "$M" 2>/dev/null || true
echo "已上锁。注意：以后更新必须先 sudo chflags noschg $M/*"
