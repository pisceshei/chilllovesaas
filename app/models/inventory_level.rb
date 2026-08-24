# frozen_string_literal: true

# 每 (inventory_item, location) 的數量狀態（排程第 16 包；13 §F5；總裁定 §三）。
#
# ①這是什麼：庫存數量的現值表。六個 leaf 實體欄（available／committed／reserved／damaged／
#   safety_stock／quality_control）＋ `incoming`；`unavailable` 與 `on_hand` 是
#   **MySQL STORED GENERATED**——恆等式由 DB 保證（想雙寫也寫不進去），
#   對應本尊 `quantityNames` 的 comprises 關係（docs/research/95 §2，incoming 不在 on_hand 內）。
# ②值域：六 leaf 皆整數、**可為負**（本尊 available 可負＝超賣後狀態；DB 不設 CHECK(>=0)）。
# ③怎麼做：讀多寫少；一切數量變更走 `Inventory::Adjust` 唯一入口（第 17 包，含禁直寫 cop）。
#   本模型在那之前**只讀**——`attr_readonly` 六 leaf 之外沒有任何寫入 API 露出。
# ④跨功能影響：商品列表 totalInventory（同一份 rollup，鐵律 7）、前台可售性（M2）、
#   下單佔用 committed（M3）。
class InventoryLevel < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :inventory_item
  belongs_to :location
  # 🔴 刻意**不**掛 dependent：ledger 是 append-only 稽核資料，任何父層刪除都不得
  #    順手清掉它。FK 無 ON DELETE（＝RESTRICT）是 fail-closed 的刻意形態：
  #    有 ledger 歷史的 level／item／location／product 一律刪不掉，直到第 20 包
  #    （刪除路徑三選一）裁定為止。對抗審查（2026-08-24）抓到原本掛的 delete_all
  #    在 delete_all 父鏈下是死碼，且與稽核意圖自相矛盾——移除。
  has_many :inventory_adjustments

  # generated column：Rails 會照常出現在 attributes，但 INSERT/UPDATE 不得帶它。
  # mysql2 adapter 對 virtual 欄已自動略過寫入；attr_readonly 是第二道保險（防手寫 SQL 以外的路徑）。
  attr_readonly :on_hand, :unavailable
end
