# SideLinker 本地 API 配置
# 安装脚本会自动生成 ~/.config/sidecar/config.sh，一般不需要手改这里。
#
# SideLinker Mac 的本地 API 默认监听 127.0.0.1:14792，需要 Bearer token。
# token 在 SideLinker 的「设置 → 本地 API / 集成」里能看到。
SIDELINKER_API="http://127.0.0.1:14792"
SIDELINKER_TOKEN="把你的_token_填这里"

# 虚拟屏名称（需与 SideLinker 里配置的虚拟屏名称一致）
VDISPLAY_NAME="SideLinker-HD"

# 逻辑分辨率（实际面板 = 逻辑 × 2）
LOGICAL_W=1323
LOGICAL_H=919
