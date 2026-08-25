# frozen_string_literal: true

# 物化成員列（13 §F4.6-1：**前台唯一查詢對象**，不即時求值）。
#
# 🔴 寫入面只有 `Collections::Rebuild` 與 `Collections::ResyncProduct` 兩支引擎服務
#   （SQL-only：rebuild 走 INSERT…SELECT，13 §F4.9「只有 SQL 一套」）。
#   手動系列的成員仍在 `collection_products`；智慧成員**禁**寫那張表（兩個真相）。
# 🔴 `variant_key` 是 DB 產生欄（COALESCE(variant_id,0)）——MySQL 唯一索引把 NULL
#   視為彼此相異，沒有它同一商品會被 rebuild 重複寫入（13 §F4.1 陷阱註）。
class CollectionMembership < ApplicationRecord
  acts_as_tenant :shop

  belongs_to :collection
  belongs_to :product

  validates :origin, inclusion: { in: %w[conditions manual nested_collection app] }
end
