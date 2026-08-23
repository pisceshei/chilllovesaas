# frozen_string_literal: true

require "rails_helper"
require "csv"

# ML-5b：翻譯 CSV 匯出／匯入（docs/specs/67 §E.6）。
# 🔴 本檔的重點是**四種「不變更」的表達**與**清空的唯一手段**——這兩條寫錯就是資料毀損。
RSpec.describe "Admin translation CSV", type: :request do
  let(:shop) { create(:shop, subdomain: "csv-i18n-shop") }
  let!(:staff) do
    ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:, owner: true) }
  end
  let!(:product) do
    ActsAsTenant.with_tenant(shop) do
      create(:product, shop:, title: "Rose Tonnerre", description_html: "<p>Rose</p>", seo_title: "Rose SEO")
    end
  end

  before do
    host! "csv-i18n-shop.lvh.me"
    https!
    Rack::Attack.cache.store.clear
    login!
  end

  describe "匯出" do
    it "8＋1 欄、對齊本尊欄序；未翻譯也出列（status=untranslated）、market 欄恆空" do
      get admin_translations_export_path, params: { locales: "ja" }

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to include("translations-product-ja.csv")
      table = CSV.parse(response.body, headers: true)
      expect(table.headers).to eq(%w[
        resource_type resource_gid field_key locale market_handle status source_text translated_text source_digest
      ])

      title_row = table.find { |row| row["field_key"] == "title" }
      expect(title_row["resource_type"]).to eq("PRODUCT")
      expect(title_row["resource_gid"]).to eq("gid://chilllove/Product/#{product.id}")
      expect(title_row["locale"]).to eq("ja")
      expect(title_row["market_handle"]).to be_nil
      expect(title_row["status"]).to eq("untranslated")
      expect(title_row["source_text"]).to eq("Rose Tonnerre")
      expect(title_row["translated_text"]).to be_nil
      expect(title_row["source_digest"]).to eq(Translation.digest_for("Rose Tonnerre"))
    end

    it "已翻譯／已過期的 status 正確；來源語言不出現在匯出檔" do
      ActsAsTenant.with_tenant(shop) do
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "ja", field_key: "title", value: "ローズ",
                            source_locale_tag: "en", source_digest: Translation.digest_for("Rose Tonnerre"),
                            value_source: "human")
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "fr", field_key: "title", value: "Rose FR",
                            source_locale_tag: "en", source_digest: "stale", value_source: "human",
                            outdated: true, outdated_severity: "major")
      end

      get admin_translations_export_path
      table = CSV.parse(response.body, headers: true)
      status_by_locale = table.select { |row| row["field_key"] == "title" }.to_h { |row| [ row["locale"], row["status"] ] }
      expect(status_by_locale["ja"]).to eq("translated")
      expect(status_by_locale["fr"]).to eq("outdated")
      expect(status_by_locale.keys).not_to include("en")
    end

    it "可選擇語言與欄位（縮小 overwrite 的爆炸半徑：範圍由表頭界定）" do
      get admin_translations_export_path, params: { locales: "ja", fields: "title" }
      table = CSV.parse(response.body, headers: true)
      expect(table.map { |row| row["locale"] }.uniq).to eq([ "ja" ])
      expect(table.map { |row| row["field_key"] }.uniq).to eq([ "title" ])
    end
  end

  describe "匯入" do
    def csv_for(rows, headers: nil)
      headers ||= %w[resource_type resource_gid field_key locale market_handle status source_text translated_text source_digest]
      CSV.generate do |output|
        output << headers
        rows.each { |row| output << headers.map { |header| row[header] } }
      end
    end

    def base_row(overrides = {})
      {
        "resource_type" => "PRODUCT",
        "resource_gid" => "gid://chilllove/Product/#{product.id}",
        "field_key" => "title",
        "locale" => "ja",
        "market_handle" => nil,
        "status" => "untranslated",
        "source_text" => "Rose Tonnerre",
        "translated_text" => "ローズトネール",
        "source_digest" => Translation.digest_for("Rose Tonnerre")
      }.merge(overrides)
    end

    def upload(csv, path: admin_translations_import_path, overwrite: false)
      post path, params: {
        file: Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "t.csv"),
        overwrite_existing: overwrite
      }
      response.parsed_body
    end

    it "預覽只算不寫；確認後才寫入（preview_required）" do
      csv = csv_for([ base_row ])

      preview = upload(csv, path: admin_translations_preview_path)
      expect(preview).to include("created" => 1, "updated" => 0, "cleared" => 0, "applied" => false)
      ActsAsTenant.with_tenant(shop) { expect(Translation.count).to eq(0) }

      result = upload(csv)
      expect(result).to include("created" => 1, "applied" => true)
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.sole).to have_attributes(value: "ローズトネール", value_source: "import", outdated: false)
      end
    end

    it "🔴 儲存格空白＝不動作（不是刪除）——譯者交回只填一半的檔案不得毀掉既有譯文" do
      ActsAsTenant.with_tenant(shop) do
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "ja", field_key: "title", value: "既有譯文",
                            source_locale_tag: "en", source_digest: Translation.digest_for("Rose Tonnerre"),
                            value_source: "human")
      end

      result = upload(csv_for([ base_row("translated_text" => nil) ]), overwrite: true)
      expect(result).to include("skipped" => 1, "cleared" => 0, "updated" => 0)
      ActsAsTenant.with_tenant(shop) { expect(Translation.sole.value).to eq("既有譯文") }
    end

    it "🔴 __CLEAR__ 是唯一清空手段" do
      ActsAsTenant.with_tenant(shop) do
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "ja", field_key: "title", value: "要被清掉",
                            source_locale_tag: "en", source_digest: Translation.digest_for("Rose Tonnerre"),
                            value_source: "human")
      end

      result = upload(csv_for([ base_row("translated_text" => "__CLEAR__") ]))
      expect(result).to include("cleared" => 1)
      ActsAsTenant.with_tenant(shop) { expect(Translation.count).to eq(0) }
    end

    it "有值 ∧ 未勾 overwrite ⇒ 既有譯文保持原值（只補新的）；勾了才覆寫" do
      ActsAsTenant.with_tenant(shop) do
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "ja", field_key: "title", value: "原本的",
                            source_locale_tag: "en", source_digest: Translation.digest_for("Rose Tonnerre"),
                            value_source: "human")
      end

      upload(csv_for([ base_row("translated_text" => "新的") ]))
      ActsAsTenant.with_tenant(shop) { expect(Translation.sole.value).to eq("原本的") }

      result = upload(csv_for([ base_row("translated_text" => "新的") ]), overwrite: true)
      expect(result).to include("updated" => 1)
      ActsAsTenant.with_tenant(shop) { expect(Translation.sole.value).to eq("新的") }
    end

    it "缺 source_digest 欄 ⇒ 整檔拒絕（沒有它無法安全回寫）" do
      headers = %w[resource_type resource_gid field_key locale translated_text]
      result = upload(csv_for([ base_row ], headers:))
      expect(result["applied"]).to be(false)
      expect(result["errors"].first["code"]).to eq("INVALID")
      ActsAsTenant.with_tenant(shop) { expect(Translation.count).to eq(0) }
    end

    it "digest 不符 ⇒ 仍寫入但標 outdated＋review_required，並計入報告（不得靜默當成最新）" do
      result = upload(csv_for([ base_row("source_digest" => Translation.digest_for("舊版原文")) ]))
      expect(result).to include("created" => 1, "digestMismatch" => 1)
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.sole).to have_attributes(outdated: true, review_required: true, value_source: "import")
      end
    end

    it "逐行錯誤：未啟用語言／來源語言／非空 market 各自被拒，其餘行照常寫入" do
      rows = [
        base_row("locale" => "ko", "translated_text" => "장미"),
        base_row("locale" => "en", "translated_text" => "English"),
        base_row("locale" => "fr", "market_handle" => "hk", "translated_text" => "Rose"),
        base_row("locale" => "zh-Hant", "translated_text" => "玫瑰雷鳴")
      ]
      result = upload(csv_for(rows))

      expect(result["created"]).to eq(1)
      codes = result["errors"].map { |error| error["code"] }
      expect(codes).to contain_exactly("LOCALE_NOT_ENABLED", "INVALID", "INVALID")
      ActsAsTenant.with_tenant(shop) do
        expect(Translation.pluck(:locale_tag)).to eq([ "zh-Hant" ])
      end
    end

    it "匯出→匯入往返：欄位與 digest 對得上，內容不變" do
      ActsAsTenant.with_tenant(shop) do
        Translation.create!(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                            locale_tag: "ja", field_key: "title", value: "ローズ",
                            source_locale_tag: "en", source_digest: Translation.digest_for("Rose Tonnerre"),
                            value_source: "human")
      end
      get admin_translations_export_path, params: { locales: "ja", fields: "title" }
      exported = response.body

      result = upload(exported, overwrite: true)
      expect(result["digestMismatch"]).to eq(0)
      ActsAsTenant.with_tenant(shop) { expect(Translation.sole.value).to eq("ローズ") }
    end
  end

  def login!
    post login_path, params: { email: staff.email, password: "long-password-123" }
    expect(response).to redirect_to(admin_root_path)
  end
end
