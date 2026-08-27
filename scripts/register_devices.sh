#!/bin/bash
# 列出 scripts/devices.txt 中的测试设备，并给出 Apple Developer 注册链接
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEVICES_FILE="$SCRIPT_DIR/devices.txt"

echo "==> 测试设备列表（须加入 Apple Developer → Devices 后重新打包）"
echo ""

if [[ ! -f "$DEVICES_FILE" ]]; then
  echo "未找到 $DEVICES_FILE"
  echo "格式: 设备名<TAB>UDID"
  exit 1
fi

while IFS=$'\t ' read -r name udid _; do
  [[ -z "${udid:-}" || "$name" =~ ^# ]] && continue
  printf "  • %-20s %s\n" "${name:-Device}" "$udid"
done < "$DEVICES_FILE"

cat <<'EOF'

添加设备：
  https://developer.apple.com/account/resources/devices/list
  Team: QNC87AZURH (Tianjin Kaoxing Technology Co.,Ltd.)

添加或修改 UDID 后重新打包：
  ./scripts/build_ipa.sh --skip-device

上传蒲公英：
  PGYER_API_KEY=你的key ./scripts/build_ipa.sh --skip-device --upload

EOF
