# 绩满满 iOS

Bundle ID: `com.gaoshub.jimanman`  
Team ID: `QNC87AZURH`

## 本地打包

```bash
cp scripts/team.env.example scripts/team.env   # 填入 Team ID
./scripts/build_ipa.sh              # Ad Hoc（蒲公英）
./scripts/build_ipa.sh --app-store  # App Store
```

## Codemagic 云端打包

1. 在 [Codemagic](https://codemagic.io) 连接本仓库
2. 按 `docs/CODEMAGIC_GUIDE.md` 配置 App Store Connect API Key
3. 设置环境变量组 `app_store_credentials`、`certificate_credentials`
4. Start build → workflow **绩满满 App Store**

详细说明见 `docs/CODEMAGIC_GUIDE.md`、`docs/APP_STORE_SUBMISSION.md`。
