# D12（`docs/DECISIONS.md`）：變體 × 選項值的 join 表 ＋ `option_values_digest` 物化欄。
#
# ## 為什麼要這張表
#
# `docs/specs/13` §F1-2 要求「變體唯一性用唯一索引 `(product_id, option_values_digest)` 兜底」，
# 但 55 張表裡**沒有 variant × option_value 的關聯**，也沒有 digest 欄
# ——D12 原文稱它是「全倉庫唯一一個『查了確實沒有規格』的洞」。
#
# 🔴 **只存 digest 不行**：`docs/specs/63` §B.5 的變體身分保持演算法要「反查這個變體
# 在某個選項上的值是什麼」（而且要對交集內的**每一個**選項各反查一次），不存關聯就跑不了；
# 商品表單的選項矩陣也畫不出來。
#
# 🔴 **不用 `option1/2/3` 冗餘欄**：`docs/research/26` 明載 `variant.option1/2/3` 在 Liquid 是
# 已淘汰屬性，且天生只支援 3 個選項。
#
# ## 表定義出處
#
# 本表是我方自創（本尊沒有這張表，也沒有 digest 這個概念——見下方 digest 段），
# 出處是 `docs/DECISIONS.md` D12 ＋ `docs/specs/13` §F1-2。
# 🔴 **刻意不寫進 `docs/research/06`**：research 記錄本尊的事實、specs 記錄我方要建的東西，
# 把自創表寫進研究檔會污染這條界線（沿用 `20260814200000` 的同一裁定）。
class CreateProductVariantOptionValues < ActiveRecord::Migration[8.1]
  # 空集合的 SHA1 ＝ 無選項變體（本尊的 Default Title）的 digest。
  # 🔴 這個字面值與 `Catalog::OptionValuesDigest::NO_OPTIONS` 必須一致，兩處各有測試釘住。
  #    寫死在 migration 裡而不是 require 那個常數：migration 要能在任何 app 版本下重跑，
  #    不該依賴 app 代碼當時的形狀。
  EMPTY_DIGEST = "da39a3ee5e6b4b0d3255bfef95601890afd80709"

  def up
    # ── 1. 父表補「可被複合外鍵指向」的唯一鍵 ──────────────────────────────────
    #
    # 🔴 **MySQL 8.4 的硬限制**（8.4.9 實測，非設定值而是編譯預設）：
    #    `restrict_fk_on_non_standard_key = 1` ⇒ 外鍵被指向的欄位組必須
    #    **逐字、同順序等於某支 UNIQUE／PRIMARY 索引的完整欄位清單**。
    #      - 指向**最左前綴**不行：父表有 UNIQUE(a,b,c) 時，FK 指向 (a,b) ⇒ ERROR 6125。
    #      - **欄序不同**也不行：UNIQUE(a,b,c) 時 FK 指向 (b,a,c) ⇒ ERROR 6125。
    #    ⇒ 既有的 `uq_*_tenant_id (shop_id, id)` 與
    #      `uq_product_options_product_id_name (shop_id, product_id, name)`
    #      **都無法**讓下面的 FK 指向 `(shop_id, product_id, id)`。
    #
    # 🔴 **下面三支索引不是「順手加的」，是外鍵建得起來的必要條件**，
    #    且欄序必須逐字等於第 4 段三支 FK 的 `primary_key:`。改動任一邊都要同步。
    add_index :product_variants, %i[shop_id product_id id],
      unique: true, name: "uq_product_variants_product_scoped_id"
    add_index :product_options, %i[shop_id product_id id],
      unique: true, name: "uq_product_options_product_scoped_id"
    add_index :option_values, %i[shop_id product_option_id id],
      unique: true, name: "uq_option_values_option_scoped_id"

    # ── 2. digest 欄（13 §F1-2 的唯一性兜底）───────────────────────────────────
    #
    # 🔴 **digest 是我方內部實作，本尊沒有這個概念**（2026-08-15 parity 查證：
    #    `ProductVariant` 型別上只有 `title` 與 `selectedOptions`，沒有任何組合鍵）。
    #    ⇒ **不得出現在 Admin GraphQL 型別上、不得進 GID／feed／URL／CSV**。
    #    因為它不外露，任何時候都可以一句 UPDATE 全表重算 ⇒ 不需要版本前綴欄。
    #    **這兩件事是綁在一起的，不得只留其一。**
    #
    # 🔴 **輸入是 `option_value_id` 不是值字串**。依據 `docs/specs/67` §B.3-4 逐字：
    #    「譯文掛在 `product_option_values.id` 上，不是掛在字串上…若變體以『選項值字串』
    #     比對，切語言就會找不到變體」。⇒ 用字串會讓多語言站的變體身分隨語言漂移。
    #
    # 🔴 **分三步而不是一步 `add_column null: false`**：MySQL 在 STRICT 模式下對既有列
    #    會**靜默填 `''`**（不是報錯），那會寫進一個不是 SHA1 的假 digest。
    #    先可空、明文回填、再收緊，過程可稽核。
    add_column :product_variants, :option_values_digest, :string, limit: 40,
      comment: "選項值組合的 SHA1（13 §F1-2／D12）；輸入是 option_value_id 不是字串；我方內部欄，不得對外曝露"
    safety_assured do # strong_migrations 看不進 execute
      execute "UPDATE product_variants SET option_values_digest = '#{EMPTY_DIGEST}' " \
              "WHERE option_values_digest IS NULL"
    end
    change_column_null :product_variants, :option_values_digest, false

    # 🔴 這支唯一索引**只在 digest NOT NULL 時有效**：MySQL 的 unique index 允許無限多筆
    #    NULL ⇒ 欄位若可空，13 §F1-2 的兜底會**靜默消失**（看起來有約束，其實沒有）。
    # 🔴 以 `shop_id` 開頭（鐵律 2）。13 §F1-2 寫成 `(product_id, ...)` 是省略寫法。
    add_index :product_variants, %i[shop_id product_id option_values_digest],
      unique: true, name: "uq_product_variants_option_values_digest"

    # ── 3. join 表 ────────────────────────────────────────────────────────────
    create_table :product_variant_option_values,
      comment: "變體 × 選項的座標（每個變體對每個選項恰好一列）" do |t|
      t.bigint :shop_id, null: false
      # 🔴 `product_id` 是冗餘欄（可由 variant 推導），但它是**約束載體**不是指標：
      #    沒有它就無法用複合外鍵擋住「同店內把 A 商品的變體掛上 B 商品的選項」，
      #    而 MySQL 的 CHECK **不能跨表**（子查詢 ⇒ ERROR 3815）——沒有第二條路。
      t.bigint :product_id, null: false
      t.bigint :product_variant_id, null: false
      # 🔴 `product_option_id` 冗餘於 `option_value_id`，但唯一索引**只能跨本表欄位**
      #    ⇒ 不存它就無法用索引表達「一個變體在一個選項上只能有一個值」。
      #    它自己的正確性由第 4 段的 `fk_pvov_value`（三欄歸屬 FK）保證，不靠寫入端自律。
      t.bigint :product_option_id, null: false
      t.bigint :option_value_id, null: false
      t.timestamps

      # D12 的核心不變量：一個變體在一個選項上恰好一個值。
      t.index %i[shop_id product_variant_id product_option_id],
        unique: true, name: "uq_pvov_variant_option"
      # 下三支同時是 FK 的最左前綴索引（不宣告的話 MySQL 會自動補、並沿用 FK 名，
      # 那些索引「能用但不歸我們管」——drop FK 時去留由 MySQL 決定）
      # ＋ 查詢用途：載入某商品／某變體的座標、反查「哪些變體用了這個選項值」。
      # 🔴 全部維持 3 欄：strong_migrations 對「非唯一且欄數 > 3」的索引會 raise。
      t.index %i[shop_id product_id product_variant_id], name: "ix_pvov_product_variant"
      t.index %i[shop_id product_id product_option_id],  name: "ix_pvov_product_option"
      t.index %i[shop_id product_option_id option_value_id], name: "ix_pvov_option_value"
      # 租戶慣例：讓別的表日後可以複合外鍵指向本表。
      t.index %i[shop_id id], unique: true, name: "uq_pvov_tenant_id"
    end

    # ── 4. 外鍵 ───────────────────────────────────────────────────────────────
    #
    # strong_migrations 在 MySQL 下對 `add_foreign_key` **一律** raise（原始碼註解逐字：
    # "unlike add_index, we don't make an exception here for new tables"）——新表也不豁免
    # ⇒ 必須 `safety_assured`。安全理由：表剛建立且為空。
    safety_assured do
      # 變體必須屬於本列宣告的商品
      add_foreign_key :product_variant_option_values, :product_variants,
        column: %i[shop_id product_id product_variant_id],
        primary_key: %i[shop_id product_id id], name: "fk_pvov_variant"
      # 選項必須屬於同一個商品（擋跨商品汙染）
      add_foreign_key :product_variant_option_values, :product_options,
        column: %i[shop_id product_id product_option_id],
        primary_key: %i[shop_id product_id id], name: "fk_pvov_option"
      # 🔴 **歸屬一致性**：選項值必須真的屬於本列宣告的那個選項。
      #    少了這一支，`uq_pvov_variant_option` 只約束「本表宣告的 option_id」，
      #    寫入端把 option_id 寫錯就能讓同一個變體同時掛「顏色=紅」與「顏色=藍」。
      #    這支同時吃掉 `(shop_id, option_value_id) → option_values(shop_id, id)`
      #    的租戶外鍵，不必重複宣告。
      add_foreign_key :product_variant_option_values, :option_values,
        column: %i[shop_id product_option_id option_value_id],
        primary_key: %i[shop_id product_option_id id], name: "fk_pvov_value"
      # 冗餘於 fk_pvov_variant，但 M0 的慣例是「每個 parent_id 欄各一支複合外鍵」，
      # **靜默偏離慣例比多一次索引查找更糟**。索引由 ix_pvov_product_variant 前綴覆蓋。
      add_foreign_key :product_variant_option_values, :products,
        column: %i[shop_id product_id], primary_key: %i[shop_id id], name: "fk_pvov_product"
      add_foreign_key :product_variant_option_values, :shops, name: "fk_pvov_shop"
    end
  end

  def down
    drop_table :product_variant_option_values
    remove_index  :product_variants, name: "uq_product_variants_option_values_digest"
    remove_column :product_variants, :option_values_digest
    remove_index  :option_values,    name: "uq_option_values_option_scoped_id"
    remove_index  :product_options,  name: "uq_product_options_product_scoped_id"
    remove_index  :product_variants, name: "uq_product_variants_product_scoped_id"
  end
end
