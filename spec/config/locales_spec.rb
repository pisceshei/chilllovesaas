# frozen_string_literal: true

require "rails_helper"
require "yaml"

# 伺服端語言包（ML-1）。兩件事：
#   ① 五個 yml 的 key 集合必須逐字相同（缺鍵＝該語言員工看到英文 fallback，靜默降級）。
#   ② app 程式裡寫死的每一個 `I18n.t("…")` key，五語都必須真的存在。
#
# 🔴 ① 原本用 `.slice(:product, :staff)` 白名單挑子樹，而白名單本身就是坑——
#    ML-3 新增的 `errors.collection` 從來沒被檢查過，於是兩個鍵被誤植到
#    `errors.product` 底下（en.yml 有兩個 `handle_taken:`，插入時配對到第一個），
#    五個檔案「一致地錯」，parity 全綠，線上才出現 `Translation missing`。
#    ⇒ 改成**直接讀我方的 yml 檔**比對，不再有需要記得維護的名單。
RSpec.describe "config/locales" do
  LOCALE_TAGS = %w[en zh-Hant zh-Hans ja fr].freeze

  def flatten(hash, prefix = nil)
    hash.flat_map do |key, value|
      full = [ prefix, key ].compact.join(".")
      value.is_a?(Hash) ? flatten(value, full) : [ full ]
    end
  end

  # 我方 yml 的整棵樹（該檔頂層唯一 key 是 locale tag）。
  def tree_for(tag)
    YAML.load_file(Rails.root.join("config/locales/#{tag}.yml")).fetch(tag)
  end

  it "五語 yml 的 key 集合與 en 一致，且值非空" do
    expect(LOCALE_TAGS).to eq(Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s))
    en_keys = flatten(tree_for("en")).sort
    expect(en_keys).not_to be_empty

    LOCALE_TAGS.each do |tag|
      keys = flatten(tree_for(tag)).sort
      expect(keys).to eq(en_keys), "#{tag} 的 key 集合與 en 不同：多 #{(keys - en_keys).inspect}／少 #{(en_keys - keys).inspect}"
      keys.each do |key|
        expect(I18n.t(key, locale: tag, default: "").to_s.strip).not_to be_empty, "#{tag}.#{key} 為空"
      end
    end
  end

  # 🔴 這條擋的是 parity 擋不到的形態：五個檔案**一致地**把鍵放錯位置。
  #    parity 只問「五語一不一樣」，這條問「程式要的那個 key 在不在」。
  it "app 程式引用的每個字面 I18n key，五語都存在" do
    referenced = Dir[Rails.root.join("app/**/*.rb")].flat_map do |path|
      File.read(path).scan(/I18n\.t\(\s*["']([a-z0-9_.]+)["']/).flatten
    end.uniq.sort
    expect(referenced).not_to be_empty

    missing = referenced.flat_map do |key|
      LOCALE_TAGS.filter_map { |tag| "#{tag}.#{key}" if I18n.t(key, locale: tag, default: nil).nil? }
    end
    expect(missing).to be_empty, "語言包缺少這些 key（程式會顯示 Translation missing）：#{missing.inspect}"
  end

  it "Rails available_locales 與 limits ui_locales 鏡像一致" do
    expect(I18n.available_locales.map(&:to_s).sort).to eq(Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s).sort)
  end
end
