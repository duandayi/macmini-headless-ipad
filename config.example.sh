# 复制到 ~/.config/sidecar/config.sh（权限 600）
# 说明：这个文件只被 sidecar-guard 读取，改完 5 秒内生效

# 虚拟屏名称。
# ⚠️ 第一次连接成功后，系统会记住「iPad 镜像到这块屏」，之后改名会丢失镜像配置。
VDISPLAY_NAME="iPadLink-HD"

# launchd 标签前缀（默认 com.dsh，装在系统级保护里时有意义）
LABEL_PREFIX="com.dsh"

# 绑定设备 UUID —— 强烈建议填。
# 获取：sidecarctl list    →  复制 id= 后面那一串
# 填了之后只连这一台；别人的 iPad（哪怕同一账号下的另一台）也不会被连上。
SIDECAR_DEVICE_ID=""

# 想换默认分辨率？改 src/vdisplay.m 里的多档数组，或直接用菜单栏切换。
