# App Store 拒绝回复稿（2026-10-17）

Submission: `9ca5b20b-3537-4dca-a490-0649b0e2f343`  
Version reviewed: 1.0 (14) · iPad Air 11-inch (M3) · iPadOS 27.2

请在 App Store Connect 用**新包 1.0 (19)** 重提，并改 Support URL。下面可直接贴到 Resolution Center。

---

## 提交前必做

1. **App 信息 → 技术支持 URL** 改为：  
   `https://ad.91jmm.com/api/article/support`  
   用 Safari 打开确认能看到电话、邮箱、FAQ，而不是官网首页。
2. 把后端 `app/api/view/article/support.html` 发到 `ad.91jmm.com`（当前线上该路径已是 200，发版后 FAQ 会改成手机号登录说明）。
3. **审核备注**填入一个真实可用的大陆手机号 + 密码（密码登录）。不要再写微信 / Apple 登录。
4. 上传 build **19**。

---

## Resolution Center（英文）

Hello App Review team,

Thank you for the feedback on 1.0 (14). We have addressed both issues in 1.0 (19).

**Guideline 1.5 – Support URL**  
The previous Support URL `https://www.91jmm.com/` pointed at our marketing homepage (a JavaScript SPA), which could appear non-functional. We have changed the Support URL to a dedicated, server-rendered support page:

https://ad.91jmm.com/api/article/support

It includes phone, email, address, and FAQ. Please use this URL in App Store Connect.

**Guideline 2.1(a) – Login on iPad**  
Sign-in is phone number + password or SMS. WeChat and Sign in with Apple are not used. The Home tab does not require login.

We fixed iPad login as follows:
- Replaced SwiftUI `Link` (known to fail on iPad) with Safari buttons
- Validation text is inline instead of a blocking alert
- Added “Browse first” so reviewers can leave the login page
- Login form is width-constrained on iPad

A demo phone + password is in the Review Notes. Please tap 我的 → login header → check the agreement → 密码登录.

Please review this new binary. Thank you.

---

## Resolution Center（中文，可选）

您好，感谢审核反馈。1.0 (19) 已处理：

1. Support URL 已改为独立支持页 https://ad.91jmm.com/api/article/support （不再使用官网 SPA 首页）。
2. iPad 登录：去掉易出错的 Link/弹窗；支持先浏览首页；审核备注提供手机号+密码。首页 GPA/科目登记无需登录。

请审核新二进制。谢谢。
