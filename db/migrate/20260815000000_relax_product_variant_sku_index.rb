# SKU 從**硬唯一**降級為**軟唯一**：`uq_product_variants_sku` → `ix_product_variants_sku`。
#
# 為什麼：`config/limits.yml:2504` 早已宣告 `sku_unique_per_shop: false`，
# 出處是 `docs/research/61` §1.5（help 原文）——本尊「偵測到重複顯示警告但**不阻擋**」。
# M0 建表時（`20260811000000` 第 272 行 `tenant_index :product_variants, :sku, unique: true`）
# 建成唯一索引，於是**規格與實作互相矛盾**，而矛盾的那一側（DB）是會擋住商家的那一側。
#
# 🔴 唯一索引具體會擋掉兩種**合法**情境（61 §1.5）：
#   ① 同款不同包裝共用 SKU（例如同一支口紅的單支裝與三入裝走同一組庫存編號）；
#   ② CSV 批次匯入——本尊的匯入器對重複 SKU 是**警告後照樣寫入**，
#      唯一索引會讓整批匯入在中途 `RecordNotUnique` 失敗。
# 兩者都是「商家做了官方允許的事，我方卻回失敗」，方向與鐵律 12（1:1 對齊）相反。
#
# 🔴 **降級之後重複 SKU 的提示沒有地方回**：63 §B.6 要求走 payload 的
# `warnings{field,message,code}`（不是 `userErrors`——後者代表操作失敗，鐵律 4），
# 而 `docs/research/28` §0.3 的 payload 目前只有 `{resource, userErrors}`，
# **`warnings` 慣例至今不存在**（63 §L-9 已登記）。本 migration 只降級索引，
# 提示機制待第一支變體 mutation 落地時一併裁定——在那之前，重複 SKU 是靜默允許的。
#
# 🔴 **本 migration 不解決 sku 雙寫**：`sku` 同時存在於 `product_variants` 與
# `inventory_items` 兩張表，而 63 §B.6 判定權威表是 `inventory_items`
# （`limits.yml:2499` `sku_owner: inventory_item`，理由是避免雙寫漂移）。
# 這個偏差在本 migration 之前就已存在，此處**刻意不順手加同步 callback**——
# 那會把一個結構問題用一個隱形副作用蓋住。登記為已知偏差。
#
# @see docs/research/61-shopify-docs-products.md §1.5
# @see docs/research/63-cross-spec-reconciliation.md §B.6、§L-1、§L-9
# @see config/limits.yml:2497-2510
class RelaxProductVariantSkuIndex < ActiveRecord::Migration[8.1]
  # 🔴 索引名同時換掉（`uq_` → `ix_`），不是只拿掉 unique 旗標。
  # 本倉庫的索引命名前綴是**語義的一部分**（`uq_` 唯一／`ix_` 一般，見
  # `db/migrate/20260811000000` 的 `tenant_index` helper），留著 `uq_` 這個名字
  # 會讓之後讀 schema.rb 的人以為它還是唯一索引——那正是本次矛盾的來源形態。
  def up
    remove_index :product_variants, name: "uq_product_variants_sku"
    add_index :product_variants, %i[shop_id sku], name: "ix_product_variants_sku"
  end

  # 🔴 `down` 會**重建唯一索引**，因此它是全庫唯一一個 `uq_product_variants_sku`
  # 的合法出現處。`spec/migrations/pr1_schema_alignment_spec.rb` 的「全庫不得出現」
  # 斷言必須明列排除本檔，否則那條斷言會被本檔自己判紅
  # （排除清單用具名常數，改動會出現在 diff 裡）。
  #
  # ⚠ 若既有資料已經有重複 SKU，`down` 會失敗——這是正確行為，
  # 不得為了讓 rollback 好過而先刪資料。
  def down
    remove_index :product_variants, name: "ix_product_variants_sku"
    add_index :product_variants, %i[shop_id sku], name: "uq_product_variants_sku", unique: true
  end
end
