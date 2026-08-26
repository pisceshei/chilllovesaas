# frozen_string_literal: true

# S0 方案 D（第一批）：`sales_catalogs` 一級表 ＋ `publications` 的五個能力旗標與 operation_status。
#
# 🔴 **為什麼現在做**：`publications.catalog_id` 自 `20260814200000` 起存在，
# **無外鍵、無寫入者、恆為 NULL 兩週**，而本尊**每個 publication 都有 catalog**
# （`docs/research/82` §9.5b／§10.3 兩次抓包）⇒ 我方三層 AND 的第三層永遠是 no-op。
# 使用者 2026-08-26 裁定方案 D（本尊全形），本支是它的第一批。
#
# 🔴 **為什麼叫 `sales_catalogs` 而不是本尊的 `catalogs`**（2026-08-26 實作當下才發現）：
#   本倉庫的 `Catalog` 這個常數**已經被服務層命名空間佔用**——`Catalog::SaveProduct`／
#   `MediaSync`／`SaveCollection`／`CacheStamps`／`HandleChange`／`OptionValuesDigest`／
#   `ExternalVideoUrl`／`DeleteVariant` 等十餘個類都掛在 `module Catalog` 底下，
#   語義是「商家的**商品目錄**操作」。本尊的 `Catalog` 則是「publication ＋ price list
#   的容器」——**同一個字在本倉庫有兩個不同的意思**。
#   建 `class Catalog < ApplicationRecord` 會讓那十餘個服務檔在載入時全部炸
#   `TypeError: Catalog is not a module`（實測：8 個 spec 檔載入失敗）。
#   ⇒ 表名與模型名都加 `sales_` 前綴，兩個概念徹底分開。
#   對外的 GID Type 仍照鐵律 4 對齊本尊（`AppCatalog` 等），那是序列化層的事，與模型名無關。
#
# 🔴 **順帶把 `publications.catalog_id` 改名成 `sales_catalog_id`**：
#   該欄自 `20260814200000` 建立以來 **app 層零讀者零寫者、值恆為 NULL**
#   （複驗：`grep -rn 'catalog_id' app/ lib/` 只有本批新增的行）
#   ⇒ 改名不動任何運行中的程式碼，而留著 `catalog_id` 指向 `sales_catalogs`
#   會讓 Rails 慣例斷掉、日後每個讀到它的人都要先查一次對應關係。
#
# 施工圖＝`docs/plans/2026-08-26-S0-方案D-schema設計.md`。
# 本支只做與 `apps`／`channels` **完全無關**的部分，那兩張表隨第二批（人工合併 PR）。
#
# @see docs/plans/2026-08-26-S0-管道身分模型-決策文件.md
# @see docs/research/82-admin-channels.md §10
class CreateSalesCatalogsAndPublicationCapabilities < ActiveRecord::Migration[8.1]
  def up
    # MySQL DDL 非交易（第 3 包實踩）⇒ 全部 if_not_exists，半途死掉可重跑。
    create_table :sales_catalogs, if_not_exists: true,
                 comment: "本尊 Catalog interface 的我方對位：publication 與 price list 的容器" do |t|
      t.bigint :shop_id, null: false
      # 對位本尊 `CatalogType`。`none` 不落庫——它是「不屬於任何 catalog」的讀取態，不是一種 catalog。
      t.string :catalog_type, limit: 24, null: false, default: "app",
               comment: "app／market／company_location（本尊 CatalogType；none 不落庫）"
      # 🔴 管道顯示名的**權威來源**。本尊 `Publication.name` 已 deprecated → `Catalog.title`。
      #    上限 255 是實測值（82 §9.5c 的表單字元計數器顯示 `0/255`）。
      t.string :title, null: false, limit: 255,
               comment: "顯示名的權威來源（本尊 Publication.name 已 deprecated → Catalog.title）"
      t.string :status, limit: 16, null: false, default: "active",
               comment: "active／archived／draft（本尊 CatalogStatus 三值；admin UI 只曝露前二）"
      # 🔴 與 `publications.auto_publish` 是**兩層不同的東西**，不得合併：
      #    前者＝「新商品要不要納入這個 catalog」（82 §9.5c 實測表單預設**開**）；
      #    後者＝「新 publishable 要不要發布到這個管道」。
      t.boolean :auto_include_new_products, null: false, default: true,
                comment: "新商品是否自動納入本 catalog（本尊表單 Automatically include new products，預設開）"
      t.timestamps
    end

    # tenant-safe FK 的前提：本表要能被 (shop_id, id) 指向（沿用本倉庫既有形態）。
    add_index :sales_catalogs, %i[shop_id id], unique: true,
              name: "uq_sales_catalogs_tenant_id", if_not_exists: true
    add_index :sales_catalogs, %i[shop_id catalog_type status],
              name: "ix_sales_catalogs_type", if_not_exists: true

    # 新建空表加 FK：strong_migrations 的鎖表顧慮不適用（零列）。
    # 同型先例＝`20260824160000_create_file_usages.rb`。
    unless foreign_key_exists?(:sales_catalogs, :shops)
      safety_assured { add_foreign_key :sales_catalogs, :shops, name: "fk_sales_catalogs_shop" }
    end

    # 🔴 改名：`catalog_id` → `sales_catalog_id`（理由見檔頭）。
    #   `safety_assured` 的依據是**該欄無人使用**，不是「表很小」：
    #   strong_migrations 擋 rename_column 的理由是「舊版程式仍在跑、改名後它會找不到欄位」，
    #   而本欄自建立以來 app 層零讀者零寫者（檔頭有複驗指令）⇒ 那個顧慮不成立。
    #   MySQL 8 的 `RENAME COLUMN` 是 metadata-only，不複製資料。
    if column_exists?(:publications, :catalog_id) && !column_exists?(:publications, :sales_catalog_id)
      safety_assured { rename_column :publications, :catalog_id, :sales_catalog_id }
    end

    # 🔴 本尊 Publication 有**六個**能力旗標，我方只有 supports_future_publishing 一個
    #    （82 §10.4 實測）。補上其餘五個。
    #    其中兩個直接解掉舊的未取得：
    #      - `supports_bundles` 解釋了 82 §9.4 那個 `includesBundle` URL 參數；
    #      - `supports_publication_for_unlisted_products` 解釋了 help 那句
    #        「You can't publish unlisted products to any third-party sales channels」
    #        ——它不是寫死的規則，是**逐管道的能力旗標**。
    #    預設 true：v1 唯一的管道是 online_store，實測本尊該管道六個旗標全 true。
    {
      supports_bundles: "本管道是否支援組合商品（bundle）",
      supports_combined_listings: "本管道是否支援 combined listing",
      supports_variant_fixed_bundles: "本管道是否支援變體固定組合",
      supports_subscriptions: "本管道是否支援訂閱商品",
      supports_publication_for_unlisted_products: "本管道是否接受 UNLISTED 狀態的商品"
    }.each do |column, comment|
      add_column :publications, column, :boolean, null: false, default: true, comment: comment,
                 if_not_exists: true
    end

    # 進行中的非同步發布操作。NULL＝沒有進行中的操作。
    # 🔴 本尊 `ResourceOperationStatus` **恰三值 created／active／complete，沒有 failed**。
    #    82 §9.5d 實測：進行中時 admin 會鎖住該 catalog 的逐商品切換並顯示
    #    「Publishing for this catalog can't be changed while updates are in progress.」
    # ⚠️ 本支**只建欄位不做狀態機**——狀態機屬 S1（設計文件 §6 第 3 條明文劃線）。
    add_column :publications, :operation_status, :string, limit: 16,
               comment: "進行中的發布操作：created／active／complete；NULL＝無（本尊 ResourceOperationStatus 恰三值，無 failed）",
               if_not_exists: true

    # ── 回填：為每筆既有 publication 建一筆 catalog 並寫回 sales_catalog_id ──────
    #
    # 🔴 **整段包 `ActsAsTenant.without_tenant`**：`Publication` 宣告 `acts_as_tenant :shop`，
    #   而 `require_tenant = true` ⇒ 沒有 current_tenant 時**讀**被 default scope 過濾、
    #   **寫**直接 raise `NoTenantSet`。migration 跑在 `bin/rails db:migrate`，那裡沒有租戶。
    #
    # 🔴 **配對 spec 非有不可**（第 11／12 包換來的固定處理）：回填迴圈的本體只有在
    #   資料庫已有 publication 時才執行；CI 跑空庫、開發庫也常剛好沒有 ⇒ 兩處都不執行
    #   迴圈本體、`db:migrate` 一路綠，只有正式環境會炸。
    #   配對 spec＝`spec/migrations/s0_backfill_catalogs_spec.rb`。
    say_with_time("backfill sales_catalogs for existing publications") { backfill_sales_catalogs! }

    # 回填完才能加約束。
    # 🔴 **不轉 NOT NULL**：轉了之後任何「先建 publication 再建 catalog」的路徑都會炸，
    #   而 `Shop#after_create` 的改寫屬本支的 model 層（同批），但**既有的兩支 migration**
    #   （20260814200000／20260815000010）在重跑舊庫時仍會先建 publication。
    #   ⇒ 約束由 model validation ＋ 外鍵擔保，NOT NULL 留給 S1（那時所有路徑都已對齊）。
    # 🔴 這一支與上面那支不同：`publications` **不是空表**，加 FK 會鎖它。
    #   `safety_assured` 的依據是量級與時序，逐條：
    #     ①`publications` 是**每店一列**的表（`Shop#after_create` 建一列），
    #       行數＝店數，與商品／變體／訂單不同數量級（複驗指令見本檔尾註）；
    #     ②上面的回填**剛剛**把每一列的 `sales_catalog_id` 都填成有效值
    #       ⇒ 驗證既有列不會找到違規列；
    #     ③欄位可為 NULL（本步不轉 NOT NULL），所以回填漏掉的列也不會擋住 FK 建立。
    #   ⚠️ 若日後 `publications` 變成「每店多列」（S0 的多管道），這個判斷要重新做。
    unless foreign_key_exists?(:publications, :sales_catalogs)
      safety_assured do
        add_foreign_key :publications, :sales_catalogs,
                        column: %i[shop_id sales_catalog_id], primary_key: %i[shop_id id],
                        name: "fk_publications_sales_catalog_id"
      end
    end
  end

  def down
    if foreign_key_exists?(:publications, :sales_catalogs)
      remove_foreign_key :publications, name: "fk_publications_sales_catalog_id"
    end
    remove_column :publications, :operation_status, if_exists: true
    %i[supports_bundles supports_combined_listings supports_variant_fixed_bundles
       supports_subscriptions supports_publication_for_unlisted_products].each do |column|
      remove_column :publications, column, if_exists: true
    end
    # 🔴 先清 sales_catalog_id 再刪表，否則 FK 已移除但殘留 id 會讓重跑的 up 跳過回填。
    if column_exists?(:publications, :sales_catalog_id)
      ActsAsTenant.without_tenant { Publication.update_all(sales_catalog_id: nil) }
      rename_column :publications, :sales_catalog_id, :catalog_id
    end
    drop_table :sales_catalogs, if_exists: true
  end

  # 為每筆還沒有 catalog 的 publication 建一筆，並寫回 `sales_catalog_id`。
  #
  # 🔴 **整段包 `ActsAsTenant.without_tenant`**：`Publication` 宣告 `acts_as_tenant :shop`，
  #   而 `require_tenant = true` ⇒ 沒有 current_tenant 時**讀**被 default scope 過濾、
  #   **寫**直接 raise `NoTenantSet`。migration 跑在 `bin/rails db:migrate`，那裡沒有租戶。
  #   ⚠️ 更危險的是**租戶是別間店**的情況：default scope 會把下面的 `where` 過濾成 0 列，
  #   於是回填一列都不做**而 migration 回報成功**。配對 spec 有一格專盯這個形態。
  #
  # 🔴 **查詢刻意不加 `.unscoped`**：那樣 default scope 的 raise 就死了，
  #   「拿掉 `without_tenant` 會炸」這個行為守衛也跟著死。配對 spec 靠它守著。
  #
  # 🔴 **為什麼獨立成方法而不是寫在 `up` 裡**（2026-08-26 實作當下發現）：
  #   `up` 的第一句 `create_table ... if_not_exists: true` 會真的送出
  #   `CREATE TABLE IF NOT EXISTS` ⇒ MySQL **隱式提交**，把 RSpec 的測試交易打斷，
  #   配對 spec 的每一格都會看到前一格殘留的資料。抽出來之後 spec 呼叫的是
  #   **`up` 呼叫的同一個方法本體**（不是副本），而且不碰 DDL。
  #
  # @return [Integer] 新建的 catalog 列數
  # @note 副作用：INSERT `sales_catalogs`、UPDATE `publications.sales_catalog_id`。
  def backfill_sales_catalogs!
    created = 0
    ActsAsTenant.without_tenant do
      Publication.where(sales_catalog_id: nil).find_each do |publication|
        catalog = SalesCatalog.create!(
          shop_id: publication.shop_id,
          catalog_type: "app",
          # 🔴 title 取自 `publications.name`——這是**權威遷移**：遷移完成後
          #   `publications.name` 降級為 legacy 唯讀（設計文件 T5）。
          title: publication.name,
          status: "active"
        )
        publication.update_columns(sales_catalog_id: catalog.id)
        created += 1
      end
    end
    created
  end
end
