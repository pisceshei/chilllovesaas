# frozen_string_literal: true

require "rails_helper"

# 第 7 包：既有譯文稽核。對象是**在本包判準立起來之前**就落庫的列。
RSpec.describe Translations::Audit do
  let(:shop) { create(:shop, subdomain: "audit-shop") }

  def product!(**attrs)
    ActsAsTenant.with_tenant(shop) { create(:product, shop:, **attrs) }
  end

  # 🔴 一律用 `insert_all` 繞過 model callback：稽核的對象就是「照現在的規則寫不進來」的列，
  #   走正規寫入路徑根本造不出 fixture（那正是本包補上判準的證明）。
  def raw_translation!(resource, locale, field, value)
    ActsAsTenant.with_tenant(shop) do
      now = Time.current
      Translation.insert_all!([ {
        shop_id: shop.id, resource_type: "PRODUCT", resource_id: resource.id,
        locale_tag: locale, field_key: field, value:,
        source_locale_tag: "en", source_digest: Translation.digest_for("x"),
        value_source: "human", created_at: now, updated_at: now
      } ])
      Translation.find_by!(shop_id: shop.id, resource_id: resource.id, locale_tag: locale, field_key: field)
    end
  end

  describe "規則值域（四條，逐條）" do
    it "blank_value：語義空 HTML 的列被抓出來" do
      product = product!
      raw_translation!(product, "ja", "body_html", "<p>&#160;</p>")

      report = described_class.call(shop:)

      expect(report.findings.map(&:rule)).to include("blank_value")
      expect(report.scanned).to eq(1)
    end

    it "unsanitized_html：帶 <script>／onerror 的 body_html 被抓出來" do
      product = product!
      raw_translation!(product, "ja", "body_html", "<p>ok</p><script>alert(1)</script>")

      report = described_class.call(shop:)

      expect(report.findings.map(&:rule)).to eq([ "unsanitized_html" ])
    end

    it "orphan_locale：locale_tag 不在 shop_locales" do
      product = product!
      raw_translation!(product, "ko", "title", "장미")   # 新店預設沒有 ko

      report = described_class.call(shop:)

      expect(report.findings.map(&:rule)).to eq([ "orphan_locale" ])
    end

    it "source_locale_row：來源語言的文字應該在 base row" do
      product = product!
      raw_translation!(product, "en", "title", "Rose")

      report = described_class.call(shop:)

      expect(report.findings.map(&:rule)).to eq([ "source_locale_row" ])
    end

    it "乾淨的列不產生任何 finding" do
      product = product!
      raw_translation!(product, "ja", "title", "ローズ")
      raw_translation!(product, "ja", "body_html", "<p>薔薇</p>")

      report = described_class.call(shop:)

      expect(report.findings).to be_empty
      expect(report.clean?).to be(true)
      expect(report.scanned).to eq(2)
    end

    it "🔴 kind 決定判準：同一個 `<p>&#160;</p>`，html 欄判空、text 欄是內容" do
      product = product!
      raw_translation!(product, "ja", "body_html", "<p>&#160;</p>")
      raw_translation!(product, "ja", "title", "<p>&#160;</p>")

      findings = described_class.call(shop:).findings

      expect(findings.map { |f| [ f.field_key, f.rule ] }).to eq([ [ "body_html", "blank_value" ] ])
    end

    it "🔴 空值列不會同時被登記成 unsanitized_html（一列一筆，修復動作才不會互相打架）" do
      product = product!
      raw_translation!(product, "ja", "body_html", "<script></script>")   # 空且未 sanitize

      rules = described_class.call(shop:).findings.map(&:rule)

      expect(rules).to eq([ "blank_value" ])
    end
  end

  describe "🔴 fail-open 防線（鐵律 20.2 第 5 類）" do
    it "零掃描 canary：一列都沒有時 scanned 是 0 且 clean? 為真——呼叫端必須看得出差別" do
      report = described_class.call(shop:)

      expect(report.scanned).to eq(0)
      expect(report.findings).to be_empty
      # 🔴 rake 任務據此印「這家店一列譯文都沒有」而不是「乾淨」。
      #    這一格的用途是把「0 掃描」與「0 發現」在 API 層就分得開。
    end

    it "🔴 script_mismatch 一律登記為棄權，**絕不回報 0 筆**" do
      product = product!
      raw_translation!(product, "zh-Hant", "title", "玫瑰")

      report = described_class.call(shop:)

      abstained = report.abstained.map { |item| item[:rule] }
      expect(abstained).to eq([ "script_mismatch" ])
      expect(report.findings_by_rule).not_to have_key("script_mismatch")
      expect(report.abstained.first[:reason]).to include("Apache-2.0")
    end
  end

  describe "--fix" do
    it "刪掉空值列、重寫未 sanitize 的列，並重算 translation_status" do
      product = product!
      # 🔴 `title` 是 :text 欄，`<p>&#160;</p>` 對它是**內容**（帶角括號的標題）——
      #   要造一個 text 欄的空值必須用真的不可見字元。這一格同時證明 kind 有生效。
      raw_translation!(product, "ja", "title", "\u3000")   # 全形空白（跳脫寫）
      raw_translation!(product, "ja", "body_html", "<p>ok</p><script>alert(1)</script>")

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(2)
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.where(locale_tag: "ja", field_key: "title")).to be_empty
        expect(Translation.find_by(locale_tag: "ja", field_key: "body_html").value)
          .to eq("<p>ok</p>alert(1)")
        status = TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "ja")
        expect(status.translated_fields).to eq(1)   # title 被刪、body_html 留下
        expect(status.required_fields).to eq(2)
      end
    end

    it "🔴 orphan_locale 與 source_locale_row **不動**（牽涉商家意圖，刪錯不可逆）" do
      product = product!
      raw_translation!(product, "ko", "title", "장미")
      raw_translation!(product, "en", "title", "Rose")

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(0)
      expect(report.findings.length).to eq(2)
      ActsAsTenant.with_tenant(shop) { expect(Translation.count).to eq(2) }
    end

    it "fix: false（預設）不動任何一列" do
      product = product!
      raw_translation!(product, "ja", "title", "<p>&#160;</p>")

      described_class.call(shop:)

      ActsAsTenant.with_tenant(shop) { expect(Translation.count).to eq(1) }
    end
  end

  describe "租戶隔離（鐵律 2）" do
    it "只掃本店，不碰別店的譯文" do
      other = create(:shop, subdomain: "audit-other")
      mine = product!
      theirs = ActsAsTenant.with_tenant(other) { create(:product, shop: other) }
      raw_translation!(mine, "ja", "body_html", "<p>&#160;</p>")
      ActsAsTenant.with_tenant(other) do
        now = Time.current
        Translation.insert_all!([ {
          shop_id: other.id, resource_type: "PRODUCT", resource_id: theirs.id,
          locale_tag: "ja", field_key: "body_html", value: "<p>&#160;</p>",
          source_locale_tag: "en", source_digest: Translation.digest_for("x"),
          value_source: "human", created_at: now, updated_at: now
        } ])
      end

      report = described_class.call(shop:, fix: true)

      expect(report.scanned).to eq(1)
      expect(report.fixed).to eq(1)
      ActsAsTenant.with_tenant(other) { expect(Translation.count).to eq(1) }
    end
  end
end
