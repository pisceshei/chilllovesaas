# frozen_string_literal: true

require "rails_helper"

# 第 7 包：**譯文寫入端的兩個缺口**——沒有 sanitize、空值判準與讀取端不同源。
#
# 🔴 缺口實證（2026-08-25 於 bt3 正式環境 rev 1a75ceb 以 `rails runner` 實跑）：
#   同一段 `<p>ok</p><script>alert(1)</script><img src=x onerror=alert(2)>`
#     - 走 `descriptionHtml` ⇒ 落庫 `<p>ok</p>alert(1)<img>`
#     - 走 `translations[body_html]` ⇒ **原樣落庫**，`<script>` 與 `onerror` 俱在
#   第 30／34 包把譯文渲染到前台的那一刻，它就是儲存型 XSS。
#
# 🔴 兩條寫入路徑（GraphQL 的 `Upsert`、CSV 的 `CsvImport`）都要測——只修一條等於
#   把同一個洞留了一個入口。
RSpec.describe "譯文寫入端的 sanitize 與空值判準" do
  let(:shop) { create(:shop, subdomain: "upsert-sanitize") }
  let(:product) { ActsAsTenant.with_tenant(shop) { create(:product, shop:, title: "Rose") } }

  # 🔴 常數定義在 describe 內會落在 Object 上（跨檔會撞名，第 6 包踩過）⇒ 加包號前綴。
  P7_XSS_PAYLOAD = '<p>ok</p><script>alert(1)</script><img src=x onerror=alert(2)>'

  def upsert!(field, value, locale: "ja")
    ActsAsTenant.with_tenant(shop) do
      Translations::Upsert.call(
        shop:, resource_type: "PRODUCT", resource_id: product.id, source_locale: "en",
        source_values: { "title" => "Rose", "body_html" => "<p>Rose</p>" },
        translations: [ { locale:, field:, value: } ]
      )
    end
  end

  def stored(field, locale: "ja")
    ActsAsTenant.with_tenant(shop) do
      Translation.find_by(shop_id: shop.id, resource_type: "PRODUCT", resource_id: product.id,
                          locale_tag: locale, field_key: field)
    end
  end

  describe "🔴 sanitize（本包修補的安全缺口）" do
    it "body_html 譯文與 base 走同一套白名單：<script> 與 onerror 都不落庫" do
      result = upsert!("body_html", P7_XSS_PAYLOAD)

      expect(result.user_errors).to eq([])
      value = stored("body_html").value
      expect(value).not_to include("<script>")
      expect(value).not_to include("onerror")
      expect(value).to include("<p>ok</p>")
    end

    it "落庫值與 base 走 SaveProduct 的結果**逐字相同**（兩份白名單＝兩個真相）" do
      upsert!("body_html", P7_XSS_PAYLOAD)

      expect(stored("body_html").value)
        .to eq(Catalog::SaveProduct.sanitize_description_for(P7_XSS_PAYLOAD))
    end

    it "純文字欄不 sanitize（標題裡的 < > 是內容，不是標籤）" do
      upsert!("title", "A < B")

      expect(stored("title").value).to eq("A < B")
    end

    it "🔴 長度上限量的是 sanitize **之後**的值（同 base 的 SaveProduct#normalize 順序）" do
      # 🔴 注意 `<script>` 的**文字內容會被保留**（實測：`<script>alert(1)</script>` → `alert(1)`），
      #   所以要造「sanitize 後變短」必須用**屬性**：style 不在白名單，整個屬性被移除。
      payload = %(<p style="#{'a' * 200}">ok</p>)
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(100)

      result = upsert!("body_html", payload)

      expect(result.user_errors).to eq([]), "先量長度再 sanitize 會把這個誤判成 TOO_LONG"
      expect(stored("body_html").value).to eq("<p>ok</p>")
    end

    it "🔴 body_html 的上限量的是**位元組**不是字元（與 base 的 bytesize 同單位）" do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(20)

      # 10 個中文字＝30 bytes > 20，但只有 10 個字元——用 `.length` 量會放行。
      result = upsert!("body_html", "<p>#{'玫' * 10}</p>")

      expect(result.user_errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ])
    end
  end

  describe "🔴 空值判準與讀取端同源（BlankValue）" do
    # 舊 regex 實作判「非空」而新判準判「空」的八格裡，挑三格走完整寫入路徑。
    [ "<p>&#160;</p>", "<p><span></span></p>", '<p class="x"></p>' ].each do |html|
      it "#{html.inspect} 判空 ⇒ 刪列（先前會留下一列「後台已翻譯、前台空白」的鬼列）" do
        upsert!("body_html", "<p>real</p>")
        expect(stored("body_html")).to be_present

        upsert!("body_html", html)

        expect(stored("body_html")).to be_nil
      end
    end

    it "有內容的值不會被誤刪（判非空的方向沒有回歸）" do
      upsert!("body_html", '<p><img src="/a.png"></p>')

      expect(stored("body_html")).to be_present
    end

    it "🔴 sanitize 後才判空：<video> 白名單外 ⇒ sanitize 成空 ⇒ 判空刪列" do
      upsert!("body_html", "<p>real</p>")
      upsert!("body_html", "<video src=x></video>")

      # 先判空的話 video 是 content-bearing ⇒ 判非空 ⇒ 存進一列 sanitize 後為空的鬼列。
      expect(stored("body_html")).to be_nil
    end
  end

  describe "CsvImport 走同一套判準（第二條寫入路徑）" do
    def import!(value, field: "body_html", locale: "ja")
      gid = "gid://chilllove/Product/#{product.id}"
      csv = <<~CSV
        resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
        PRODUCT,#{gid},#{field},#{locale},,untranslated,Rose,"#{value.gsub('"', '""')}",#{Translation.digest_for('<p>Rose</p>')}
      CSV
      Translations::CsvImport.call(shop:, csv_text: csv, dry_run: false, overwrite_existing: true)
    end

    it "🔴 語義空 HTML 經 CSV 也判空（先前只做 strip.empty? ⇒ 會寫進鬼列）" do
      outcome = import!("<p>&#160;</p>")

      expect(outcome.skipped).to eq(1)
      expect(outcome.created).to eq(0)
      expect(stored("body_html")).to be_nil
    end

    it "🔴 CSV 進來的 body_html 一樣 sanitize" do
      import!(P7_XSS_PAYLOAD)

      value = stored("body_html").value
      expect(value).not_to include("<script>")
      expect(value).not_to include("onerror")
      expect(value).to eq(Catalog::SaveProduct.sanitize_description_for(P7_XSS_PAYLOAD))
    end

    it "🔴 CSV 匯入會重算 translation_status（先前完全不算 ⇒ 後台進度與 stamp 都不動）" do
      import!("<p>薔薇</p>")

      ActsAsTenant.with_tenant(shop) do
        status = TranslationStatus.find_by(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "ja")
        expect(status).to be_present, "CsvImport 沒有重算 translation_status"
        expect(status.translated_fields).to eq(1)
        expect(status.required_fields).to eq(2)
      end
    end

    it "__CLEAR__ 在 sanitize 之前判（控制 token 不經 HTML sanitizer），且清空後重算進度" do
      import!("<p>薔薇</p>")
      outcome = import!("__CLEAR__")

      expect(outcome.cleared).to eq(1)
      expect(stored("body_html")).to be_nil
      ActsAsTenant.with_tenant(shop) do
        expect(TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id,
                                          locale_tag: "ja").translated_fields).to eq(0)
      end
    end

    it "dry_run 不寫 translation_status（預覽不得有副作用）" do
      gid = "gid://chilllove/Product/#{product.id}"
      csv = <<~CSV
        resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
        PRODUCT,#{gid},title,ja,,untranslated,Rose,ローズ,#{Translation.digest_for('Rose')}
      CSV
      Translations::CsvImport.call(shop:, csv_text: csv, dry_run: true)

      ActsAsTenant.with_tenant(shop) { expect(TranslationStatus.count).to eq(0) }
    end
  end
end
