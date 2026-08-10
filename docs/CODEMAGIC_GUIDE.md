# Codemagic 使用指南（绩满满 iOS）

> 适用场景：本地 Mac 无法安装 Xcode 26，用云端 Mac 打 App Store 包并上传。

---

## 一、准备清单

| 项目 | 说明 |
|------|------|
| Git 仓库 | Codemagic 必须连 GitHub / GitLab / Bitbucket |
| Apple 开发者账号 | tianaoteam@126.com，Team: QNC87AZURH |
| App Store Connect 已建 App | Bundle ID: `com.gaoshub.jimanman` |
| App Store Connect API Key | 用于云端自动签名 + 上传 |

---

## 二、注册 Codemagic（免费）

1. 打开 https://codemagic.io/signup
2. 用 **GitHub** 或 **GitLab** 账号注册（推荐 GitHub）
3. 选择 **Personal account** → 每月 **500 分钟免费**（M2 Mac）

---

## 三、代码推到 GitHub

Codemagic 只能构建 Git 仓库里的代码。

```bash
# 在 jimanman_ios 或 jimanman/jimanman 目录
git init
git add .
git commit -m "init jimanman ios"
# 在 GitHub 新建私有仓库 jimanman-ios，然后：
git remote add origin git@github.com:你的用户名/jimanman-ios.git
git push -u origin main
```

> 建议用**私有仓库**（含签名配置说明时注意不要提交密钥）。

---

## 四、创建 App Store Connect API Key

1. 登录 https://appstoreconnect.apple.com
2. **用户和访问** → **集成** → **App Store Connect API**
3. 点 **+** 生成密钥
   - 名称：`Codemagic`
   - 访问权限：**App 管理**（App Manager）
4. **下载 `.p8` 文件**（只能下载一次，妥善保存）
5. 记录：
   - **Issuer ID**（页面顶部）
   - **Key ID**（密钥列表里）

---

## 五、在 Codemagic 配置密钥

### 5.1 创建环境变量组

Codemagic 网页 → **Teams** → 你的团队 → **Environment variables**

新建 Group：`app_store_credentials`，勾选 **Secure**，添加：

| 变量名 | 值 |
|--------|-----|
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect 的 Issuer ID |
| `APP_STORE_CONNECT_KEY_IDENTIFIER` | Key ID |
| `APP_STORE_CONNECT_PRIVATE_KEY` | 打开 `.p8` 文件，**完整复制**内容（含 BEGIN/END） |

新建 Group：`certificate_credentials`，添加：

| 变量名 | 值 |
|--------|-----|
| `CERTIFICATE_PRIVATE_KEY` | 见下方「生成证书私钥」 |

**生成证书私钥（终端执行一次）：**

```bash
openssl genrsa -out codemagic_private_key.pem 2048
```

把 `codemagic_private_key.pem` 的**全部内容**粘贴到 `CERTIFICATE_PRIVATE_KEY`。

### 5.2 关联 App Store Connect 集成（可选）

Teams → **Integrations** → **Developer Portal** → 上传同一个 API Key，名称填 `codemagic`。

---

## 六、添加应用并构建

### 方式 A：使用项目里的 `codemagic.yaml`（推荐）

1. Codemagic → **Add application**
2. 选择 GitHub 仓库 `jimanman-ios`
3. 选 **codemagic.yaml** 作为配置方式
4. 修改 `codemagic.yaml` 里的 `APP_STORE_APPLE_ID`：
   - App Store Connect → 绩满满 → **App 信息** → **Apple ID**（纯数字，如 `6738291021`）
5. 点 **Start new build** → 选 workflow **绩满满 App Store**

### 方式 B：纯网页 UI 配置（不写 yaml）

1. Add application → 选仓库
2. Platform：**iOS**
3. 配置：
   - Project: `jimanman.xcodeproj`
   - Scheme: `jimanman`
   - Bundle ID: `com.gaoshub.jimanman`
   - Xcode version: **latest**（即 Xcode 26）
4. **Distribution** → App Store
5. **Code signing** → Automatic（填入 API Key）
6. **Start build**

---

## 七、构建完成后

1. 在 Codemagic 构建页 **Artifacts** 下载 `.ipa`
2. 若配置了 `publishing.app_store_connect`，会自动上传到 App Store Connect
3. 也可手动用 **Transporter** 上传下载的 IPA
4. 登录 App Store Connect → **TestFlight** 等待处理 → 提交审核

---

## 八、费用说明

| 用量 | 费用 |
|------|------|
| 个人账号 ≤ 500 分钟/月 | **免费** |
| 单次 iOS 构建约 10~20 分钟 | 约可打 **25~50 次/月** |
| 超出免费额度 | 约 $0.095/分钟（M2） |

---

## 九、常见问题

### Q1: 构建失败「No signing certificate」
- 检查 API Key 权限是否为 **App Manager**
- 确认 `BUNDLE_ID` 与 App Store Connect 一致
- 在脚本里 `--create` 会自动创建证书，需 API Key 有足够权限

### Q2: 上传失败 SDK version
- 确认 `xcode: latest` 使用的是 Xcode 26（Codemagic 会跟进 Apple 要求）

### Q3: 第一次上传 App Store Connect 失败
- Apple 要求**首个版本**有时需先在 App Store Connect 手动创建 App 记录
- 确保 Bundle ID、名称、SKU 已建好

### Q4: 微信 SDK / Universal Link
- 云端打包不影响功能，但 Associated Domains 需在 Apple Developer 后台为 Bundle ID 开启

### Q5: 不想自动上传，只要 IPA
- 把 `codemagic.yaml` 里 `publishing.app_store_connect` 整段删掉
- 构建完成后从 Artifacts 下载 IPA

---

## 十、推荐流程（第一次）

```
1. GitHub 私有仓库推送代码
2. Codemagic 注册 + 配置 API Key
3. 修改 APP_STORE_APPLE_ID
4. Start build（约 15 分钟）
5. 下载 IPA 或自动上传 TestFlight
6. App Store Connect 补截图/描述 → 提交审核
```

---

## 相关文件

- `codemagic.yaml` — CI 配置
- `scripts/team.env` — 本地 Team ID（勿提交密钥）
- `docs/APP_STORE_SUBMISSION.md` — 上架材料清单
