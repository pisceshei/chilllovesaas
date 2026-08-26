# frozen_string_literal: true

# 第 12 包：補齊既有 Product／ProductVariant／Collection 的發布列。
#
# 🔴 **為什麼需要這支**：`resource_publications` 自 `20260814200000` 建立以來，
# 倉庫裡沒有任何程式碼會建立它的列（`docs/specs/88` §5 待辦 #2 明文延後）。
# 本包補上了三個 `after_create` 生產者，但它們只管**未來**建立的資源；
# **歷史資料**要靠這支回填。兩半缺一等於沒修——這與 88 §5 #1 的
# 「callback 修未來、migration 修歷史」是同一條教訓，那次也是兩半。
#
# 🔴 **本檔刻意只是一個薄呼叫端，實作在 `Publications::Materialize.backfill_all!`。**
#   2026-08-26 對抗審查發現：前一版把回填邏輯**抄一份**寫在這裡，而它的 spec
#   又抄了第三份 ⇒ 規則有三份實作，而測試守的是它自己那一份。實測後果：
#   把這裡的 `where(shop_id:)` 刪掉一個 token 會寫出跨租戶的列、把
#   `auto_publish: true` 拿掉會回填成完全相反的管道集合——**兩者 spec 都全綠**。
#   ⇒ 邏輯收斂到服務層一份，本檔不得再長出自己的規則。
#
# @see app/services/publications/materialize.rb
# @see docs/dev/m2-publication-model.md §7
class BackfillResourcePublications < ActiveRecord::Migration[8.1]
  def up
    say_with_time "backfill resource_publications for existing publishables" do
      Publications::Materialize.backfill_all!
    end
  end

  def down
    # 不可逆：無法區分「本次回填建的列」與「使用者後來手動發布的列」。
    raise ActiveRecord::IrreversibleMigration
  end
end
