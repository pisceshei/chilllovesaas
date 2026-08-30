# frozen_string_literal: true

# JSON template 實例（OS 2.0 形態；包 30／D77）。
#
# `key`＝完整範本名（`index`／`product`／`product.custom`）；`template_type`＝
# 78 §4 窮舉 11 型之一；`content`＝JSON template（sections／order）。
# 引擎解析順序：本表（DB 覆寫）→ 主題來源檔 `templates/<key>.json`（fallback）。
# 範本總數上限走 limits `max_templates_per_theme`（78 §4：官方 1,000）。
class Template < ApplicationRecord
  # 78 §4 窮舉（help 雙源）11 型＋`index`（首頁；help 清單列的是「可新增」型別，
  # 首頁範本每主題固有——Ella fixture `templates/index.json` 實在，不列不能渲染首頁）。
  TEMPLATE_TYPES = %w[
    index product collection list-collections gift_card page cart blog article search password 404
  ].freeze

  acts_as_tenant :shop

  belongs_to :theme

  validates :key, presence: true, length: { maximum: 255 },
                  uniqueness: { scope: %i[shop_id theme_id] }
  validates :template_type, inclusion: { in: TEMPLATE_TYPES }
end
