# frozen_string_literal: true

require "rails_helper"

# 伺服端語言包 key 同構（ML-1）：en.yml 是正典，其餘四檔 key 集合必須逐字相同。
# 缺鍵＝該語言員工看到英文 fallback（靜默降級）；多鍵＝死字串。
RSpec.describe "config/locales key parity" do
  def flatten(hash, prefix = nil)
    hash.flat_map do |key, value|
      full = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flatten(value, full) : [ full ]
    end
  end

  it "五語 yml 的 key 集合與 en 一致，且值非空" do
    locales = Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s)
    expect(locales).to include("en")
    I18n.backend.send(:init_translations) unless I18n.backend.initialized?
    # 只比我方的子樹（errors.product／errors.staff）：Rails 自帶的 en 預設鍵（errors.messages、number.* …）不在五語包射程。
    ours = ->(tag) { (I18n.backend.send(:translations).dig(tag.to_sym, :errors) || {}).slice(:product, :staff) }
    en_keys = flatten(ours.call("en"), "errors").sort
    expect(en_keys).not_to be_empty

    locales.each do |tag|
      tree = ours.call(tag)
      expect(flatten(tree, "errors").sort).to eq(en_keys), "#{tag} 的 key 集合與 en 不同"
      flatten(tree, "errors").each do |key|
        expect(I18n.t(key, locale: tag).to_s.strip).not_to be_empty, "#{tag}.#{key} 為空"
      end
    end
  end

  it "Rails available_locales 與 limits ui_locales 鏡像一致" do
    expect(I18n.available_locales.map(&:to_s).sort).to eq(Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s).sort)
  end
end
