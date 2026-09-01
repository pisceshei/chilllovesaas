# G6 步 11：買家帳戶線（passwordless OTP＋/account 家族）

> 正典＝`docs/research/74-admin-customers.md` §7（新版帳號形：無密碼、6 位驗證碼、
> 刪除後同 email 再登入自動重建、365 天上限）。OTP 信走步 6 通知鏈
> （`docs/dev/g6-notifications.md`）。

## 1. 流程

GET /account/login（email 表單）→ POST /account/login（發碼：CustomerOtp.issue!
→ DeliverJob customer_otp 分支——模板 `config/notification_templates/customer_otp.liquid`）
→ POST /account/verify（CustomerOtp.verify!：digest secure_compare／expires／
attempts／consumed_at 四防線）→ 未註冊 email **自動建 profile**（normalize_email
同一定義點——74 §7）→ CustomerSession.issue!（365 天＝limits customer.session_days）
→ 簽名 host-only cookie `_cl_customer` → /account。

## 2. 防線（突變紅證逐條）

- 嘗試上限（otp_max_attempts=5；6 位碼空間小，不限次＝可枚舉——MO1）。
- 重發冷卻（otp_resend_cooldown_s=60——MO2）；效期（otp_expiry_minutes=10——MO3）。
  🔴 三值＝ours 保守值（官方數字未取得，19.3 誠實標註 limits 註釋）。
- consumed_at 防重放（MO4）；**session 過期雙防線**：cookie expires（客戶端）＋
  DB expires_at（`CustomerSession.authenticate`——被竊 token 的唯一防線；MO5 的
  測試教訓：travel 下 rack-test cookie 先過期會遮蔽 DB 層 ⇒ model 級直測）。
- 發碼回應不洩漏 email 存在性（一律進驗證頁——枚舉防護同軸）。

## 3. /account 家族與整合

- 非主題化頁（checkout 同法）：/account（訂單史，單連 thank-you 頁）＋
  /account/addresses（唯讀 v1）＋login/verify/logout。
- 結帳整合：Sign in 死鏈收口（→/account/login）；show 預填——email **空才填**
  （不覆蓋手動輸入，MO6）＋customer_id 掛載＋預設地址預填（shipping_address
  空時）。
- 主題引擎：`customer` **顯式 nil stub**——主題頁走頁快取（14 §F1-4 個人化不進
  快取）；登入態注入需快取鍵分票（91 §3.57）。nil＝Ella {% if customer %}
  全走未登入分支（快取頁的正確形）。

## 4. v1 邊界（91 §3.57）

Shop/社群/passkey 登入、OIDC（Plus）、升級 30 天還原、Multipass——74 §7 記載的
其餘形態 ⚪；storefront 地址 CRUD ⚪；OTP code 過境 Solid Queue arguments 的
風險面已註 DeliverJob。
