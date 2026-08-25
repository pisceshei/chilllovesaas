# frozen_string_literal: true

# 第 11 包（D50 案 A）：智慧系列引擎的最小地基——四張表＋collections 兩欄。
#
# ①這是什麼：sources 模型（limits `collection.source_types` 起的整組鍵；正典＝
#   docs/research/95 §1.1 的 2026-08-24 重大修正）的儲存層。
#   🔴 **不是** spec 13 §F4.1 的舊 SQL 塊形態（四型來源 × include/exclude 極性旗標）——
#   那一塊落後於 limits 的修正（本包契約 PR 一併回寫，D50 配套）。
#   本形態：source 只有兩型（conditions／sub_collections）；include/exclude 是
#   conditions source **內部的兩個區塊**（block 欄），各自帶 matchType 與條件。
#
# ②為什麼一次建對（D50）：舊 `collection_rules.condition_value VARCHAR` 用字串存金額
#   （`'148.00'`）＝鐵律 3 禁止的十進位字串入口；金額規則值必須 `value_cents BIGINT`。
#   正式環境 smart=0、collection_rules=0（2026-08-25 實查）⇒ 無資料要遷，改的是空表。
#
# ③🔴 MySQL 唯一索引的 NULL 陷阱（13 §F4.1 明載）：`variant_id IS NULL` 的列彼此「相異」，
#   `UNIQUE(..., variant_id)` 擋不住重複 ⇒ 用產生欄 `variant_key = COALESCE(variant_id, 0)`
#   進唯一索引（同 58 §D.5(b) 的處置）。
#
# ④跨功能影響：寫入者＝`Catalog::SaveCollection`（sources 契約）與
#   `Collections::Rebuild`／`ResyncProduct`（memberships）；讀取者＝三處成員數
#   （model／GraphQL／前端）與日後的前台（30/33，只查 memberships）。
#   `product_tags` 的寫入者＝`Catalog::SaveProduct`（同 tx 維護），讀取者＝tag 條件的
#   EXISTS 求值與（日後）商品頁標籤列。
class CreateSmartCollectionFoundation < ActiveRecord::Migration[8.1]
  def up
    # MySQL DDL 非交易（第 3 包實踩）⇒ 全部 if_not_exists，半途死掉可重跑。
    create_table :product_tags, if_not_exists: true,
                 comment: "商品標籤正規化表（13 §F4.4）：display 顯示、key 比對" do |t|
      t.bigint :shop_id, null: false
      t.bigint :product_id, null: false
      t.string :tag_display, limit: 255, null: false, comment: "商家原字串（同 key 只留首次寫入的）"
      # 🔴 collation 明文 bin（limits `tag_key_collation`）：正規化只有 Tags::Normalize 一處，
      #    DB 不得用 ai_ci 再加一套大小寫/重音等價規則。
      t.string :tag_key, limit: 255, null: false, collation: "utf8mb4_bin",
               comment: "正規化鍵（Tags::Normalize 唯一實作）；比對一律用這欄"
      t.timestamps

      # 13 §F4.3 配套 3：兩個索引都以 shop_id 開頭（鐵律 2）。
      t.index [ :shop_id, :tag_key, :product_id ], unique: true, name: "uq_product_tags_key_product"
      t.index [ :shop_id, :product_id, :tag_key ], name: "ix_product_tags_product"
    end

    create_table :collection_sources, if_not_exists: true,
                 comment: "系列來源（sources 模型；limits collection.source_types）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :collection_id, null: false
      # 🔴 varchar 不用 MySQL ENUM：值域由 limits＋write path 白名單管（加值不 DDL）。
      t.string :source_type, limit: 32, null: false, comment: "conditions / sub_collections"
      t.string :target_type, limit: 16, comment: "products / variants（僅 conditions 型；v1 只收 products）"
      t.bigint :referenced_collection_id, comment: "僅 sub_collections 型：被引用的系列"
      t.bigint :app_id, comment: "app 是 source 的欄位不是型別（95 §1.1）；v1 恆 NULL"
      t.boolean :shareable, comment: "95 §1.1 記載的真實維度；語義未取證（P11 登記），v1 不寫"
      t.string :inclusion_match, limit: 8, null: false, default: "all", comment: "all / any（per block）"
      t.string :exclusion_match, limit: 8, comment: "all / any / NULL（三態；三道裁定 :58-59）"
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index [ :shop_id, :collection_id, :position ], name: "ix_collection_sources_collection"
      # 反向索引：sub_collections 失效傳播（誰引用了我）＋ per-shop 上限計數（13 §F4.5(a)）。
      t.index [ :shop_id, :source_type, :referenced_collection_id ], name: "ix_collection_sources_referenced"
    end

    create_table :collection_source_rules, if_not_exists: true,
                 comment: "typed-value 條件（金額一律 value_cents——鐵律 3；13 §F4.1 修訂形）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :collection_source_id, null: false
      # 🔴 inclusion/exclusion 是**區塊**不是 source 極性（95 §1.1）；exclusion 的條件
      #    型別是 6 值子集——單一 ENUM 表達不了「哪個區塊有哪些欄位」，白名單在
      #    寫入層逐區塊驗（limits `exclusion_condition_types`），這裡只存。
      t.string :block, limit: 12, null: false, comment: "inclusion / exclusion"
      t.string :condition_type, limit: 64, null: false,
               comment: "開放集：未知型別原樣保留（condition_unknown_passthrough）"
      t.string :relation, limit: 32, comment: "已知型別必填；unknown 可 NULL"
      t.string :value_text, limit: 255
      t.bigint :value_cents, comment: "金額規則值唯一合法欄（鐵律 3）"
      t.bigint :value_int
      t.boolean :value_bool
      t.bigint :metafield_definition_id, comment: "metafield 條件（v1 不收，欄位先就位）"
      t.json :raw_payload, comment: "unknown 型別的原樣保存（passthrough 載體）"
      t.integer :position, null: false, default: 0
      t.timestamps

      t.index [ :shop_id, :collection_source_id, :block, :position ],
              unique: true, name: "uq_collection_source_rules_position"
    end

    create_table :collection_memberships, if_not_exists: true,
                 comment: "物化成員（前台唯一查詢對象；13 §F4.6-1）。智慧成員禁入 collection_products" do |t|
      t.bigint :shop_id, null: false
      t.bigint :collection_id, null: false
      t.bigint :product_id, null: false
      t.bigint :variant_id, comment: "NULL＝整商品；非 NULL＝variants 目標（v1 恆 NULL）"
      # 🔴 產生欄擋 NULL 陷阱（檔頭③）。
      t.virtual :variant_key, type: :bigint, as: "COALESCE(`variant_id`, 0)", stored: true
      t.string :origin, limit: 24, null: false, default: "conditions",
               comment: "conditions / manual / nested_collection / app（13 §F4.1）"
      t.bigint :origin_source_id
      t.integer :position, null: false, default: 0
      t.datetime :rebuilt_at, precision: 6, comment: "本輪 rebuild 的世代戳（掃尾依據）"
      t.timestamps

      t.index [ :shop_id, :collection_id, :product_id, :variant_key ],
              unique: true, name: "uq_collection_memberships_member"
      t.index [ :shop_id, :collection_id, :position ], name: "ix_collection_memberships_position"
      # 增量 resync 要按商品反查「它在哪些系列的物化列裡」。
      t.index [ :shop_id, :product_id ], name: "ix_collection_memberships_product"
    end

    add_column :collections, :rebuild_status, :string, limit: 12, if_not_exists: true,
               comment: "OK / PENDING / ERROR（13 §F4.1；NULL＝從未 rebuild 過＝manual 或未啟用）"
    add_column :collections, :rebuilt_at, :datetime, precision: 6, if_not_exists: true,
               comment: "最後一次成功 rebuild 完成時刻"

    # --- product_tags 回填（正式環境 2026-08-25 實查：帶標籤商品 3 筆——量級極小）------
    # 🔴 迴圈走 Ruby 端 Tags::Normalize（唯一實作；不在 SQL 裡重寫一份正規化）。
    #    正規化撞鍵（兩個原字串同 key）⇒ 只留首次、記稽核 log——不靜默丟（13 §F4.4）。
    say_with_time "backfill product_tags from products.tags" do
      Product.unscoped.where.not(tags: []).find_each do |product|
        seen = {}
        Array(product.tags).each do |raw|
          key = Tags::Normalize.key(raw)
          next if key.empty?

          if seen.key?(key)
            say "merge shop=#{product.shop_id} product=#{product.id} #{seen[key].inspect}+#{raw.inspect} -> #{key.inspect}", true
            next
          end
          # 🔴 正規化可能讓 key 比原字串長（NFKC 展開／casefold；收斂輪 J2）⇒
          #   既有資料可能超過欄寬。回填**不得因此中斷整個 db:migrate**：
          #   跳過並記稽核 log（與撞鍵同一種處置——不靜默丟）。
          # 判準引 limits（鐵律 6），且 **raw 與 key 都要守**：`tag_display` 同為
          # varchar(255)，而正規化可能**縮短**（連續空白／`-` 壓縮）⇒ 只守 key 時
          # 「raw>上限 但 key≤上限」的既有列仍會讓 db:migrate 中斷（第六輪 K5）。
          tag_limit = Limits.fetch(:product, :tag_max_chars)
          if key.length > tag_limit || raw.to_s.length > tag_limit
            say "skip oversize shop=#{product.shop_id} product=#{product.id} " \
                "raw_length=#{raw.to_s.length} key_length=#{key.length}", true
            next
          end
          seen[key] = raw
          ProductTag.unscoped.find_or_create_by!(
            shop_id: product.shop_id, product_id: product.id, tag_key: key
          ) { |row| row.tag_display = raw }
        end
      end
    end
  end

  def down
    remove_column :collections, :rebuilt_at, if_exists: true
    remove_column :collections, :rebuild_status, if_exists: true
    drop_table :collection_memberships, if_exists: true
    drop_table :collection_source_rules, if_exists: true
    drop_table :collection_sources, if_exists: true
    drop_table :product_tags, if_exists: true
  end
end
