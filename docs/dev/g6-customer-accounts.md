# G6 步 11：買家帳戶線（passwordless OTP＋/account 家族）

> 正典＝`docs/research/74-admin-customers.md` §7＋`docs/research/89` §9（步 11
> 補課：官方硬數字三個〔6 位碼/365 天/30 天回退〕、hosted 登入頁實測逐字、
> customer Liquid 物件屬性正典、NIST/OWASP 取值依據）。OTP 信走步 6 通知鏈。

## 1. 流程

GET /account/login（email 表單）→ POST /account/login（發碼：CustomerOtp.issue!
→ DeliverJob customer_otp 分支——模板 `config/notification_templates/customer_otp.liquid`）
→ POST /account/verify（CustomerOtp.verify!：digest secure_compare／expires／
attempts／consumed_at 四防線）→ 未註冊 email **自動建 profile**（normalize_email
同一定義點——74 §7）→ CustomerSession.issue!（365 天＝limits customer.session_days）
→ 簽名 host-only cookie `_cl_customer` → /account。

## 2. 防線（突變紅證逐條）

- 嘗試上限（otp_max_attempts=5；6 位碼 ≈19.9 bits＝NIST 熵下限邊緣，不限次＝
  可枚舉——MO1）。重發冷卻（60s——MO2）；效期（10 分——MO3）。
  🔴 三值官方未公布 ⇒ 取值依 **NIST SP 800-63B**（≤10 分失效/失敗節流）＋
  **OWASP**（per-account 限流）——89 §9（步 11 補課升級「ours 保守」為有據值）。
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
