#!/bin/bash
# 将 scripts/team.env 中的 Team / Bundle ID 写入 Xcode 工程
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PBXPROJ="$ROOT/jimanman.xcodeproj/project.pbxproj"

if [[ ! -f "$SCRIPT_DIR/team.env" ]]; then
  echo "请先创建 scripts/team.env（可复制 team.env.example）" >&2
  exit 1
fi

# shellcheck disable=SC1091
source "$SCRIPT_DIR/team.env"

if [[ -z "${TEAM_ID:-}" ]]; then
  echo "team.env 中 TEAM_ID 为空，请填入考星教育 Team ID" >&2
  exit 1
fi

BUNDLE_ID="${BUNDLE_ID:-com.gaoshub.jimanman}"

sed -i '' "s/DEVELOPMENT_TEAM = [^;]*/DEVELOPMENT_TEAM = $TEAM_ID/g" "$PBXPROJ"
sed -i '' "s/PRODUCT_BUNDLE_IDENTIFIER = [^;]*/PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID/g" "$PBXPROJ"

echo "✅ 已更新 Xcode 工程"
echo "   DEVELOPMENT_TEAM = $TEAM_ID"
echo "   PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID"
[[ -n "${TEAM_NAME:-}" ]] && echo "   团队: $TEAM_NAME"
