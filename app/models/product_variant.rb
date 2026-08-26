# 商品的子類選項（variant）。
#
# ⚠️ **M1 尚未展開**：本類別目前只有租戶隔離、關聯與最基本的驗證。
# 變體 diff 更新、價格/成本、庫存連動、選項組合等屬 M1 商品線的主體工作
# （HANDOFF §5：「Products CRUD＋變體 diff 更新＋媒體＋系列＋庫存 ledger」）。
#
# 為什麼現在就建：`ResourcePublication` 的 `publishable` 是**多型**關聯，
# 而本尊的 Publishable 介面由 Product／Collection／ProductVariant 三者實作
# （docs/research/82 §0.2）——三個類別缺一個，多型關聯就無法驗證。
#
# @see docs/specs/88-publication-model.md
class ProductVariant < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :product

  has_many :resource_publications, as: :publishable, dependent: :destroy

  # D12：變體的選項座標。`dependent: :destroy`——座標是變體的組成部分，變體沒了就沒有意義。
  # 🔴 `autosave: true` 不是可有可無（2026-08-16，PR #38 靜默資料遺失第二層，實測復現）：
  #    預設的 has_many autosave **只存新列、只刪標記列，不存被修改的持久列**。
  #    於是 `row.option_value_id = 新值; variant.save!` ⇒ save! 回 true、
  #    **digest 用了記憶體新值、DB 還是舊值**——digest 與 join 列不一致，
  #    正是唯一索引防不了、查不出來的那種錯。autosave: true 讓 dirty 子列隨父存檔落地，
  #    digest 算的「存檔後的樣子」才真的是存檔後的樣子。
  has_many :product_variant_option_values, dependent: :destroy, autosave: true
  has_many :option_values, through: :product_variant_option_values

  # 變體圖（第 27 包建立、第 29 包讀取面用）。
  # 🔴 **無 dependent**：變體被刪時 `Catalog::DeleteVariant` 只把
  #    `media.product_variant_id` 置 NULL（B1 方案②第 ② 步）——圖仍屬於商品，
  #    只是不再是「這個變體的圖」。加 dependent: :destroy 會把商品的圖一起刪掉。
  has_many :media, class_name: "Media", inverse_of: :product_variant

  # 🔴 無 dependent（2026-08-24 第 20 包／B1）：item 在變體刪除後**保留為孤兒**
  #    （product_variant_id 置 NULL＋variant_deleted_at）——ledger 是 append-only
  #    稽核帳，連鎖刪 item→levels 會撞 ledger 的 RESTRICT FK；且 dependent: :destroy
  #    走**記憶體快取的關聯物件**，呼叫端載過關聯時連「先置 NULL」都繞不過。
  #    刪除唯一路徑＝Catalog::DeleteVariant。
  has_one :inventory_item

  # B1 全域不變量：任何 destroy 路徑（含 product.destroy 連鎖）都先孤兒化 item，
  # ledger／levels 隨孤兒保留。update_all 不觸發回呼、冪等（已 NULL 查無列）。
  before_destroy :orphan_inventory_item!

  validates :title, presence: true
  # 重量是非負整數公克。DB 是 signed int ⇒ 負數在資料庫層完全合法，擋不住；
  # `SaveProduct#normalize_weight` 已在服務層回 userError，這是第二道
  # ——涵蓋 insert_all 以外的所有寫入路徑（審查 R-4／P29-BE-W2）。
  # 上限不設：官方值未取得（鐵律 19），要設須先依鐵律 6 在 limits.yml 立鍵並帶出處。
  validates :weight_grams,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  after_create :create_inventory_item
  # 變體出生即物化發布列（本尊實測 82 §8.2：未被觸碰過的變體回傳的是**全部管道**，
  # 不是 0 列——若是「無列＝繼承父商品」的模型應該回 0 列）。
  # 掛 callback 的理由與上一行的 `create_inventory_item` 完全相同（見該方法註釋）。
  after_create :materialize_publications

  private

  # 🔴 **這裡刻意不讀父商品的 publication 集合。這是我方裁定（ours），不是照抄本尊。**
  #
  # 「變體應該跟著父商品」是壓倒性的直覺，任何 reviewer 看到這裡都會想提
  # 「沒有跟父層對齊」。先讀完下面四段再決定要不要動它。
  #
  # **本尊官方文檔說的是「跟父商品」**（`shopify.dev/docs/apps/build/sales-channels/
  # product-publishing`，取證 2026-08-26）逐字：
  #   "the variant is created with the default state of published to all channels
  #    and catalogs where the parent product is published."
  #
  # **但那句描述的是「生效狀態」，不是「儲存狀態」。** 同日在測試店拿到的 UI 直接證據：
  # 對變體開 Manage publishing 時，父商品沒發布的那個管道**呈灰、帶 ⓘ、而 toggle 仍是開的**，
  # 提示逐字 "Product must be published to the channel before variants can appear"
  # ⇒ 變體在該管道上**確實有列**，只是被商品層閘掉（82 §8.4②(c)）。
  #
  # **⚠️ 儲存狀態這一側的實測有一個排除不掉的替代假說**（82 §8.4②(b)，已登記未取得）：
  # 新變體可能是由前身 `Default Title` 變體衍生的，那顆本來就有全部管道的列。
  #
  # **⇒ 選「全部 auto_publish 管道」的理由是後果而非權威**：
  #   ①與實測的儲存狀態一致；②與本尊自陳的 opt-out 模型一致（"Variants default to
  #     published"、"configure variant visibility **before** publishing the product"）；
  #   ③商家後果較好——商品日後發布到新管道時變體立刻跟著可見，不必逐一補發布。
  #   而且**兩種選法對「可見性」的結果完全相同**，因為閘控在讀取層的 AND
  #   （`Product.published_on` 的兩個 EXISTS），不在寫入層。
  #
  # @see Publications::Materialize
  # @see docs/research/82-admin-channels.md §8.4②
  def materialize_publications
    Publications::Materialize.for(self)
  end

  def orphan_inventory_item!
    InventoryItem.where(shop_id: shop_id, product_variant_id: id)
                 .update_all(product_variant_id: nil, variant_deleted_at: Time.current)
    association(:inventory_item).reset
  end

  # 變體出生即建 inventory_item（63 §B.5：加選項後原 variant.id 與 inventory_item.id
  # 必須完全相同 ⇒ item 的身分必須與變體同時誕生，不能等「之後補庫存」）。
  # 每個既有地點補一列 0 量 level；反方向（新地點補 level）在 Location#after_create。
  # 🔴 做成 callback 而不是 SaveProduct 的服務層步驟：任何建立路徑（含未來的匯入、
  # bulk、測試 factory）都必須成立，服務層紀律涵蓋不了它們。
  def create_inventory_item
    item = InventoryItem.create!(shop_id: shop_id, product_variant_id: id, sku: sku, tracked: true)
    Location.where(shop_id: shop_id).find_each do |location|
      InventoryLevel.find_or_create_by!(shop_id: shop_id, inventory_item_id: item.id, location_id: location.id)
    end
  end

  # 🔴 digest 一律由 join 列算出來，**不接受呼叫端指定**。
  # 允許外部塞值 ＝ 允許 join 列與 digest 不一致，而唯一索引只認 digest。
  before_validation :recompute_option_values_digest

  validates :option_values_digest, presence: true,
    format: { with: /\A[0-9a-f]{40}\z/,
              message: "必須是 40 字元小寫 hex（由 Catalog::OptionValuesDigest 產生）" }

  # 🔴 **座標必須「商品的每個選項恰好一個值」**（2026-08-16，PR #38 Codex review）。
  #
  # DB 層擋得住的只有「**至多**一個」（`uq_pvov_variant_option`）與「值屬於該選項」
  # （`fk_pvov_value`）——**擋不住「少給」**。於是在一個已經有選項的商品上：
  #   - 完全不給座標 ⇒ 被當成合法的 `NO_OPTIONS`（那是**無選項商品**才對的狀態）；
  #   - 只給三個選項中的兩個 ⇒ 也照樣存得進去。
  # ⇒ 前台的選項矩陣會出現點不到的組合，而 `selectedOptions` 序列化出去是殘缺的。
  #
  # ⚠️ **這條只能在 model 層擋**：MySQL 的 CHECK 不能跨表（子查詢 ⇒ ERROR 3815），
  #    而「恰好等於另一張表的某個集合」不是任何單一索引表達得了的約束。
  #    ⇒ 它是**唯一**的防線，`insert_all`／`upsert_all` 繞過它時沒有第二道。
  validate :option_coordinates_cover_every_product_option

  # @return [void]
  # @note 副作用：可能加入 `:product_variant_option_values` 的錯誤。
  def option_coordinates_cover_every_product_option
    return if product.nil?

    expected = product.product_options.pluck(:id).to_set
    # 🔴 與 digest 共用同一份「存檔後的樣子」——驗證與 digest 若各讀各的
    #    （一個讀快取、一個讀 DB），同一次存檔會出現「驗證過了但 digest 是另一組」。
    actual = effective_option_value_pairs.map(&:first).to_set
    return if expected == actual

    missing = expected - actual
    extra = actual - expected
    errors.add(:product_variant_option_values,
      "必須對商品的每個選項各給恰好一個值" \
      "#{missing.any? ? "（缺：#{missing.to_a.sort.join(', ')}）" : ''}" \
      "#{extra.any? ? "（多：#{extra.to_a.sort.join(', ')}）" : ''}")
  end

  # 依目前的 join 列重算 digest。
  #
  # 🔴 **無 join 列 ⇒ `NO_OPTIONS`**（空集合的 SHA1），那正是本尊「Default Title」
  # 那顆隱含變體的座標。它是合法狀態，不是「還沒填」。
  #
  # ⚠️ **重算必須與 join 列的 INSERT/UPDATE/DELETE 在同一個 transaction 內**。
  # 這個 callback 只覆蓋「透過本 model 存檔」的路徑；直接操作 join 表之後
  # **必須自己再存一次變體**（或呼叫本方法），否則 digest 會落後。
  # 🔴 `insert_all`／`upsert_all` 一律繞過本 callback——那條路徑目前沒有防護，
  #    而 DB 的 `option_values_digest` 是 `null: false` 且**刻意不給 default**，
  #    所以那種寫法會**大聲失敗**而不是靜默寫進假 digest。這是刻意的。
  #
  # @return [String] 重算後的 digest
  # @note 副作用：改寫 `option_values_digest` 屬性（不存檔）。
  # @see docs/DECISIONS.md D12
  def recompute_option_values_digest
    self.option_values_digest = Catalog::OptionValuesDigest.call(effective_option_value_pairs)
  end

  # 本次存檔完成後，join 列**將會是**的樣子：DB 事實 ＋ 記憶體中的待存增量。
  #
  # 🔴 **為什麼不能用 `association.reset`**（2026-08-16，PR #38 靜默資料遺失，實測復現）：
  #    reset 會把關聯 target 換成 DB 重載的新物件 ⇒ 呼叫端已 build 未存的列、
  #    對已載入列的屬性修改、`mark_for_destruction` 標記**全部從 autosave 目標消失**。
  #    最毒的一型：`row.option_value_id = 新值; variant.save!` ⇒ **save! 回 true、
  #    DB 還是舊值、digest 也是舊值、沒有任何錯誤**——修改被靜默丟棄。
  #    （build 未存列那一型會在驗證段吵著失敗——錯誤訊息指錯方向，但至少是吵的；
  #    屬性修改這一型完全靜默，是兩者中必須先堵的。）
  #
  # 🔴 **為什麼也不能只讀關聯快取**（reset 當初要修的問題，仍然成立）：
  #    寫入 service 的典型形態是先讀變體（關聯已載入）→ 直接
  #    `ProductVariantOptionValue.create!`／`destroy` 動 join 表 → `variant.save!`。
  #    此時快取是載入當下的快照 ⇒ digest 算出來是舊的，而唯一索引只認 digest。
  #
  # ⇒ 兩個問題的共同解：**以 DB 為底、疊上記憶體中 autosave 將要落地的增量**——
  #    新列（`new_record?`）加入、標記刪除的列剔除、屬性被改的持久列以記憶體值覆蓋。
  #    這樣「直接動 DB」與「透過關聯改」兩條路徑都算得對，且不動 autosave 目標。
  #
  # ⚠️ 代價：已持久化變體每次驗證多一次 `pluck`（digest 與驗證各一次）。
  #    相對於「digest 與 join 列不一致」這種查不出來的錯，可以接受。
  #
  # ⚠️ **已知邊界（Rails 全域語義，本 model 攔不了）**：在**未載入**的關聯上呼叫
  #    `.first`／`.find` 會另發查詢、回傳**不在 target 裡**的獨立物件——改它的屬性
  #    再 `variant.save!`，autosave 與本方法都看不見（物件根本不在關聯裡）。
  #    要改既有列：①先載入（`to_a`／遍歷）再改，或 ②改完自己 `row.save!` 再存變體
  #    （後者走 db_pairs 路徑，一樣正確）。
  #
  # @return [Array<Array(Integer, Integer)>] `[[product_option_id, option_value_id], ...]`
  # @note 副作用：無（不觸發關聯載入、不動 autosave 目標）。
  def effective_option_value_pairs
    assoc = product_variant_option_values
    # 🔴 讀 `target` 而不是先看 `loaded?`：`build` 只把新列放進 target，
    #    **不會**把關聯標成 loaded ⇒ 用 loaded? 當閘門會把「未載入但有 build 列」
    #    的情形整批漏掉（實測：save! 在驗證段誤報「缺」）。
    #    target 的語義正好是我們要的：未載入時＝只有記憶體新列；已載入時＝DB 快照＋新列。
    loaded = assoc.target

    new_pairs = loaded.select(&:new_record?).reject(&:marked_for_destruction?)
                      .map { |r| [ r.product_option_id, r.option_value_id ] }
    gone_ids = loaded.select { |r| r.persisted? && r.marked_for_destruction? }.filter_map(&:id)
    edited = loaded.select do |r|
      r.persisted? && !r.marked_for_destruction? &&
        (r.changed & %w[product_option_id option_value_id]).any?
    end
    edited_pairs = edited.map { |r| [ r.product_option_id, r.option_value_id ] }

    db_pairs =
      if persisted?
        # acts_as_tenant 會自動補 shop_id 條件；索引＝uq_pvov_variant_option 的最左前綴。
        ProductVariantOptionValue.where(product_variant_id: id)
                                 .where.not(id: gone_ids + edited.map(&:id))
                                 .pluck(:product_option_id, :option_value_id)
      else
        []
      end

    db_pairs + edited_pairs + new_pairs
  end
end
