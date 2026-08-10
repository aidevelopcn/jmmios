#!/bin/bash
# 绩满满 iOS 打包脚本
# 用法: ./scripts/build_ipa.sh [选项]
#
# 示例:
#   ./scripts/build_ipa.sh              # Ad Hoc 打包（蒲公英内测）
#   ./scripts/build_ipa.sh --app-store  # App Store 打包（上传 App Store Connect）
#   ./scripts/build_ipa.sh --clean      # 清理后打包
#   ./scripts/build_ipa.sh --upload     # 打包并上传蒲公英（需设置 PGYER_API_KEY）
#   PGYER_API_KEY=xxx ./scripts/build_ipa.sh --upload

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# 优先读取 scripts/team.env（考星教育等正式配置）
if [[ -f "$SCRIPT_DIR/team.env" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/team.env"
fi

# ── 默认配置（可按项目修改）────────────────────────────
SCHEME="jimanman"
CONFIGURATION="Release"
TEAM_ID="${TEAM_ID:-FM7YXM5TQM}"
BUNDLE_ID="${BUNDLE_ID:-com.wllives.testjmm}"
TEAM_NAME="${TEAM_NAME:-}"
EXPORT_METHOD="ad-hoc"          # ad-hoc | development | app-store
EXPORT_OPTIONS_TEMPLATE=""
ENTITLEMENTS="jimanman/jimanman.entitlements"

ARCHIVE_PATH="./build/jimanman.xcarchive"
EXPORT_DIR="./build/ipa"
EXPORT_OPTIONS="./build/ExportOptions.generated.plist"
OUTPUT_IPA="./build/ipa/jimanman.ipa"

DO_CLEAN=false
DO_UPLOAD=false
SKIP_DEVICE_BUILD=false

# ── 参数解析 ────────────────────────────────────────────
usage() {
  cat <<EOF
绩满满 iOS IPA 打包脚本

用法:
  $(basename "$0") [选项]

选项:
  -h, --help          显示帮助
  -c, --clean         打包前清理 build 目录
  -m, --method TYPE   导出方式: ad-hoc（默认）| development | app-store
  --app-store         等同于 --method app-store（上传 App Store Connect）
  -u, --upload        打包成功后上传蒲公英（需环境变量 PGYER_API_KEY）
  --skip-device       跳过真机预构建（已手动注册 UDID 时可加快速度）

环境变量:
  PGYER_API_KEY       蒲公英 API Key（配合 --upload 使用）
  TEAM_ID             开发者 Team ID（也可写入 scripts/team.env）
  BUNDLE_ID           Bundle Identifier（也可写入 scripts/team.env）

配置文件:
  scripts/team.env    复制 team.env.example 并填入考星教育 Team ID

输出:
  IPA 文件: $OUTPUT_IPA

当前配置:
  Scheme:     $SCHEME
  Team ID:    $TEAM_ID
  Bundle ID:  $BUNDLE_ID
  导出方式:   $EXPORT_METHOD
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -c|--clean) DO_CLEAN=true; shift ;;
    -u|--upload) DO_UPLOAD=true; shift ;;
    --skip-device) SKIP_DEVICE_BUILD=true; shift ;;
    --app-store) EXPORT_METHOD="app-store"; shift ;;
    -m|--method)
      EXPORT_METHOD="$2"
      if [[ "$EXPORT_METHOD" != "ad-hoc" && "$EXPORT_METHOD" != "development" && "$EXPORT_METHOD" != "app-store" ]]; then
        echo "错误: --method 仅支持 ad-hoc、development 或 app-store" >&2
        exit 1
      fi
      shift 2
      ;;
    *) echo "未知参数: $1（使用 --help 查看帮助）" >&2; exit 1 ;;
  esac
done

# ── 工具函数 ────────────────────────────────────────────
pick_physical_device_id() {
  xcrun xctrace list devices 2>/dev/null \
    | grep -v Simulator \
    | grep -viE 'Mac mini|MacBook|iMac|Mac Pro|Mac Studio' \
    | sed -n 's/.*(\([0-9A-F-]{36}\)).*/\1/p' \
    | head -1
}

xcode_has_team() {
  local tid="$1"
  local plist="$HOME/Library/Preferences/com.apple.dt.Xcode.plist"
  [[ -f "$plist" ]] || return 1
  local content
  content="$(plutil -p "$plist" 2>/dev/null)" || return 1
  [[ "$content" == *"$tid"* ]]
}

verify_team_available() {
  if [[ -n "$TEAM_ID" ]] && ! xcode_has_team "$TEAM_ID"; then
    cat <<EOF >&2

❌ Xcode 未识别 Team ID: $TEAM_ID
${TEAM_NAME:+   目标团队: $TEAM_NAME}

请先同步开发者账号：
  1. Xcode → Settings → Accounts → tianaoteam@126.com
  2. 点击「Download Manual Profiles」
  3. 登录 https://developer.apple.com/account
     右上角切换到考星教育公司，完成协议签署
  4. 在 Membership Details 复制 Team ID，写入 scripts/team.env

查看当前已识别 Team：
  ./scripts/list_teams.sh

EOF
    exit 1
  fi
}

print_fail_help() {
  cat <<EOF

❌ 打包失败。常见原因：

1. 未注册测试设备
   - 连接 iPhone，Xcode 选真机 Run 一次
   - 或在 https://developer.apple.com/account/resources/devices/list 添加 UDID

2. Bundle ID 不可用
   - 当前: $BUNDLE_ID
   - 登录开发者后台确认 Identifiers 已创建

3. 签名 / Team 错误
   - 当前 Team: $TEAM_ID
   - Xcode → Settings → Accounts 确认已登录公司账号

EOF
}

generate_export_options() {
  mkdir -p "$(dirname "$EXPORT_OPTIONS")"
  if [[ "$EXPORT_METHOD" == "app-store" && -f "./build/ExportOptions.appstore.plist" ]]; then
    cp "./build/ExportOptions.appstore.plist" "$EXPORT_OPTIONS"
    /usr/libexec/PlistBuddy -c "Set :teamID ${TEAM_ID}" "$EXPORT_OPTIONS" 2>/dev/null \
      || /usr/libexec/PlistBuddy -c "Add :teamID string ${TEAM_ID}" "$EXPORT_OPTIONS"
    return
  fi
  cat > "$EXPORT_OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>${EXPORT_METHOD}</string>
	<key>teamID</key>
	<string>${TEAM_ID}</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>compileBitcode</key>
	<false/>
</dict>
</plist>
PLIST
}

read_ipa_info() {
  local tmp
  tmp="$(mktemp -d)"
  unzip -q "$OUTPUT_IPA" -d "$tmp" 2>/dev/null || return 1
  plutil -p "$tmp"/Payload/*.app/Info.plist 2>/dev/null \
    | grep -E 'CFBundleDisplayName|CFBundleIdentifier|CFBundleShortVersionString|CFBundleVersion|MinimumOSVersion' \
    || true
  rm -rf "$tmp"
}

upload_to_pgyer() {
  local api_key="${PGYER_API_KEY:-}"
  if [[ -z "$api_key" ]]; then
    echo "⚠️  未设置 PGYER_API_KEY，跳过上传。示例:" >&2
    echo "   PGYER_API_KEY=你的key ./scripts/build_ipa.sh --upload" >&2
    return 1
  fi
  echo "==> 上传蒲公英..."
  local resp
  resp="$(curl -sf -F "file=@${OUTPUT_IPA}" -F "_api_key=${api_key}" https://www.pgyer.com/apiv2/app/upload)" \
    || { echo "上传失败，请检查网络或 API Key" >&2; return 1; }
  if echo "$resp" | grep -q '"code":0'; then
    echo "✅ 上传成功"
    echo "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin).get('data', {})
if d.get('buildShortcutUrl'):
    print('   安装页: https://www.pgyer.com/' + d['buildShortcutUrl'])
if d.get('buildQRCodeURL'):
    print('   二维码: ' + d['buildQRCodeURL'])
" 2>/dev/null || echo "$resp"
  else
    echo "上传失败: $resp" >&2
    return 1
  fi
}

# ── 主流程 ──────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  绩满满 iOS 打包"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Team ID:   $TEAM_ID"
echo "  Bundle ID: $BUNDLE_ID"
[[ -n "$TEAM_NAME" ]] && echo "  团队:      $TEAM_NAME"
echo ""

verify_team_available

if $DO_CLEAN; then
  echo "==> 清理 build 目录..."
  rm -rf ./build/jimanman.xcarchive ./build/ipa ./build/DerivedData
fi

mkdir -p build "$EXPORT_DIR"
generate_export_options

if ! $SKIP_DEVICE_BUILD; then
  DEVICE_ID="$(pick_physical_device_id || true)"
  if [[ -n "$DEVICE_ID" ]]; then
    echo "==> [0/3] 检测到真机 ($DEVICE_ID)，预构建以更新描述文件..."
    xcodebuild \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -destination "id=$DEVICE_ID" \
      DEVELOPMENT_TEAM="$TEAM_ID" \
      PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
      CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
      -allowProvisioningUpdates \
      build
    echo ""
  else
    echo "⚠️  未连接 iPhone，跳过预构建（需已在开发者后台注册 UDID）"
    echo ""
  fi
fi

echo "==> [1/3] Archive（$CONFIGURATION）..."
if ! xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGN_ENTITLEMENTS="$ENTITLEMENTS" \
  -allowProvisioningUpdates \
  archive; then
  print_fail_help
  exit 1
fi

echo ""
echo "==> [2/3] 导出 IPA（$EXPORT_METHOD）..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates

FOUND_IPA="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
if [[ -z "$FOUND_IPA" ]]; then
  echo "❌ 未找到 IPA 文件" >&2
  exit 1
fi

# 统一输出路径（源/目标相同时 cp 可能返回非 0，忽略）
cp -f "$FOUND_IPA" "$OUTPUT_IPA" || [[ "$FOUND_IPA" -ef "$OUTPUT_IPA" ]]

echo ""
echo "==> [3/3] 完成"
echo ""
echo "✅ 打包成功"
echo "   文件: $(cd "$(dirname "$OUTPUT_IPA")" && pwd)/$(basename "$OUTPUT_IPA")"
echo "   大小: $(du -h "$OUTPUT_IPA" | cut -f1)"
echo ""
read_ipa_info | sed 's/^/   /'
echo ""
if [[ "$EXPORT_METHOD" == "app-store" ]]; then
  echo "📦 App Store 包已生成，下一步："
  echo "  1. Xcode → Organizer → Distribute App → Upload"
  echo "  或 Transporter 上传: $OUTPUT_IPA"
  echo "  2. App Store Connect 选择构建版本并提交审核"
  echo "  3. 材料清单: docs/APP_STORE_SUBMISSION.md"
else
  echo "⚠️  Ad Hoc / Development 包仅已注册 UDID 的设备可安装。"
  echo ""
  if $DO_UPLOAD; then
    upload_to_pgyer || true
  else
    echo "上传蒲公英:"
    echo "  网页: https://www.pgyer.com （拖入 IPA）"
    echo "  命令: PGYER_API_KEY=你的key $0 --upload"
  fi
fi
echo ""
