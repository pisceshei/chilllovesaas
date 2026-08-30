# frozen_string_literal: true

# 市場的網站呈現（docs/research/29 §1.2；docs/specs/67 §C.8(b)）。
#
# ①這是什麼：一個市場在網路上的一個落點——獨立網域／子網域（`domain_id`）或
#   主網域子資料夾（`subfolder_suffix`），**恰一邊有值（XOR）**；DB CHECK＋model 雙層。
#   實測對照（2026-08-31 market 詳情 Domain/language ⊕ popover）：兩類選項並列＝
#   「New subfolder on chill.deals」動作 vs 網域勾選清單——與 XOR 同構。
# ②繼承：web presence 沿 lineage **累加**（limits `market.inheritance_additive`）——
#   市場自身可以零 presence（`inherit_primary`，limits `market.web_presence.default_for_new_market`）。
# ③default_shop_locale：該 presence 的預設語言；與 mwpl.is_market_default **同一真相**
#   （67 §C.8(b)），改預設走 #set_default_locale!，不得各改一半。
# ④跨功能影響：`Markets::UrlPrefix`（前綴的 region 半邊；多國市場 subfolder_suffix 兼任
#   region 識別字——V-225 暫案 C）；`Markets::PrefixIndex`（前綴 ≡ (market, locale) 身分，
#   67 §F.1(c)）；62 §I.1 hreflang 矩陣讀 resolved presences 的開放語言集。
class MarketWebPresence < ApplicationRecord
  SUBFOLDER_SUFFIX_FORMAT = /\A[a-z]{2}\z/

  acts_as_tenant :shop

  # touch：presence 是繼承解析（Domain and language 維度）的輸入 ⇒ bump markets.updated_at
  # （cache stamp；白名單列的 touch 經本表級聯到 market——見 MarketWebPresenceLocale）。
  belongs_to :market, touch: true
  belongs_to :domain, optional: true
  has_many :market_web_presence_locales, dependent: :delete_all

  validates :default_shop_locale, presence: true
  validates :subfolder_suffix,
            format: { with: SUBFOLDER_SUFFIX_FORMAT,
                      message: "必須是兩碼小寫識別字（67 §F.1(b) 前綴正則的 region 段）" },
            allow_nil: true
  validate :domain_xor_subfolder

  # 改 presence 預設語言的唯一入口（67 §C.8(b)：欄位與 is_market_default 同 transaction 翻轉）。
  #
  # @param locale_tag [String] 新預設（必須已在白名單且 open_to_buyers）
  # @raise [ActiveRecord::RecordNotFound] 不在白名單
  # @raise [ActiveRecord::RecordInvalid] 目標未開放（MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED 的鏡像）
  def set_default_locale!(locale_tag)
    transaction do
      target = market_web_presence_locales.find_by!(locale_tag:)
      current = market_web_presence_locales.find_by(is_market_default: true)
      # 先卸旗再上旗：uq_mwpl_single_default 是 (shop, presence, default_guard) 唯一索引，順序反了撞索引。
      current&.update!(is_market_default: false)
      update!(default_shop_locale: locale_tag)
      target.update!(is_market_default: true)
    end
  end

  private

  def domain_xor_subfolder
    return if domain_id.nil? ^ subfolder_suffix.nil?

    errors.add(:base, "domain 與 subfolder_suffix 互斥且必填其一（29 §1.2 XOR）")
  end
end
