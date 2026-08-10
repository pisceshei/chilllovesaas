# 12 — 功能規格：多租戶、認證、權限（生產級）

> 覆蓋功能：開店註冊、子網域路由、staff 登入/Session、邀請流程、角色權限、操作稽核。基線見 11。

## F1. 開店註冊與子網域路由

**生產級做法**：
1. 註冊表單：店名 → 自動生成 subdomain（可改）→ 建 Shop + owner StaffMember + 預設資料（General profile、預設 theme、notification 模板種子）——包成一個 `Shops::Provision` service、單一 transaction。
2. subdomain 規則：`/\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/`、全小寫、唯一索引；**保留字黑名單**（www、admin、api、mail、assets、cdn、status、help、blog…約 50 個）建常數表。
3. 路由解析：middleware 以 `request.host` 查 Shop（快取 5 分鐘）；查無 → 404 頁（不是 500）；主網域（無子網域）→ 平台官網/註冊頁。
4. 自訂網域（P1）：`custom_domains` 表 + CNAME 驗證 job + Kamal/反代的動態 TLS（P2 用 Caddy on-demand TLS 或 Cloudflare SaaS）。

**工具**：acts_as_tenant、Rails middleware、Solid Cache。

**代碼**：

```ruby
class ResolveShop
  RESERVED = %w[www admin api mail cdn assets status].freeze
  def call(env)
    req = ActionDispatch::Request.new(env)
    sub = req.subdomains.first
    return platform_response(env) if sub.blank? || RESERVED.include?(sub)
    shop = Rails.cache.fetch(["shop-by-host", req.host], expires_in: 5.minutes) {
      Shop.find_by(subdomain: sub) || Shop.joins(:custom_domains).find_by(custom_domains: {host: req.host, verified: true})
    }
    return [404, {}, [render_shop_not_found]] unless shop
    env["chilllove.shop_id"] = shop.id
    @app.call(env)
  end
end
```

**⚠️ 坑**：
- **Host header 欺騙**：一切以「host 查得到 Shop」為準，不要拿 `params[:shop]` 或 header 裡的自報身分做任何授權；`config.hosts` 允許 `.lvh.me` / 主網域 + 已驗證 custom domains。
- 保留字漏了 `admin`/`api` → 之後平台功能搶不回子網域；第一天就建全黑名單。
- subdomain 改名：舊子網域要 301 到新（redirect 表），且快取 key 要失效。
- Provision 半途失敗留殭屍店 → 全程單 transaction + 唯一索引兜底。

## F2. Staff 認證與 Session

**生產級做法**：
1. 用 Rails 8 內建 authentication generator 為底改多租戶：`staff_members`（email 對 shop 唯一）、`sessions` 表（DB session 記錄：token 雜湊、ip、user_agent、last_active_at）。
2. 密碼：`has_secure_password`（bcrypt cost 12）；密碼政策只設長度 ≥10，不搞複雜度規則。
3. 登入成功 → `reset_session`（防 session fixation）→ 寫 session 記錄；「登出所有裝置」= 刪該 staff 全部 session 列。
4. 找回密碼：`generates_token_for :password_reset, expires_in: 15.minutes`（Rails 內建簽名 token，單次有效）；回應永遠顯示「已寄出（若帳號存在）」。
5. 限流：登入每 IP 10 次/分 + 每帳號 10 次/10 分（rack-attack 雙鍵）；失敗訊息統一「帳號或密碼錯誤」。
6. admin cookie：名稱 `_cl_admin`、host-only、Secure、HttpOnly、SameSite=Lax；買家端另一顆 `_cl_buyer`（見 15）。
7. 2FA（P1）：TOTP（rotp gem）+ recovery codes；owner 可強制全店開啟（對齊 05 研究）。

**⚠️ 坑**：
- **帳號枚舉**：登入、註冊、找回三處的回應時間與文案都不能洩漏帳號存在性（bcrypt 比對即使查無帳號也跑一次 dummy hash，拉平時間差）。
- session token 明文入庫 → 一律存 SHA-256 摘要，查詢用摘要比對。
- 同一 email 在多店（多租戶常態）→ 唯一索引是 `(shop_id, email)` 不是全域 email；登入頁在店的 admin 網域下做，天然分租戶。
- remember me 的長效 cookie 要可撤銷（綁 sessions 列，不是純簽名 cookie）。

## F3. 邀請與角色權限

**生產級做法**：
1. 邀請：owner 建 staff（email + role）→ 寄簽名邀請 token（72 小時、單次）→ 受邀者設密碼啟用；重寄 = 舊 token 作廢。
2. 權限模型：`roles`（shop 內自訂）+ `role_permissions`（permission key 字串）+ `staff_members.role_id`；permission key 命名照 05 研究：`orders.view / orders.refund / products.edit / products.cost.view / settings.payments / …`（demo 先 20 個 key）。
3. 強制點：Pundit policy 全 controller `verify_authorized`（漏掛直接測試紅）；React 端只做「藏按鈕」的 UX，**授權真相只在 server**。
4. owner 特權：不可刪除、不可降權、permission check 永遠 true；轉移店主是獨立雙確認流程（P1）。
5. 稽核：`audit_logs`（actor、action、target_type/id、before/after JSON、ip）——append-only，設定變更/退款/刪除/權限變更必記（對齊 05 的 Store activity log）。

**代碼**：

```ruby
class ApplicationPolicy
  def initialize(staff, record) = (@staff, @record = staff, record)
  def can?(key) = @staff.owner? || @staff.role.permission_keys.include?(key)
end
class OrderPolicy < ApplicationPolicy
  def refund? = can?("orders.refund")
end
# controller: authorize order, :refund?  ← Pundit
```

**⚠️ 坑**：
- 權限只擋 UI 不擋 API → 一定要 `verify_authorized` + request spec 逐 endpoint 測 403。
- audit log 記 `after` 時把密碼/token 欄位過濾掉（沿用 filter_parameters 清單）。
- 邀請 token 放 URL 會進各種日誌 → token 只可單次使用即作廢，且日誌過濾 query string。
- 刪 staff 不能硬刪（audit/timeline 引用）→ `deactivated_at` 停用。

## F4. 租戶隔離的持續保證（工程機制）

**生產級做法**：
1. `acts_as_tenant(:shop)` 掛滿業務 model；`ActsAsTenant.configure.require_tenant = true`（無租戶查詢直接炸，開發期就暴露）。
2. Job 規約：所有 job 第一參數 `shop_id`，`around_perform` 統一 `ActsAsTenant.with_tenant(Shop.find(shop_id))`。
3. 測試護欄：一支共用 spec——建兩個店的資料，對每個 admin API endpoint 用 A 店身分打 B 店資源 ID，斷言 404（不是 403，避免洩漏存在性）。
4. DB 層兜底（P1）：關鍵表加 `(shop_id, id)` 複合唯一，查詢一律帶 shop_id 才能命中。

**⚠️ 坑**：
- `find_by(id:)`、`find_signed`、GlobalID 反序列化這些「繞過 default scope」的入口是隔離破口清單，code review 重點盯。
- console/rake 操作忘 set tenant → 提供 `bin/tenant SHOP_SUBDOMAIN` 包裝腳本，養成肌肉記憶。
- 跨租戶的平台級查詢（計費、監控）明確用 `ActsAsTenant.without_tenant` 並集中在 `Platform::` namespace，好審計。

## 本篇驗收（對照 11 §0）

雙店隔離 spec 全綠；brakeman 無高危；登入限流生效（實測 429）；session 撤銷即時；audit log 可還原「誰在何時改了什麼」；邀請 token 過期/重放皆拒。
