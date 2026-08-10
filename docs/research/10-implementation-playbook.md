# 10 — 實作手冊：00–09 逐篇細節化（怎麼做、用什麼工具、寫什麼代碼、查什麼文檔）

> 前提：D1–D3 決策已定（Rails + React 本尊同款棧、路線 A→B→C、品牌 CHILL LOVE）。本篇把 00–09 每一篇研究翻譯成「動手做」的層次：**做法 → 工具/套件 → 關鍵代碼草稿 → 參考文檔**。代碼皆為示意草稿，實作時以此為骨架展開。

## 通用底座（所有篇章共用）

| 層 | 選擇 | 版本基準（2026-08） | 備註 |
|---|---|---|---|
| 語言 | Ruby + TypeScript | Ruby 3.4.x / TS 5.x | |
| 框架 | **Rails 8.1**（8.1.3 現行穩定版） | rails gem 8.1.x | Solid Queue/Cache/Cable 內建，**不需要 Redis** |
| DB | MySQL | 8.4 LTS | 與本尊一致；`mysql2` gem |
| 後台前端 | React 19 + Vite | `vite_rails` gem | SPA 掛在 Rails layout 下 |
| 前台 | Rails SSR + **Hotwire**（Turbo + Stimulus）+ ViewComponent | rails 內建 | Turbo ≈ Section Rendering API 的天然等價物 |
| 佇列/快取 | Solid Queue / Solid Cache（DB-backed） | rails 內建 | 對齊 08 的「用 DB 佇列」結論 |
| 金流 | Stripe test mode | `stripe` gem + Stripe.js Elements | |
| 模板語言 | **Liquid gem（Shopify 官方開源、MIT）** | `liquid` | 通知信模板直接用真 Liquid，完全合法 |
| 部署（P1 之後） | Docker + Kamal 2 | rails 內建 | demo 期在雲端工作區跑 |

**關鍵 Gemfile 追加**：`mysql2`、`vite_rails`、`acts_as_tenant`（多租戶）、`pundit`（權限）、`liquid`、`stripe`、`image_processing`（Active Storage 縮圖）、`blueprinter`（JSON 序列化）、`pagy`（分頁）、`rack-attack`（限流）、`flipper`（feature flags）、`annotaterb`；開發測試：`rspec-rails`、`factory_bot_rails`、`faker`、`capybara`、`letter_opener`、`rubocop-rails-omakase`。

**Admin 端 npm**：`react` `react-dom` `react-router` `@tanstack/react-query` `@tanstack/react-table` `react-hook-form` `zod` `@radix-ui/react-*`（Popover/Dialog/DropdownMenu/Tabs/Toast 等 headless 原語，MIT）`lucide-react`（icon，MIT）`@dnd-kit/core`（拖曳）`@tiptap/react`（富文本）`recharts`（報表圖）。

---

## 00 總覽 → 專案骨架與三個面

**做法**：單一 Rails app 承載三個面——`/admin`（React SPA）、`{store}.chilllove.test`（買家前台，子網域定租戶）、`/checkout`。用 `Current.shop`（CurrentAttributes）+ `acts_as_tenant` 讓「所有查詢自動帶 shop_id」。開發環境用 `lvh.me`（免設定的萬用回環網域）測子網域。

**工具**：`rails new chilllove -d mysql`、`vite_rails`、`acts_as_tenant`、lvh.me。

**代碼草稿**：

```ruby
# config/routes.rb
constraints subdomain: /.+/ do            # {store}.lvh.me → 前台
  root "storefront#index", as: :storefront_root
  get "/products/:handle",    to: "storefront/products#show"
  get "/collections/:handle", to: "storefront/collections#show"
  scope :checkout do post "/", to: "checkouts#create" end
end
namespace :admin do                        # 平台後台（React SPA）
  get "/(*path)", to: "spa#show"           # 交給 react-router
  namespace :api do resources :products, :orders, :customers end
end
```

```ruby
# app/controllers/concerns/set_current_shop.rb
class ApplicationController < ActionController::Base
  set_current_tenant_through_filter
  before_action { set_current_tenant(Shop.find_by!(subdomain: request.subdomain)) }
end
# 之後所有 acts_as_tenant(:shop) 的 model 查詢自動 scope 到該店
```

**文檔**：Rails Routing 指南、acts_as_tenant README、我們的 00（導航地圖=admin 路由表）。

---

## 01 後台核心 → Models + 服務層

**做法**：06 的 40 張表用 migration 落地（見 06 節），業務動作全部收進 **service objects**（`app/services/`），controller 只做參數與授權。狀態機用字串 enum + 服務內守衛（不引入重型 gem），financial/fulfillment 狀態由 transactions / fulfillments **推導**而非手動改。

**工具**：Active Record、`aasm`（可選，建議先不用）、FactoryBot（測試資料）。

**代碼草稿**：

```ruby
# 變體生成：options 笛卡兒積（≤3 options，上限保護）
class Catalog::VariantGenerator
  def call(product, options)  # options: [{name:"Size", values:["S","M"]}, ...]
    raise TooManyOptions if options.size > 3
    combos = options.map { _1[:values] }.inject(&:product) || []
    combos.map { |vals| product.variants.build(option_values: vals, price_cents: product.default_price_cents) }
  end
end
```

```ruby
# 庫存調整：永遠走 ledger（06 §5 恆等式）
class Inventory::Adjust
  def call(level:, delta:, reason:, ref: nil)
    ActiveRecord::Base.transaction do
      level.lock!
      level.update!(available: level.available + delta)
      level.adjustments.create!(delta:, reason:, reference: ref, staff: Current.staff)
    end
  end
end
```

```ruby
# 訂單金流狀態推導（掛在 Order 上）
def derive_financial_status
  cap = transactions.successful.where(kind: %w[sale capture]).sum(:amount_cents)
  ref = transactions.successful.where(kind: "refund").sum(:amount_cents)
  return "refunded"           if ref >= cap && cap.positive?
  return "partially_refunded" if ref.positive?
  return "paid"               if cap >= total_cents
  cap.positive? ? "partially_paid" : "pending"
end
```

**文檔**：我們的 01（畫面與狀態機規格）、06（表結構）、Rails Active Record 指南。

---

## 02 Polaris 風格 UI → 自建元件庫（`admin/ui/`）

**做法**：三層——(1) `tokens.css`（把 02 研究的色彩/字級/間距/圓角值寫成 CSS variables）；(2) 基礎元件（Radix headless 原語 + 自己的樣式 = 合法的 Polaris 手感）；(3) 兩個頁面模板 `IndexPage` / `DetailPage` 承載所有模組。**不安裝任何 @shopify/* 前端套件**（授權紅線）。

**工具**：Radix UI（MIT）、TanStack Table（IndexTable 的表格引擎）、react-hook-form（dirty 偵測 → SaveBar）、lucide-react、@dnd-kit。

**代碼草稿**：

```css
/* admin/src/ui/tokens.css —— 值來自 02 §2 */
:root{
  --bg:#f1f1f1; --surface:#fff; --surface-2:#f7f7f7;
  --text:#303030; --text-2:#616161; --border:#e3e3e3; --icon:#4a4a4a;
  --fill-brand:#303030; --success:rgb(4,123,93); --critical:rgb(199,10,36);
  --warning:#ffb800; --sp-1:4px; --sp-2:8px; --sp-4:16px;
  --r-card:12px; --r-btn:8px; --font:Inter,-apple-system,sans-serif;
}
```

```tsx
// SaveBar：dirty 就浮出（02 §5 的靈魂交互）
export function SaveBar({form, onSave}:{form:UseFormReturn<any>, onSave:()=>void}) {
  const dirty = form.formState.isDirty;
  useBlocker(dirty);                          // react-router 離開攔截
  useBeforeUnload(dirty);                     // 關閉分頁攔截
  if (!dirty) return null;
  return <div className="savebar">
    <span>未儲存的變更</span>
    <Button variant="tertiary" onClick={()=>form.reset()}>捨棄</Button>
    <Button variant="primary" loading={form.formState.isSubmitting} onClick={onSave}>儲存</Button>
  </div>;
}
```

元件開發順序（對應 02 §10）：tokens → Button/Card/Page/TextField/Select/Badge → IndexTable(+IndexFilters) → SaveBar/Toast/Modal → EmptyState/Skeleton → Popover/ActionList → DropZone/Combobox/DatePicker。

**文檔**：Radix UI docs、TanStack Table docs、react-hook-form docs；規格書=我們的 02。

---

## 03 前台與主題 → ViewComponent sections + Turbo

**做法**：theme = DB 資料（`themes` / `templates`(JSON) / `theme_settings`），每種 section 是一個 **ViewComponent** 類別 + 一份 settings schema（Ruby DSL，等價 `{% schema %}`）。渲染管線：子網域定店 → 取 published theme → 取該頁 template JSON → 依 order 逐個 render section。cart drawer / variant 切換 / predictive search 全用 **Turbo Streams / Frames**（= Shopify Ajax + bundled section rendering 的 Rails 原生等價）。

**工具**：`view_component` gem、Turbo、Stimulus、`liquid` gem（P2 的自訂 section 語言，demo 先不用）。

**代碼草稿**：

```ruby
# app/components/sections/featured_collection_component.rb
class Sections::FeaturedCollectionComponent < Sections::Base
  schema do
    setting :collection, type: :collection_picker, label: "選擇集合"
    setting :columns,    type: :range, min: 2, max: 5, default: 4
    setting :heading,    type: :text, default: "精選商品"
  end
end
SECTION_REGISTRY = {
  "image-banner" => Sections::ImageBannerComponent,
  "featured-collection" => Sections::FeaturedCollectionComponent, ... }
```

```json
// templates.body 範例（index 頁）——與 OS 2.0 同構
{ "sections": {
    "hero":  { "type": "image-banner", "settings": { "heading": "CHILL LOVE" } },
    "feat":  { "type": "featured-collection", "settings": { "columns": 4 } } },
  "order": ["hero", "feat"] }
```

```erb
<%# 加入購物車 → turbo_stream 同時更新 drawer 與 badge（= bundled section rendering）%>
<%= turbo_stream.replace "cart-drawer", partial: "storefront/cart/drawer" %>
<%= turbo_stream.replace "cart-badge",  partial: "storefront/cart/badge" %>
```

Stimulus controllers：`variant-picker`（選項變更 → fetch 該 section 局部 HTML 換價格/庫存/按鈕）、`predictive-search`（debounce 300ms → `/search/suggest` 局部結果）、`cart-drawer`。

**文檔**：ViewComponent docs、Turbo Handbook、Stimulus Handbook；規格書=我們的 03（Dawn 頁面解剖 = 每頁要做什麼的 checklist）。

---

## 04 結帳金流 → 金額引擎 + Stripe + 通知 + 分析

**做法**：
1. **金額引擎**做成純 PORO（`Checkout::Calculator`），輸入 cart+地址+折扣碼，輸出完整 breakdown（小計/折扣分攤/運費/稅/總計）——checkout 預覽、下單、draft order、退款全部重用（06 §6）。
2. **Stripe**：後端建 PaymentIntent（金額來自 Calculator，不信任前端）；前端 Payment Element；`/webhooks/stripe` 收 `payment_intent.succeeded` → `Orders::CreateFromCheckout`（以 checkout_id 冪等）→ 同交易內條件式扣庫存。
3. **通知信**：`notification_templates`（subject + body 為 Liquid），OrderMailer 用 **Liquid gem** 渲染（變數經 Drop 白名單暴露）。
4. **棄單**：checkouts 表天然就是資料來源；Solid Queue 排程任務掃「有 email、未完成、>10 分鐘」。
5. **分析**：`Analytics::Query` 純 SQL 聚合 + recharts 卡片。

**代碼草稿**：

```ruby
class Checkout::Calculator
  Result = Data.define(:subtotal, :discounts, :shipping, :tax, :total, :allocations)
  def call(checkout)
    sub   = checkout.line_items.sum { _1.price_cents * _1.quantity }
    disc  = Discounts::Engine.new.apply(checkout)          # class+combinesWith 規則
    ship  = Shipping::RateResolver.pick(checkout)          # 05
    tax   = Tax::Calculator.for(checkout, sub - disc.total, ship) # 含稅/未稅
    Result.new(sub, disc, ship, tax, sub - disc.total + ship + tax, disc.allocations)
  end
end
```

```ruby
# 防超賣：條件式 UPDATE（08 §4 的單機正解）
sold = InventoryLevel.where(id: lvl.id).where("available >= ?", qty)
                     .update_all(["available = available - ?, committed = committed + ?", qty, qty])
raise OutOfStock if sold.zero?
```

```ruby
# Stripe webhook（冪等）
event = Stripe::Webhook.construct_event(payload, sig, ENV["STRIPE_WEBHOOK_SECRET"])
if event.type == "payment_intent.succeeded"
  Orders::CreateFromCheckout.call(checkout_id: event.data.object.metadata.checkout_id) # find_or_create
end
```

**工具**：`stripe` gem、Stripe.js、`liquid`、Solid Queue、recharts。
**文檔**：Stripe Payment Element / PaymentIntents / Webhooks 官方文件、Liquid gem README；規格書=我們的 04（欄位順序照 §1.2 做）。

---

## 05 平台設定 → 設定領域 + 權限 + 運費稅務引擎

**做法**：Settings 做成獨立 React 框架（左欄分類）。結構化領域用專屬表（shipping/taxes/notifications/users），簡單開關集中在 `shops.settings`（MySQL JSON 欄）。權限用 **Pundit** + `roles`/`role_permissions`（權限鍵直接沿用 01/05 研究的類別命名，如 `orders.refund`、`products.cost.view`）。

**代碼草稿**：

```ruby
class Shipping::RateResolver
  def rates(cart, address)
    zone = ShippingZone.for_country(address.country)     # profile→zone 匹配
    zone.rates.select { _1.matches?(cart) }              # flat / 重量或金額條件
        .map { |r| RateOption.new(r.name, r.price_cents(cart)) }
  end
end
```

```ruby
class OrderPolicy < ApplicationPolicy
  def refund? = staff.can?("orders.refund")   # role_permissions 查表
end
```

**工具**：Pundit、MySQL JSON 欄位。
**文檔**：Pundit README；規格書=我們的 05（§1 全清單就是 Settings 頁面路由表；demo 做 8 個域）。

---

## 06 資料模型 → Migrations 慣例 + 種子資料

**做法**：40 表按里程碑分批建（M0 建 shops/staff/products 群，M2 建 theme 群，M3 建 orders 群…）。慣例：**shop_id 放第一欄 + 每個查詢索引都是 `[shop_id, ...]` 複合**、金額一律 `*_cents` integer + `currency`、狀態用字串、外鍵約束全開。`annotaterb` 自動在 model 頂部註記 schema；ERD 用 mermaid 手維護在 06。

**代碼草稿**：

```ruby
create_table :orders do |t|
  t.references :shop, null: false, foreign_key: true
  t.references :customer, foreign_key: true
  t.string  :name, null: false                          # #1001（含前後綴）
  t.string  :status, default: "open", null: false       # open/archived/canceled
  t.string  :financial_status, default: "pending", null: false
  t.string  :fulfillment_status, default: "unfulfilled", null: false
  t.integer :subtotal_cents, :shipping_cents, :tax_cents, :total_cents, default: 0, null: false
  t.string  :currency, null: false
  t.json    :shipping_address, :billing_address
  t.text    :note
  t.datetime :closed_at, :cancelled_at
  t.timestamps
  t.index [:shop_id, :status, :created_at]
  t.index [:shop_id, :name], unique: true
end
```

**種子**：`db/seeds.rb` 生成 CHILL LOVE 示範店——服飾類 30 個商品（Faker 文案 + picsum 圖）、3 個 collections、50 個顧客、90 天內 200 筆訂單（讓分析頁一開就有漂亮曲線）。

**文檔**：Rails Migrations 指南、annotaterb README；規格=我們的 06。

---

## 07 方案 → 我的實際開發工作流（工具面）

**我在雲端工作區怎麼做**：
1. **環境**：工作區內裝 Ruby 3.4 + MySQL + Node（apt/rbenv），`bin/dev` 一鍵起 Rails + Vite + worker（Procfile）。
2. **驗收**：每個里程碑配 RSpec system test（Capybara + 無頭 Chromium，工作區已預裝）當「可跑證明」；同時用 Playwright 對關鍵畫面**截圖傳給你看**（後台列表、商品頁、結帳、付款成功）。
3. **交付**：程式碼在工作區用 git 管理；每個里程碑結束把整個專案同步回你的 `shopifysystem` 資料夾（或你開一個 GitHub repo，我直接 push——二選一）。
4. **品質**：rubocop-rails-omakase + RSpec 進 GitHub Actions（P1）；`bin/rails db:seed` 隨時重建示範資料。
5. **文件**：每個里程碑更新 `docs/DECISIONS.md` 與 milestone note，讓專案自我解釋。

**驗收清單（Definition of Done）範例——M3 成交線**：訪客在前台加購 → `/checkout` 填 4242 測試卡 → thank you 頁 → 後台 Orders 出現該單（paid/unfulfilled badge）→ 庫存 committed +1 → 收到訂單確認信（letter_opener 可見）→ system test 全綠。

---

## 08 架構守則 → 在 Rails 裡的具體落地

| 守則（08 §7） | 落地 |
|---|---|
| shop_id 貫穿一切 | `acts_as_tenant(:shop)` 全 model + 一支「掃描無租戶查詢」的測試（撈 SQL log 驗證）+ FK 約束 |
| read path 可快取 | 前台 fragment caching（Russian doll：section 快取 key = theme 版本 + 資料 updated_at）+ Solid Cache；圖片 CDN header |
| 寫路徑冪等 | `idempotency_keys` 表 + controller concern（checkout 提交、webhook 接收必掛）|
| 任務可中斷重跑 | Solid Queue + 任務全部設計成可重入（以 ID 撈狀態再續做，不在記憶體持狀態）|

**Outbox 事件（之後直通 webhooks）**：

```ruby
class Events
  def self.publish!(topic, payload)   # 與業務同一個 transaction 內呼叫
    Event.create!(shop: Current.shop, topic:, payload:, status: "pending")
  end
end
# Solid Queue 的 DispatchEventsJob 每 10s 掃 pending → 內部訂閱者（寄信、統計）
# P2 對外 webhook：同一張表加 webhook_subscriptions 的投遞 job
```

**Feature flags**：`flipper` gem，actor = shop（可對單店開新功能，等價 Shopify 的漸進發布）。

---

## 09 API → 對外開放的分層路線

**做法**（demo → P1 → P2 漸進）：
1. **demo**：`/admin/api/*` 內部 JSON（session 認證、Blueprinter 序列化、pagy cursor 分頁、統一錯誤格式 `{errors:[{code,message,field}]}`）。
2. **P1 公開唯讀**：`/api/v1/*` + `api_tokens`（token + scopes JSON，命名照抄 `read_products` 風格）+ `rack-attack` 令牌桶限流 + `X-Total-Cost` 風格回應頭（向 09 的 calculated cost 致敬、先做簡化版）。
3. **P2**：webhooks 對外（HMAC `X-ChillLove-Hmac-SHA256`、4 小時 8 次退避重試、24 小時失敗停用——規格照抄 09 §5）；GraphQL 用 `graphql-ruby`。

**代碼草稿**：

```ruby
# config/initializers/rack_attack.rb —— 每 token 每分鐘 120 requests
Rack::Attack.throttle("api/token", limit: 120, period: 60) do |req|
  req.env["chilllove.api_token_id"] if req.path.start_with?("/api/")
end
```

```ruby
class DeliverWebhookJob < ApplicationJob
  retry_on DeliveryFailed, attempts: 8, wait: ->(n) { (2**n).minutes } # ≈4 小時窗口
  def perform(subscription, event)
    body = event.payload.to_json
    hmac = Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", subscription.secret, body))
    res  = HTTP.timeout(5).headers("X-ChillLove-Hmac-SHA256" => hmac,
             "X-ChillLove-Topic" => event.topic, "X-ChillLove-Event-Id" => event.uuid)
             .post(subscription.url, body:)
    raise DeliveryFailed unless res.status.success?
  end
end
```

**文檔**：rack-attack README、graphql-ruby 官網（P2）；規格書=我們的 09。

---

## 工具總表（一頁看完）

| 用途 | 工具 | 授權 | 主文檔 |
|---|---|---|---|
| 框架 | Rails 8.1 | MIT | guides.rubyonrails.org |
| DB | MySQL 8.4 + mysql2 | GPL/MIT | dev.mysql.com |
| 多租戶 | acts_as_tenant | MIT | github.com/ErwinM/acts_as_tenant |
| 後台 SPA | React 19 + Vite + vite_rails | MIT | vite-ruby.netlify.app |
| UI 原語 | Radix UI | MIT | radix-ui.com |
| 表格/查詢 | TanStack Table / Query | MIT | tanstack.com |
| 表單 | react-hook-form + zod | MIT | react-hook-form.com |
| Icon | lucide-react | MIT (ISC) | lucide.dev |
| 拖曳 | dnd-kit | MIT | dndkit.com |
| 富文本 | TipTap | MIT | tiptap.dev |
| 前台互動 | Turbo / Stimulus / ViewComponent | MIT | turbo.hotwired.dev、viewcomponent.org |
| 模板語言 | liquid（Shopify 官方） | **MIT** | github.com/Shopify/liquid |
| 金流 | stripe gem + Stripe.js | MIT/專有服務 | docs.stripe.com |
| 佇列/快取 | Solid Queue / Solid Cache | MIT | rails 內建 |
| 權限 | Pundit | MIT | github.com/varvet/pundit |
| 限流 | rack-attack | MIT | github.com/rack/rack-attack |
| Flags | Flipper | MIT | flippercloud.io/docs |
| 序列化 | Blueprinter | MIT | github.com/procore-oss/blueprinter |
| 分頁 | pagy | MIT | ddnexus.github.io/pagy |
| 圖表 | recharts | MIT | recharts.org |
| 測試 | RSpec + Capybara + FactoryBot + Faker | MIT | rspec.info |
| 信件 | Action Mailer + letter_opener | MIT | rails 內建 |
| 部署（P1+） | Kamal 2 + Docker | MIT | kamal-deploy.org |
| ⚠️ 明確不用 | @shopify/polaris、Polaris icons、Dawn 代碼 | 受限授權 | 見 02 §1、07 §10 |

## M0 開工清單（下一步的具體動作）

1. 工作區裝 Ruby 3.4 + MySQL 8 + Node 22 → `rails new chilllove -d mysql` → 加 Gemfile → `bundle`。
2. `vite_rails` 安裝 → admin SPA 骨架（react-router 路由表 = 00 的導航地圖）。
3. Migration 批次一：shops / staff_members / roles / sessions / products 群 / inventory 群（約 14 表）。
4. `tokens.css` + 第一批 6 元件（Button/Card/Page/TextField/Badge/IndexTable 雛形）→ admin shell（側欄 + top bar，左上角 **CHILL LOVE**）。
5. Rails 8 內建認證產生器改多租戶版（staff 登入）。
6. `db/seeds.rb` 示範店 → 起 `bin/dev` → **截圖後台給你驗收**。

驗收標準：登入 CHILL LOVE 後台，看到側欄導航 + 商品列表（空狀態插畫）+ 可新增第一個商品。
