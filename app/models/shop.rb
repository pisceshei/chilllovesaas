# 只由 request Host 選定的 tenant root model。
#
# Shop 本身不受 acts_as_tenant scope；所有租戶資料都透過其 shop_id 隔離。
# 見 docs/specs/12 F1/F4。
class Shop < ApplicationRecord
  SUBDOMAIN_FORMAT = /\A[a-z0-9][a-z0-9-]{1,61}[a-z0-9]\z/
  STATUSES = %w[active suspended closed].freeze

  # 建店時就要有的預設銷售管道（88 §4：「建立商店的流程**必須**連帶建立它」）。
  DEFAULT_CHANNEL_HANDLE = "online_store"
  DEFAULT_CHANNEL_NAME = "線上商店"

  # 🔴 **本區塊的三條關聯在 2026-08-15 之前是壞的**（`Shop#destroy` 完全不能用）。
  # `20260814000000`（身分表升組織層，裁定 D8／§A G24）從 `staff_members`／`sessions`／
  # `roles` 三張表拆掉了 `shop_id`，卻**沒有同步改這裡的宣告** ⇒ 三者都會生出
  # `WHERE staff_members.shop_id = ?` 這種 SQL，實跑一律 `Unknown column`。
  # 🔴 **沒有任何測試發現**，因為在此之前沒有任何一條測試呼叫過 `shop.destroy`
  # 或這三個關聯（全庫 grep `shop.staff_members`／`shop.sessions`／`shop.roles` 零命中）。
  # 教訓：**拆欄位的 migration 要連 model 宣告一起改**——欄位沒了，宣告不會自己失效，
  # 它會安靜地留著，直到第一個人去用它。
  #
  # 現在的正確模型：`staff` 屬於**組織**，「屬於哪些店」是一筆 `UserStoreAssignment`。
  has_many :user_store_assignments, dependent: :restrict_with_error
  # 保留原本 `restrict_with_error` 的意圖（還有人在的店不得刪除），只是改由指派關係表承載。
  has_many :staff_members, through: :user_store_assignments
  has_many :products, dependent: :restrict_with_error
  # ⚠️ `has_many :sessions` 與 `has_many :roles` **已移除**，不是漏寫：
  # session 屬於 staff_member（組織層登入），role 明文「本身不綁店」
  # （見 `app/models/role.rb` 檔頭）——兩者都不再是 Shop 的下屬集合。
  # 要「這間店的 session」請走 `user_store_assignments → staff_member → sessions`。

  # 🔴 `:destroy` 而**不是** `:restrict_with_error`。
  # 本檔**另外兩個**直接關聯（`user_store_assignments`／`products`）都用
  # `restrict_with_error`，照抄看起來合慣例——但下面的 `after_create` 之後
  # **每一間店恆有一列 publication**，於是連一間空店都永遠刪不掉，
  # 而且沒有任何既有測試會因此變紅。publication 是店的**附屬設定**不是業務資料，
  # 店沒了它就沒有意義；擋刪店的責任屬於那兩個。
  # ⚠️ 原文寫「另外**三**個」並把 `staff_members` 算進去——它是
  # `has_many :through`，**沒有也不能有 `dependent:`**（擋刪店的是它底下的
  # `user_store_assignments`）。數錯不影響本條的裁定，但會讓人去找一個不存在的第三個。
  #
  # 🔴 **這四個關聯的宣告順序是外鍵決定的，不可任意調換。**
  #   `dependent:` 是按**宣告順序**註冊成 `before_destroy` 的，而外鍵要求
  #   「指向別人的那一方先刪」⇒ 宣告順序＝建立順序的**反序**：
  #
  #     建立（`create_default_publication`）：
  #       app_installation → sales_catalog → publication → channel
  #     刪除（本處宣告順序）：
  #       channel → publication → sales_catalog → app_installation
  #
  #   調換的後果不是「刪不掉」這麼明顯，而是**錯誤訊息指不出根因**——
  #   會變成「無法刪除 catalog」或「無法刪除 app_installation」，
  #   而真正的原因是還有 publication／channel 指著它。
  #   （同 `Product` 那組 `product_variants` 必須排在 `product_options` 之前的理由。）
  has_many :channels, dependent: :destroy
  has_many :publications, dependent: :destroy
  has_many :sales_catalogs, dependent: :destroy
  has_many :app_installations, dependent: :destroy
  # 🔴 三張 i18n 表用 `delete_all` 不用 `destroy`：ShopLocale#before_destroy 擋「刪來源語言」
  #    （SOURCE_LOCALE_IMMUTABLE）——那是保護**活著的店**；整店刪除時語言列必須跟著走，
  #    走 destroy 會被自己的守門擋住變成「空店刪不掉」（shop_spec 三條即此）。
  #    順序：translations／translation_status 有 FK → shops，必須在 shop 刪除前清掉。
  # 庫存鏈（排程第 16 包）。地點 delete_all：每家新店都有預設地點，restrict 會讓
  # 空店永遠刪不掉；有商品的店本來就被 products 的 restrict 擋住，不會走到這裡。
  has_many :locations, dependent: :delete_all
  has_many :inventory_items, dependent: :delete_all
  has_many :inventory_adjustment_groups, dependent: :delete_all
  # 🔴 markets／domains 必須排在 shop_locales **之前**（dependent 依宣告順序執行）：
  #    market_web_presence(_locale)s 有複合 FK restrict 指向 shop_locales——先清語言列會被
  #    FK 擋下「空店刪不掉」。刪 markets 由 DB cascade 帶走 regions／presences／白名單列，
  #    domains 隨後才無 presence 引用（fk_mwp_domain restrict）。
  # ⚠️ 用 `delete_all` 而非 `destroy`：Market#before_destroy 擋 primary market——
  #    那是保護**活著的店**；整店刪除時市場必須跟著走，走 destroy 會被自己的守門擋成
  #    「空店刪不掉」，與 shop_locales 繞 SOURCE_LOCALE_IMMUTABLE 是同一條理由（見上方 i18n 註釋）。
  has_many :markets, dependent: :delete_all
  has_many :domains, dependent: :delete_all
  has_many :shop_locales, dependent: :delete_all
  has_many :translations, dependent: :delete_all
  has_many :translation_statuses, class_name: "TranslationStatus", dependent: :delete_all

  normalizes :subdomain, with: ->(value) { value.to_s.strip.downcase }
  normalizes :custom_domain, with: ->(value) { value.to_s.strip.downcase.delete_suffix(".").presence }

  validates :name, :subdomain, :status, presence: true
  validates :subdomain, format: { with: SUBDOMAIN_FORMAT }, uniqueness: { case_sensitive: false }
  validates :subdomain, exclusion: {
    in: Chilllove::TenantResolver::RESERVED_SUBDOMAINS,
    message: "為平台保留字"
  }
  validates :custom_domain, uniqueness: { case_sensitive: false }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  after_create :create_default_publication
  after_create :create_default_location
  after_create :enable_launch_locales
  # 🔴 必須排在 enable_launch_locales 之後（after_create 依註冊順序執行）：
  #    presence.default_shop_locale 與白名單列都有複合 FK 指向 shop_locales——語言列先存在。
  after_create :provision_default_market
  # 🔴 `prepend: true` 不可省。`has_many ... dependent: :destroy` 是在**關聯宣告當下**
  # 註冊成 `before_destroy` 的，而本檔的關聯宣告在這行之上 ⇒ 不 prepend 的話，
  # dependent 的刪除會**先跑**、落在租戶包裹之外，`NoTenantSet` 照樣拋。
  # （實測過：不加 prepend 時「空店可以刪除」那條 spec 仍然紅。）
  around_destroy :within_own_tenant, prepend: true

  # 刪除本店時把租戶設成自己。
  #
  # 🔴 為什麼非有不可：`dependent: :destroy` 會走 `publications` 這個
  # **受 `acts_as_tenant` 隔離**的關聯。而 `require_tenant = true` 之下：
  #   - **沒有** current_tenant ⇒ `NoTenantSet`，`shop.destroy` 直接炸；
  #   - current_tenant 是**別間店** ⇒ default scope 把它過濾成 0 列，
  #     於是 publication 一列都沒刪掉，**而 `destroy` 回報成功**。
  #     這是「回報成功但什麼都沒做」的形態，比直接炸危險得多。
  # ⇒ 不把「先設對租戶」當成呼叫端的紀律，直接做進 model。
  #
  # @return [void]
  # @note 副作用：在 yield 期間切換 `ActsAsTenant.current_tenant`，結束後還原。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F4
  def within_own_tenant(&block)
    ActsAsTenant.with_tenant(self, &block)
  end

  # 建立本店的預設線上商店管道。
  #
  # 為什麼是 `after_create` 而不是別的掛載點：88 §5 #1 只說「建店流程本身是 M1/M8 的事」，
  # 沒有指定掛載點；而本倉庫目前**沒有 service 層、也沒有 shops controller**
  # ⇒ 實務上只剩 model callback 一個位置。放這裡的好處是**每一條建店路徑都涵蓋**
  # （seeds、factory、rake、未來的 M8 平台後台），不會有人新開一條路徑而忘了建管道。
  #
  # 🔴 缺了它會怎樣：`Publication.online_store` 回 `nil`，於是
  #   ① 商品的上架區塊沒有任何管道可勾（88 §1 的三層 AND 第二層永遠不成立）；
  #   ② `resource_publications` 建不起來（`publication_id` 是 `null: false`）；
  #   ③ **而這一切不會拋任何錯**——新店看起來一切正常，只是所有商品都上不了架。
  # 這正是 88 §5 #1 的實質內容：migration 只回填了**當時既有**的店，
  # 之後每一間新店都靜默拿到 nil。
  # ℹ️ 88 §5 #1 **已由本次改動結案**（該列在規格裡已劃掉並標 ✅）——
  # 原文稱它為「那條**待辦**」是寫作當下的狀態，現在讀起來會誤導。
  #
  # 🔴 為什麼包 `ActsAsTenant.with_tenant(self)`：
  # `config/initializers/acts_as_tenant.rb` 設 `require_tenant = true`，
  # `Publication` 宣告了 `acts_as_tenant :shop` ⇒ 在沒有 current_tenant 時
  # 它的 default scope 會 raise `NoTenantSet`。
  # 而改用 `without_tenant` 也不行——那樣 gem 的 `before_validation` 不會填 `shop_id`，
  # 會撞 `null: false`。⇒ 只有 `with_tenant(self)` 兩件事都對。
  # （`with_tenant` 只換 `current_tenant`、不動 `unscoped` 旗標，所以在 seeds 的
  #  `without_tenant` 區塊內巢狀使用是安全的。）
  #
  # 🔴 **transaction 內沒有外部 IO**（鐵律 5）：只有一次本地 INSERT。
  # 之後若要在建店時通知外部（例如註冊 webhook），必須丟 job，不得直接呼叫。
  #
  # ⚠️ **只建 `online_store` 一個管道**。`docs/research/82` §0.1 實測本尊的
  # 「已安裝管道」有三個（銷售點／線上商店／Shop），但 88 全篇只規範 online_store，
  # 其他管道由誰在什麼時候建**沒有規格** ⇒ 不猜，登記於 worklog。
  #
  # @return [Publication] 本店的線上商店管道
  # @note 副作用：INSERT 一列 `publications`。
  # @see docs/specs/88-publication-model.md §4、§5 #1
  # 建店即建預設地點（名稱同本尊「Shop location」；資料預設英文＝2026-08-23 使用者指示）。
  # 🔴 沒有這一步，第一個變體的 level 鏈就斷了——90 藍圖 §9.1.4：「任何『先做商品、
  # 之後再補庫存』的排法都會產生一次資料回填，而 ledger 是 append-only、期初列無法追認」。
  def create_default_location
    ActsAsTenant.with_tenant(self) do
      locations.create!(name: Limits.fetch(:inventory, :default_location_name))
    end
  end

  # 🔴 **2026-08-26 S0**：從建 1 列變成建 **4 列**
  #   （app_installation → catalog → publication → channel）。
  #   順序**不可倒**，每一步都是外鍵決定的：
  #     ①`channels.app_installation_id` 指向 `app_installations`；
  #     ②`publications.sales_catalog_id` 指向 `sales_catalogs`；
  #     ③`channels.publication_id` 指向 `publications`。
  #   （第一批 `20260826062000` 時是 2 列，第二批 `20260826070000` 補上頭尾兩列。）
  #
  #   為什麼要 catalog：本尊**每個 publication 都有一個 catalog**
  #   （`docs/research/82` §9.5b／§10.3 兩次抓包：Online Store 與 Shop 的 catalog 都是
  #   `AppCatalog`，標題 `Channel Catalog {publicationId} for {ChannelName}`）。
  #   我方的 catalog 外鍵欄自 `20260814200000` 起存在但**恆為 NULL、無寫入者兩週**
  #   ⇒ 三層 AND 的第三層永遠是 no-op。使用者 2026-08-26 裁定方案 D（本尊全形）後補上。
  #
  #   ⚠️ 四列在**同一個 transaction** 內：`after_create` 本身跑在 `Shop.create!` 的
  #   transaction 裡，所以這裡不另開。任何一步失敗 ⇒ 整間店回滾，不會留下
  #   「有 publication 但沒有 catalog」或「有 publication 但沒有 channel」的半成品。
  #   🔴 後者特別重要：`Publication.online_store` 自 S0 第二批起**經 `channels.handle` 解析**
  #   ⇒ 少了 channel 的 publication 在該方法眼中不存在。
  #
  # @return [Publication] 本店的線上商店管道
  # @note 副作用：INSERT 各一列 `app_installations`／`sales_catalogs`／`publications`／`channels`。
  # @see docs/plans/2026-08-26-S0-方案D-schema設計.md §2
  def create_default_publication
    ActsAsTenant.with_tenant(self) do
      installation = app_installations.create!(
        app_handle: DEFAULT_CHANNEL_HANDLE,
        installed_at: Time.current
      )

      catalog = sales_catalogs.create!(
        catalog_type: "app",
        title: SalesCatalog.channel_catalog_title(DEFAULT_CHANNEL_NAME),
        status: "active"
      )

      publication = publications.create!(
        sales_catalog: catalog,
        name: DEFAULT_CHANNEL_NAME,
        channel_handle: DEFAULT_CHANNEL_HANDLE,
        auto_publish: true,
        supports_future_publishing: true
      )

      channels.create!(
        publication:,
        app_installation: installation,
        handle: DEFAULT_CHANNEL_HANDLE,
        channel_type: "app"
      )

      publication
    end
  end

  # 新店啟用首發語言（limits `i18n.launch_locales`；種子不是列舉，商家之後可自行增刪）。
  # 來源語言＝`i18n.source_locale_default`（en，裁定 C1/R1）且 published；其餘啟用但未發布。
  # 與 migration 20260823100000 對既有商店的規則**同一份**（docs/plans/2026-08-23-多語言方案.md §3.2）。
  def enable_launch_locales
    source = Limits.fetch(:i18n, :source_locale_default).to_s
    ActsAsTenant.with_tenant(self) do
      Limits.fetch(:i18n, :launch_locales).map(&:to_s).each_with_index do |tag, position|
        next unless PlatformLocale.exists?(tag:)

        shop_locales.create!(
          locale_tag: tag,
          is_source: tag == source,
          published: tag == source,
          enabled: true,
          position:
        )
      end
    end
  end

  # 建店預設市場鏈（包 32）：primary market HK ＋ primary domain ＋ presence ＋ 語言白名單。
  # 🔴 薄呼叫端——實作只有 `Markets::ProvisionDefaults` 一份（既有店回填 migration 同一支）。
  # 為什麼建店就要有：url_prefix 恆帶 region（67 §F.1(b)），region 來自市場——
  # 沒有市場的店一條前台 URL 都組不出來（B11：v1 單一 HK 市場先接通整條鏈）。
  def provision_default_market
    Markets::ProvisionDefaults.call(shop: self)
  end

  # 判斷 M0 是否可路由已持久化的 custom domain。
  #
  # M0 只在驗證完成後寫入此欄位；P1 的 custom_domains 表會保存明確的
  # verification timestamp。
  #
  # @return [Boolean] 只有 active 且有 custom domain 的商店回傳 true
  # @note 副作用：無。
  # @see docs/specs/12-spec-tenancy-auth-permissions.md F1
  def custom_domain_verified?
    status == "active" && custom_domain.present?
  end
end
