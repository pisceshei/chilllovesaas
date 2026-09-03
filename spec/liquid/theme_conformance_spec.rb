# frozen_string_literal: true

require "rails_helper"

# D78：主題無關 conformance——每套買斷授權的主題都是平台契約的探針
# （Minimog 6.0.0＝FoxEcom OS 2.0；Kalles 5.4.2＝The4，重度使用 theme blocks
# `blocks/*.liquid`＋`content_for "blocks"/"block"`＋`@theme`/`@app`）。
# 判準（第一階）：全模板可渲染＝每頁 200（404 模板 404）、零 Liquid error、
# 零例外。count_miss 遙測只登記（引擎缺口分類隨後續包），不在此擋。
#
# 🔴 假綠殺手：本格用真主題全模板——任何引擎回歸讓某頁炸出
#   「Liquid error」或例外，此格即紅；基線＝2026-09-02 首跑 0/0（兩套）。
RSpec.describe "Theme conformance（D78 探針）" do
  let(:shop) { create(:shop) }

  # allowed：[[template, /訊息/]] 白名單——只放**資料面缺口造成、本尊對同樣資料也會印**的 Liquid 錯誤（E12：文章無圖片模型，
  # Minimog social-sharing `article.image | image_url` ⇒「invalid url input」，本尊對無圖文章同形；91 §3.79 V）。其餘一律紅。
  def expect_all_templates_render(report, min_pages:, skipped:, allowed: [])
    expect(report[:pages].size).to be >= min_pages, "模板清單縮水：#{report[:pages].size}"
    exceptions = report[:pages].select { |p| p[:exception] }
    expect(exceptions).to eq([]), "渲染例外：#{exceptions.map { |p| "#{p[:template]}: #{p[:exception]}" }.inspect}"
    errored = report[:pages].reject do |p|
      p[:liquid_errors].to_a.reject { |e| allowed.any? { |tpl, re| p[:template] == tpl && e.match?(re) } }.empty?
    end
    expect(errored).to eq([]), "Liquid error：#{errored.map { |p| "#{p[:template]}: #{p[:liquid_errors]}" }.inspect}"
    statuses = report[:pages].to_h { |p| [ p[:template], p[:status] ] }
    expect(statuses["404"]).to eq(404)
    expect(statuses.except("404").values.uniq).to eq([ 200 ])
    expect(report[:skipped]).to include(*skipped)
  end

  it "TC-M1 🔴 Minimog 6.0.0：41 模板全渲染、每頁 200/404 正確、零 Liquid error、零例外" do
    report = conformance_render_all(theme_dir: Rails.root.join("test/fixtures/themes/minimog-6.0.0"),
                                    theme_name: "Minimog", theme_version: "6.0.0", shop:)
    expect_all_templates_render(report, min_pages: 41, skipped: %w[gift_card.liquid password.json],
                                allowed: [ [ "article", /\ALiquid error \(snippets\/social-sharing line \d+\): invalid url input/ ] ])
  end

  it "TC-K1 🔴 Kalles 5.4.2（theme blocks）：60 模板全渲染、每頁 200/404 正確、零 Liquid error、零例外" do
    report = conformance_render_all(theme_dir: Rails.root.join("test/fixtures/themes/kalles-5.4.2"),
                                    theme_name: "Kalles", theme_version: "5.4.2", shop:)
    expect_all_templates_render(report, min_pages: 60, skipped: %w[gift_card.liquid password.liquid])
  end
end
