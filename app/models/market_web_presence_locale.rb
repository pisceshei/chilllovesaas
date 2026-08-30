# frozen_string_literal: true

# per-market 語言白名單的一列（docs/specs/67 §C.8；概念名 `market_locales`）。
#
# ①這是什麼：某 presence 上「開放哪個語言給買家」的開關本體＋切換器順序（position）。
#   🔴 粒度是 **presence** 不是 market（67 §C.8(a)）：一個市場可有多個 resolved presence，
#   「市場的開放語言」是聯集的結果——任何 `UPDATE ... WHERE market_id = ?` 形態的寫入都是 bug。
# ②三層真包含（67 §A.5(a)）：③本表 ⊆ ②shop_locales ⊆ ①platform_locales。
#   ③⊆② 由複合 FK `fk_mwpl_shop_locale` 執法（DB 層）；②⊆① 是 shop_locales 既有 FK。
# ③關閉是狀態轉換不是刪除（67 §C.8）：`open_to_buyers=false`＋`closed_at`；
#   刪列會讓 position／closed_at 一起消失，而 §A.5(c) 情形 3 需要「曾經開過」才能決定 404 與失效範圍。
# ④跨功能影響：Markets::PrefixIndex 只解析 open＋published 的組合（未開放前綴 404——
#   limits `i18n.market_locales.unopened_prefix_status`）；hreflang 矩陣同一開放集（62 §I.1）；
#   開關寫入要掛 62 §I.3(b) 失效管線與 shop_locales_version bump（隨步 3／4 的消費者包接線）。
class MarketWebPresenceLocale < ApplicationRecord
  acts_as_tenant :shop

  # touch 鏈：白名單開關改變前台可路由集合 ⇒ presence → market 級聯 bump
  # markets.updated_at（cache stamp；Rails 的 belongs_to touch 在 touch 時同樣傳播）。
  belongs_to :market_web_presence, touch: true

  validates :locale_tag, presence: true, uniqueness: { scope: %i[shop_id market_web_presence_id] }
  validate :default_matches_presence
  validate :default_stays_open
  validate :prefix_stays_unique

  before_validation { self.locale_tag = Locales::Tag.normalize(locale_tag) if locale_tag.present? }

  scope :open_to_buyers, -> { where(open_to_buyers: true).order(:position, :locale_tag) }

  # 關閉語言（67 §A.5(c) 情形 3）：狀態轉換，不刪列、不動 translations。
  # 影響數字確認對話（§C.8(c) 三數字）與失效管線由 admin 消費端補（本層只管資料語義）。
  def close!
    update!(open_to_buyers: false, closed_at: Time.current)
  end

  def reopen!
    update!(open_to_buyers: true, closed_at: nil)
  end

  private

  # is_market_default 與 presence.default_shop_locale 同一真相（67 §C.8(b)）。
  # 單向檢查（true ⇒ 必須相符）：翻轉過程（set_default_locale!）中舊列先卸旗，雙向 iff 會擋住合法流程。
  def default_matches_presence
    return unless is_market_default
    return if locale_tag == market_web_presence&.default_shop_locale

    errors.add(:is_market_default, "與 presence.default_shop_locale 不符（67 §C.8(b)：兩者同一真相）")
  end

  # 🔴 預設 locale 必須開放（67 §C.8(b)）：關掉預設 ⇒ 地區重導沒有落點（62 §K.2）、
  # localization 表單切國家後沒有語言可落。錯誤碼契約：MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED。
  def default_stays_open
    return unless is_market_default && !open_to_buyers

    errors.add(:open_to_buyers,
               "預設語言不可關閉，先改預設再關（MARKET_DEFAULT_LOCALE_CANNOT_BE_CLOSED）")
  end

  # 🔴 前綴 ≡ (market, locale) 身分（67 §F.1(c)）：同一 effective domain 上兩個 (presence, locale)
  # 不得產生同一前綴——UNIQUE (shop_id, domain_id, url_prefix) 的應用層執法
  # （前綴是推導值不落欄，故唯一性只能在這裡擋；列數＝白名單大小，全表掃描可負擔）。
  def prefix_stays_unique
    presence = market_web_presence
    return if presence.nil? || locale_tag.blank?

    mine = begin
      Markets::UrlPrefix.for(presence, locale_tag)
    rescue Markets::UrlPrefix::Error
      return # region 來源缺失（V-225 fail-closed）由 UrlPrefix 呼叫端處理，不在本驗證重複報
    end

    conflict = self.class
                   .where(shop_id: presence.shop_id)
                   .where.not(id: id)
                   .includes(:market_web_presence)
                   .find do |other|
      other_presence = other.market_web_presence
      next false unless effective_domain_id(other_presence) == effective_domain_id(presence)

      Markets::UrlPrefix.for(other_presence, other.locale_tag) == mine
    rescue Markets::UrlPrefix::Error
      false
    end
    return if conflict.nil?

    errors.add(:locale_tag, "前綴 #{mine} 已被另一組 (market, locale) 佔用（67 §F.1(c)：前綴是身分）")
  end

  # subfolder presence 落在 primary domain 上（29 §1.2 子資料夾＝主網域策略）。
  def effective_domain_id(presence)
    presence.domain_id || Domain.primary.where(shop_id: presence.shop_id).pick(:id)
  end
end
