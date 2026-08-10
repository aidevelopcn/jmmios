# jimanman iOS 打包指南

## 📦 一键打包脚本

### 快速开始

```bash
# 进入项目目录
cd /Users/mac/Desktop/jimanman/jimanman_ios/jimanman/jimanman

# 执行打包脚本
./scripts/build_ipa.sh
```

### 打包流程

脚本会自动完成以下步骤：

1. ✅ **检查依赖** - 验证 xcodebuild 和项目配置
2. 🧹 **清理旧构建** - 删除旧的构建文件
3. 📦 **归档项目** - 生成 .xcarchive 文件
4. 📱 **导出 IPA** - 根据 ExportOptions.plist 配置导出
5. 📄 **保存日志** - 记录完整的构建日志

### 输出文件

打包完成后，文件会保存在：

```
build/
├── jimanman.xcarchive/     # 归档文件
├── ipa/                     # IPA 导出目录
│   └── jimanman.ipa         # 最终的 IPA 文件
└── build_YYYYMMDD_HHMMSS.log  # 构建日志
```

---

## ⚙️ 配置说明

### ExportOptions.plist

当前配置（Ad-Hoc 分发）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>FM7YXM5TQM</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

### 分发方式

根据需要修改 `method`：

| 方式 | 说明 |
|------|------|
| `app-store` | 上传到 App Store |
| `ad-hoc` | 内部分发（当前） |
| `enterprise` | 企业分发 |
| `development` | 开发测试 |

---

## 🔧 常见问题

### 1. 签名错误

**错误信息**：
```
No signing certificate "iOS Distribution" found
```

**解决方案**：
- 打开 Xcode → Preferences → Accounts
- 登录开发者账号
- 确保 Team ID `FM7YXM5TQM` 正确
- 检查证书和描述文件是否有效

### 2. 方案不存在

**错误信息**：
```
xcodebuild: error: Scheme XXX is not currently configured
```

**解决方案**：
```bash
# 查看可用方案
xcodebuild -list -project jimanman.xcodeproj

# 确保在 Xcode 中共享了方案
# Xcode → Product → Scheme → Manage Schemes → 勾选 Shared
```

### 3. 清理构建缓存

```bash
# 手动清理
rm -rf ~/Library/Developer/Xcode/DerivedData/jimanman-*
rm -rf build/

# 重新打包
./scripts/build_ipa.sh
```

---

## 📝 高级用法

### 自定义输出目录

编辑 `scripts/build_ipa.sh`，修改：

```bash
BUILD_DIR="${PROJECT_DIR}/build"  # 改为你的路径
```

### 自动上传到分发平台

在 `export_ipa()` 函数后添加上传逻辑：

```bash
# 示例：上传到 Firm
IPA_PATH="${IPA_EXPORT_PATH}/${PROJECT_NAME}.ipa"
curl -F "file=@${IPA_PATH}" https://api.fir.im/apps
```

---

## 🎯 快速命令

```bash
# 查看项目信息
xcodebuild -list -project jimanman.xcodeproj

# 清理构建
xcodebuild clean -project jimanman.xcodeproj -scheme jimanman

# 仅归档（不导出）
xcodebuild archive -project jimanman.xcodeproj -scheme jimanman \
    -configuration Release -archivePath ./build/jimanman.xcarchive

# 仅导出（使用已有的归档）
xcodebuild -exportArchive -archivePath ./build/jimanman.xcarchive \
    -exportPath ./build/ipa -exportOptionsPlist ExportOptions.plist
```

---

## 📞 需要帮助？

如果遇到问题：
1. 查看构建日志：`build/build_YYYYMMDD_HHMMSS.log`
2. 检查 Xcode 签名配置
3. 确保开发者账号有效

---

**祝打包顺利！** 🚀
