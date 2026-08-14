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
  # 本檔另外三個關聯都用 `restrict_with_error`，照抄看起來合慣例——但下面的
  # `after_create` 之後**每一間店恆有一列 publication**，於是連一間空店都永遠刪不掉，
  # 而且沒有任何既有測試會因此變紅。publication 是店的**附屬設定**不是業務資料，
  # 店沒了它就沒有意義；擋刪店的責任屬於 products／staff_members 那三個。
  has_many :publications, dependent: :destroy

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
  # 這正是 88 §5 #1 那條待辦的實質內容：migration 只回填了**當時既有**的店，
  # 之後每一間新店都靜默拿到 nil。
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
  def create_default_publication
    ActsAsTenant.with_tenant(self) do
      publications.create!(
        name: DEFAULT_CHANNEL_NAME,
        channel_handle: DEFAULT_CHANNEL_HANDLE,
        auto_publish: true,
        supports_future_publishing: true
      )
    end
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
