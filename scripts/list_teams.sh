#!/bin/bash
# 列出当前 Xcode 已识别的开发者 Team
set -euo pipefail

echo "当前 Xcode 账号下的 Team："
echo ""

plutil -p ~/Library/Preferences/com.apple.dt.Xcode.plist 2>/dev/null \
  | awk '
    /teamID/ { gsub(/.*=> "/, ""); gsub(/".*/, ""); id=$0 }
    /teamName/ { gsub(/.*=> "/, ""); gsub(/".*/, ""); name=$0 }
    /teamType/ { gsub(/.*=> "/, ""); gsub(/".*/, ""); type=$0; if (id != "") { printf "  • %s\n    Team ID: %s\n    类型: %s\n\n", name, id, type; id="" } }
  '

if ! plutil -p ~/Library/Preferences/com.apple.dt.Xcode.plist 2>/dev/null | grep -q 'Kaoxing'; then
  cat <<'EOF'
⚠️  未检测到「Tianjin Kaoxing Technology Co., Ltd.」

请按以下步骤同步考星教育 Team：

1. 打开 Xcode → Settings → Accounts
2. 选中 tianaoteam@126.com
3. 点击右下角「Download Manual Profiles」
4. 若仍只有 Wanglu，请：
   - 登录 https://developer.apple.com/account
   - 右上角切换到「Tianjin Kaoxing Technology Co., Ltd.」
   - 完成协议签署（如有）
   - 回到 Xcode 重新登录或再次 Download Profiles

5. 在 developer.apple.com 的 Membership Details 复制 Team ID
6. 创建配置文件：
   cp scripts/team.env.example scripts/team.env
   # 编辑 scripts/team.env，填入 TEAM_ID=你的TeamID

7. 重新执行：./scripts/build_ipa.sh
EOF
fi
