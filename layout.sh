#!/bin/bash
# 用法:
#   ./layout.sh save <名称>    把当前所有接入显示器的排列+分辨率保存为预设
#   ./layout.sh apply <名称>   应用预设（所需显示器未全部接入时拒绝并提示）
#   ./layout.sh list           列出所有预设
#   ./layout.sh migrate        把旧版 .args 预设迁移为 .json
exec /usr/bin/python3 "$(cd "$(dirname "$0")" && pwd)/preset.py" "$@"