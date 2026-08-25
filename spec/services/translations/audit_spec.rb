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

    it "🔴 S5：新增第二個 :html 欄時 audit 必須跟著看得到（不得硬編 body_html）" do
      # `Fields::KIND` 是單一中繼資料表；audit 若硬編欄名，新增 html 欄就靜默漏掃。
      stubbed = Translations::Fields::KIND.merge("meta_title" => :html)
      stub_const("Translations::Fields::KIND", stubbed)
      product = product!
      raw_translation!(product, "ja", "meta_title", "<p>ok</p><script>alert(1)</script>")

      rules = described_class.call(shop:).findings.map(&:rule)

      expect(rules).to eq([ "unsanitized_html" ]),
        "audit 用 Fields.kind 判型別才會跟著這張表走；硬編 body_html 時這裡會是 []"
    end

    it "🔴 A5：**停用**語言的譯文不是孤兒（enabled=false 是官方的「下架但譯文保留」）" do
      product = product!
      raw_translation!(product, "ja", "title", "ローズ")
      ActsAsTenant.with_tenant(shop) { ShopLocale.find_by!(locale_tag: "ja").update!(enabled: false, published: false) }

      report = described_class.call(shop:)

      expect(report.findings).to be_empty,
        "首版用 enabled_tags 比對 ⇒ 每家用過停用鈕的店 audit 恆非零、恆 abort"
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

    it "🔴 A1/S1：sanitize 後會變空的列歸類為 blank_value（不是 unsanitized_html）" do
      product = product!
      # <iframe> content-bearing 但不在白名單 ⇒ BlankValue 判非空、sanitize 後為 ""。
      raw_translation!(product, "ja", "body_html", '<iframe src="https://e/"></iframe>')

      rules = described_class.call(shop:).findings.map(&:rule)

      expect(rules).to eq([ "blank_value" ]),
        "首版歸成 unsanitized_html ⇒ fix 會 update_columns(value: '') 造出鬼列"
    end

    it "🔴 A1/S1：fix 這種列＝刪列，且**不留下空字串**、model 仍然有效" do
      product = product!
      raw_translation!(product, "ja", "body_html", "<video src=x></video>")

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(1)
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.where(locale_tag: "ja", field_key: "body_html")).to be_empty
        expect(Translation.where(value: "")).to be_empty, "任何列都不該被寫成空字串"
      end
    end

    it "🔴 A1/S1：fix 之後再 audit 必須乾淨（首版不冪等，要跑兩次才收斂）" do
      product = product!
      raw_translation!(product, "ja", "body_html", '<iframe src="https://e/"></iframe>')
      raw_translation!(product, "fr", "body_html", "<p>ok</p><script>alert(1)</script>")

      described_class.call(shop:, fix: true)
      second = described_class.call(shop:)

      expect(second.findings).to be_empty,
        "第二輪還有 #{second.findings_by_rule.inspect} ⇒ fix 不冪等"
      expect(second.clean?).to be(true)
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
        fixed_row = Translation.find_by(locale_tag: "ja", field_key: "body_html")
        expect(fixed_row.value).to eq("<p>ok</p>alert(1)")
        expect(fixed_row).to be_valid, "修復後的列必須通過 model 驗證（首版用 update_columns 繞過）"
        # 🔴 `update!` 而不是 `update_columns`：後者跳過驗證**也跳過 updated_at**，
        #   而 updated_at 是 67 §G.3 的 stamp 來源——修復動了值卻不推進時戳＝前台不失效。
        expect(fixed_row.updated_at).to be > fixed_row.created_at
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

  describe "🔴 C2：掃描與修復之間值變了 ⇒ 重驗擋下，不盲刪" do
    it "掃描後被商家改成真內容的列不會被刪，計入 skipped_stale" do
      product = product!
      row = raw_translation!(product, "ja", "body_html", "<p>&#160;</p>")

      # 在掃描完成、修復開始之前把值改成真內容（模擬商家同時儲存）。
      allow(Translations::Upsert).to receive(:recompute_status).and_call_original
      original = Translation.method(:lock)
      allow(Translation).to receive(:lock).and_wrap_original do |orig|
        ActsAsTenant.with_tenant(shop) do
          Translation.where(id: row.id).update_all(value: "<p>日本語の説明</p>")
        end
        allow(Translation).to receive(:lock) { original.call }
        original.call
      end

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(0)
      expect(report.skipped_stale).to eq(1)
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.find_by(id: row.id).value).to eq("<p>日本語の説明</p>")
      end
    end
  end

  describe "🔴 F8：修復不得無中生有 translation_status 列" do
    it "同時命中 blank_value 與 source_locale_row 的列：修掉之後不為來源語言造 status 列" do
      product = product!
      raw_translation!(product, "en", "body_html", "<p>&#160;</p>")   # en＝來源語言、又是空值

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(1)
      ActsAsTenant.with_tenant(shop) do
        expect(TranslationStatus.where(locale_tag: "en")).to be_empty,
          "Upsert.commit 從不為來源語言建 status 列；audit 修復也不得建（後台會多出 en 0/2）"
      end
    end

    it "orphan 語言的列被修掉時：既有 status 列照樣歸零，但沒有就不新造" do
      product = product!
      raw_translation!(product, "ko", "body_html", "<p>&#160;</p>")   # ko 不在 shop_locales

      report = described_class.call(shop:, fix: true)

      expect(report.fixed).to eq(1)
      ActsAsTenant.with_tenant(shop) do
        expect(TranslationStatus.where(locale_tag: "ko")).to be_empty
      end
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
