# 绩满满 iOS App Store 上架材料清单

> 适用版本：1.0 (Build 1)  
> 更新日期：2026-08-07  
> 主体：天津考星科技有限公司（Tianjin Kaoxing Technology Co.,Ltd.）

---

## 一、上架前必做（按优先级）

| 序号 | 事项 | 状态 | 说明 |
|------|------|------|------|
| 1 | Apple Developer 付费账号 | ☐ | 公司账号，Team ID: `QNC87AZURH` |
| 2 | App Store Connect 创建 App | ☐ | Bundle ID: `com.gaoshub.jimanman` |
| 3 | **APP 备案（工信部）** | ☐ | iOS 需填 Bundle ID + 公钥 + SHA-1，见下文 |
| 4 | **微信支付改 IAP 或隐藏储值** | ⚠️ 重要 | 虚拟商品/会员储值走微信支付，易被 App Store 拒审 |
| 5 | 隐私政策 URL 可公网访问 | ☐ | 见下文链接 |
| 6 | Universal Link 配置 | ☐ | `https://ad.91jmm.com/jimanman/` + AASA 文件 |
| 7 | 微信开放平台移动应用审核 | ☐ | AppID: `wx25240f7addf5c344` |
| 8 | 截图 + 1024 图标 | ☐ | 见下文规格 |
| 9 | 测试账号 | ☐ | 供审核员登录体验 |
| 10 | 打 App Store 包并上传 | ☐ | `./scripts/build_ipa.sh --app-store` |

---

## 二、App 基本信息（App Store Connect）

| 字段 | 填写内容 |
|------|----------|
| 名称 | 绩满满 |
| 副标题（30字内） | 大学生绩点提升与 AI 学业助手 |
| Bundle ID | `com.gaoshub.jimanman` |
| SKU | `jimanman-ios`（自定义，唯一即可） |
| 主要语言 | 简体中文 |
| 类别（主） | 教育 |
| 类别（次） | 效率 或 参考 |
| 内容版权 | © 2026 天津考星科技有限公司 |
| 年龄分级 | 4+（无暴力/赌博/成人内容） |
| 价格 | 免费 |

---

## 三、文案材料（可直接复制）

### 3.1 推广文本（170字内，可选）

```
绩满满专注大学生绩点提升与学业规划，提供 AI 答疑、GPA 计算、学习能力测评等功能，助力高效学习。
```

### 3.2 描述（4000字内）

```
绩满满是面向大学生的学业提升工具，由原「高数帮」品牌升级而来，由天津考星科技有限公司运营。

【核心功能】
• AI 答疑：拍照或输入题目，获取 AI 学习辅导
• GPA 计算：支持多种绩点算法，快速估算成绩
• 学习能力测试：多维度测评并生成报告
• 我的课程：查看已购课程（跳转浏览器）
• 个人中心：管理账号、答疑记录、会员与订单

【适用人群】
在校大学生、考研备考学生及有绩点提升需求的用户。

【登录方式】
支持微信授权登录。

【联系我们】
客服 QQ：942210353
邮箱：2636239710@qq.com
```

### 3.3 关键词（100字符内，逗号分隔）

```
绩满满,绩点,GPA,AI答疑,大学生,学习,测评,高数,考研,学业规划
```

### 3.4 技术支持 URL

```
https://ad.91jmm.com/api/article/user
```

（建议后续替换为独立帮助页，当前可用用户协议页）

### 3.5 营销 URL（可选）

```
https://ad.91jmm.com
```

### 3.6 隐私政策 URL（必填）

```
https://ad.91jmm.com/api/article/ysxy
```

---

## 四、截图与图标

### 4.1 App 图标

- 已有：`jimanman/Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- App Store 要求：**1024×1024 PNG，无透明、无圆角**

### 4.2 截图尺寸（iPhone 6.7 寸必传）

| 设备 | 尺寸 | 数量 |
|------|------|------|
| iPhone 6.7" | 1290 × 2796 | 3~10 张 |
| iPhone 6.5" | 1284 × 2778 | 建议一并准备 |
| iPad Pro 12.9"（若支持 iPad） | 2048 × 2732 | 可选 |

**建议截图页面：**
1. 首页（四大功能入口）
2. AI 答疑对话页
3. GPA 计算器
4. 学习能力测评
5. 个人中心（已登录状态）

> 截图不要含状态栏虚假信息、不要含「测试」「Debug」字样。

---

## 五、App 隐私（App Store Connect 问卷）

根据当前代码，建议勾选如下（以实际上线功能为准）：

| 数据类型 | 是否收集 | 用途 | 是否关联用户 |
|----------|----------|------|--------------|
| 姓名/昵称 | 是 | 账号展示 | 是 |
| 头像 | 是 | 个人资料 | 是 |
| 用户 ID | 是 | 登录与业务 | 是 |
| 照片 | 是 | AI 答疑拍照/相册 | 是 |
| 设备 ID | 可能 | 由第三方 SDK 收集 | 视 SDK 而定 |
| 购买记录 | 是 | 订单/会员 | 是 |

**第三方 SDK：**
- 微信 Open SDK（登录、支付）
- 后端 AI 服务（通义千问，见隐私政策）

**跟踪（Tracking）：** 当前未见 ATT 广告跟踪，一般选「否」。

---

## 六、审核备注（Review Notes，英文或中文均可）

```
测试账号：（请填写可用微信登录的测试账号，或提供 Demo 登录方式）

功能说明：
1. 登录：点击「我的」→ 登录，使用微信授权。
2. AI 答疑：底部 Tab「答疑」→ 输入或拍照提问。
3. GPA：首页 → GPA 计算。
4. 测评：首页 → 学习能力测试。
5. 我的课程：首页 → 我的课程，将在 Safari 打开外部课程页。

微信登录需安装微信 App。Universal Link 域名：ad.91jmm.com。

如审核员无法使用微信登录，请联系开发者提供备用测试方式。
```

---

## 七、ICP / APP 备案信息（iOS）

| 字段 | 值 |
|------|-----|
| 应用名称 | 绩满满 |
| Bundle ID | `com.gaoshub.jimanman` |
| 运营主体 | 天津考星科技有限公司 |
| 注册地址 | 天津市红桥区咸阳路29号中保财信大厦9楼9010052 |
| 签名 SHA-1 | `AA:03:B1:39:07:6F:FA:9F:DF:C1:CE:10:24:00:E1:BE:23:05:85:BF` |
| 签名 SHA-1（无冒号） | `AA03B139076FFA9FDFC1CE102400E1BE230585BF` |
| 公钥（模数 HEX） | 见 `docs/APP_STORE_METADATA.txt` |

> 证书类型为 Distribution Managed，Developer 网页无法下载 .cer，以上从 IPA 提取，与上架签名一致。

---

## 八、签名与证书

| 项目 | 值 |
|------|-----|
| Apple ID | tianaoteam@126.com |
| Team ID | QNC87AZURH |
| Team 名称 | Tianjin Kaoxing Technology Co.,Ltd. |
| Bundle ID | com.gaoshub.jimanman |
| 签名证书 | Apple Distribution: Tianjin Kaoxing Technology Co.,Ltd. |
| 证书有效期 | 2026-07-07 ~ 2027-07-07 |
| Entitlements | Associated Domains: `applinks:ad.91jmm.com` |
| 最低系统 | iOS 15.0 |

---

## 九、权限说明（Info.plist 已有）

| 权限 | 文案 |
|------|------|
| 相机 | 需要访问相机以拍摄题目进行AI答疑 |
| 相册读取 | 需要访问相册以选择图片进行AI答疑 |
| 相册写入 | 需要保存测评报告到您的文件 |

---

## 十、打包与上传 App Store

### 方式 A：脚本（推荐）

```bash
cd jimanman/jimanman
./scripts/build_ipa.sh --app-store
```

输出：`build/ipa/jimanman.ipa`（App Store 包）

### 方式 B：Xcode 图形界面

1. Product → Archive
2. Distribute App → App Store Connect → Upload
3. 勾选 Upload symbols

### 上传后

1. 登录 [App Store Connect](https://appstoreconnect.apple.com)
2. 选择构建版本 → 填写截图/描述/隐私
3. 提交审核

---

## 十一、高风险项（上架前必须确认）

### ⚠️ 1. 微信支付储值（Guideline 3.1.1）

当前「会员中心 → 储值」使用 **微信支付** 购买虚拟商品/服务。

Apple 要求 App 内数字内容必须使用 **Apple IAP（内购）**。否则大概率被拒。

**可选方案：**
- A. iOS 版改为 Apple IAP，Android 继续微信支付
- B. iOS 版暂时隐藏「储值/会员购买」，仅保留已购内容查看
- C. 改为外链购买（仍有限制，虚拟内容外链也常被拒）

### ⚠️ 2. 小鹅通课程外链

「我的课程」跳转 Safari 打开外部网页，一般可接受；但若页面内仍有微信支付购买虚拟课程，可能连带审核风险。

### ⚠️ 3. AI 内容合规

AI 答疑需确保有内容审核机制，隐私政策中已声明使用通义千问，需与实际一致。

### ⚠️ 4. 测试登录

审核员未必有微信环境，建议准备：
- 备用测试账号机制，或
- 在 Review Notes 说明如何完成登录

---

## 十二、材料文件夹建议

```
docs/appstore/
├── APP_STORE_METADATA.txt      # 可复制字段
├── screenshots/                # 1290x2796 截图
├── icon-1024.png               # 商店图标
├── review-notes.txt            # 审核备注
└── test-account.txt            # 测试账号（勿提交 git）
```

---

## 十三、联系人信息（App Store Connect）

| 角色 | 建议填写 |
|------|----------|
| 版权方 | 天津考星科技有限公司 |
| 联系人 | 李青松（或实际负责人） |
| 电话 | 17316243850 |
| 邮箱 | tianaoteam@126.com |

---

**下一步建议：**
1. 确认储值功能 iOS 处理方案（IAP 或隐藏）
2. 补截图与 1024 图标
3. 完成 APP 备案
4. 打 `--app-store` 包上传 TestFlight 内测
5. 内测通过后提交 App Store 审核
