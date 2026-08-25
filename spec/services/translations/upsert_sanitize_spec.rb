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

    it "🔴 尺寸前置閘在 sanitize **之前**：超限的 raw 直接 TOO_LONG，Loofah 一次都不跑（審查 S4）" do
      # 🔴 2026-08-25 行為反轉（撤回首版「先 sanitize 再量」）：Loofah 對無上界輸入是
      #   超線性 CPU（實測 5MB≈160s），先量 raw 把 parse 的輸入限制在欄位上限內。
      #   代價＝「raw 超限但 sanitize 後會縮到限內」者改拒收——已裁定接受。
      payload = %(<p style="#{'a' * 200}">ok</p>)
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(100)
      expect(Catalog::SaveProduct).not_to receive(:sanitize_description_for)

      result = upsert!("body_html", payload)

      expect(result.user_errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ])
      expect(stored("body_html")).to be_nil
    end

    it "sanitize 可能放大輸出（實體跳脫）⇒ 落庫值仍要量第二次" do
      # `&` 會被序列化成 `&amp;`（5 bytes）：raw 剛好在限內、sanitize 後超限 ⇒ TOO_LONG。
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(30)
      raw = "<p>#{'&' * 6}</p>"   # raw 13 bytes；sanitize 後 <p>&amp;×6</p> = 37 bytes
      expect(raw.bytesize).to be <= 30

      result = upsert!("body_html", raw)

      expect(result.user_errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ])
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

    it "🔴 sanitize 把非空內容毀成空 ⇒ userError INVALID、既有列**不動**（審查 S2，撤回首版的靜默刪列）" do
      # 首版讓 <video> 走「判空＝刪列」——商家貼了個影片內嵌，譯文就無聲消失。
      # 現在：raw 非空而 sanitize 後空 ⇒ 顯式報錯；只有 raw 本來就空才刪列。
      upsert!("body_html", "<p>real</p>")

      result = upsert!("body_html", "<video src=x></video>")

      expect(result.user_errors.map { |e| e[:code] }).to eq([ "INVALID" ])
      expect(stored("body_html").value).to eq("<p>real</p>")
    end

    it "🔴 深巢狀懸崖（libxml2 深度 255）同樣走 userError，不再靜默毀資料（審查 S2）" do
      # 🔴 必須用 `div` 不能用 `p`：HTML4 的 `<p>` 會被 parser 自動閉合，300 個 `<p>`
      #   是 300 個兄弟節點而不是 300 層巢狀，根本碰不到深度限制（實測 nest=400 仍保留
      #   文字）。`div` 才真的疊層——實測懸崖在 **256**：255 層 sanitize 後仍留 9 bytes、
      #   256 層起輸出為 0 bytes（2026-08-25，本機 `rails runner -e test`）。
      deep = ("<div>" * 300) + "IMPORTANT" + ("</div>" * 300)
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(10_000)

      result = upsert!("body_html", deep)

      expect(result.user_errors.map { |e| e[:code] }).to eq([ "INVALID" ]),
        "深巢狀的真內容被 sanitize 毀掉時必須報錯，不得靜默刪列或存空值"
      expect(stored("body_html")).to be_nil
    end

    it "raw 本來就空（RTE 初始值）⇒ 照舊刪列（不報錯——那是商家清空的合法表達）" do
      upsert!("body_html", "<p>real</p>")

      result = upsert!("body_html", "<p><br></p>")

      expect(result.user_errors).to eq([])
      expect(stored("body_html")).to be_nil
    end

    it "🔴 A2：只改譯文文字時 translation_status.updated_at 也要推進（67 §G.3 stamp 載體）" do
      upsert!("body_html", "<p>第一版</p>")
      status = ActsAsTenant.with_tenant(shop) do
        TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "ja")
      end
      before_stamp = status.updated_at

      travel(2.seconds) do
        upsert!("body_html", "<p>第二版（計數欄一個都不變）</p>")
      end

      expect(status.reload.updated_at).to be > before_stamp,
        "計數欄沒變 ⇒ save! 不發 UPDATE ⇒ stamp 停住——touch 防線失效（審查 A2）"
    end

    it "沒動到的語言的 status **不**被 touch（無條件 touch 會把別語言的快取白白失效）" do
      upsert!("title", "ローズ", locale: "ja")
      upsert!("title", "Rose FR", locale: "fr")
      fr_stamp = ActsAsTenant.with_tenant(shop) do
        TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "fr").updated_at
      end

      travel(2.seconds) { upsert!("title", "ローズ改", locale: "ja") }

      current = ActsAsTenant.with_tenant(shop) do
        TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "fr").updated_at
      end
      expect(current).to eq(fr_stamp)
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

    it "🔴 A4/C1：一列拋例外不得毀掉整份檔案（逐行 rescue，Outcome 恆回傳）" do
      gid = "gid://chilllove/Product/#{product.id}"
      digest = Translation.digest_for("<p>Rose</p>")
      csv = <<~CSV
        resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
        PRODUCT,#{gid},title,ja,,untranslated,Rose,行1,#{digest}
        PRODUCT,#{gid},body_html,ja,,untranslated,Rose,<p>行2</p>,#{digest}
        PRODUCT,#{gid},title,fr,,untranslated,Rose,行3,#{digest}
      CSV
      # 讓第二列在寫入時炸（模擬併發撞唯一鍵那類 DB 例外）。
      call_count = 0
      allow(Translation).to receive(:find_or_initialize_by).and_wrap_original do |orig, **kw|
        call_count += 1
        raise ActiveRecord::RecordNotUnique, "boom" if kw[:field_key] == "body_html"

        orig.call(**kw)
      end

      outcome = Translations::CsvImport.call(shop:, csv_text: csv, dry_run: false, overwrite_existing: true)

      expect(outcome).not_to be_nil, "例外逸出 ⇒ 整份檔案沒有報告（首版行為）"
      expect(outcome.errors.map { |e| e[:code] }).to eq([ "ERROR" ])
      expect(outcome.errors.first[:line]).to eq(3)
      ActsAsTenant.with_tenant(shop) do
        # 第 1、3 列照樣寫入，而且**進度有重算**（首版在例外後整個 recompute 迴圈被跳過）。
        expect(Translation.where(resource_id: product.id).pluck(:locale_tag, :field_key))
          .to contain_exactly([ "ja", "title" ], [ "fr", "title" ])
        expect(TranslationStatus.where(resource_id: product.id).pluck(:locale_tag))
          .to contain_exactly("ja", "fr")
      end
    end

    it "🔴 A6/S3：CSV 也要量長度（先前完全沒有 ⇒ 能寫進 GraphQL 拒收的超長值）" do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :title_max_chars).and_return(10)

      outcome = import!("這是一個明顯超過十個字元的標題", field: "title")

      expect(outcome.errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ])
      expect(stored("title")).to be_nil
    end

    it "🔴 S2：CSV 的毀內容形態也走行級錯誤，不靜默 skip" do
      outcome = import!("<video src=x></video>")

      expect(outcome.errors.map { |e| e[:code] }).to eq([ "INVALID" ])
      expect(outcome.skipped).to eq(0)
      expect(stored("body_html")).to be_nil
    end

    it "🔴 A4：超出 BIGINT 的 resource_gid 在 validate 就擋成行級 INVALID" do
      csv = <<~CSV
        resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
        PRODUCT,gid://chilllove/Product/99999999999999999999,title,ja,,untranslated,Rose,x,#{Translation.digest_for('Rose')}
      CSV
      outcome = Translations::CsvImport.call(shop:, csv_text: csv, dry_run: false)

      expect(outcome.errors.map { |e| e[:code] }).to eq([ "INVALID" ])
    end

    it "🔴 F1：CSV 的 body_html 也要量 sanitize **之後**的值（實體跳脫會放大輸出）" do
      allow(Limits).to receive(:fetch).and_call_original
      allow(Limits).to receive(:fetch).with(:product, :description_max_bytes).and_return(30)
      raw = "<p>#{'&' * 6}</p>"   # raw 13 bytes 在限內；sanitize 後 &amp;×6 ⇒ 37 bytes 超限
      expect(raw.bytesize).to be <= 30

      outcome = import!(raw)

      expect(outcome.errors.map { |e| e[:code] }).to eq([ "TOO_LONG" ]),
        "首版只量 raw ⇒ CSV 落庫一個 GraphQL 拒收、連 CSV 自己都無法再匯入的值"
      expect(stored("body_html")).to be_nil
    end

    it "🔴 F5：sanitize 之後**變成** __CLEAR__ 的值拒收，不得清掉既有譯文" do
      import!("<p>大切な説明</p>")

      outcome = Translations::CsvImport.call(
        shop:, dry_run: false, overwrite_existing: false,
        csv_text: <<~CSV
          resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
          PRODUCT,gid://chilllove/Product/#{product.id},body_html,ja,,untranslated,Rose,<div>__CLEAR__</div>,#{Translation.digest_for('<p>Rose</p>')}
        CSV
      )

      expect(outcome.errors.map { |e| e[:code] }).to eq([ "INVALID" ])
      expect(outcome.cleared).to eq(0)
      expect(stored("body_html").value).to eq("<p>大切な説明</p>"),
        "首版：div 被白名單剝掉後恰剩 token ⇒ 走清空分支刪列，還繞過 overwrite:false"
    end

    it "🔴 F2：寫入失敗的列只計 skipped＋error，不得同時計 created／cleared" do
      gid = "gid://chilllove/Product/#{product.id}"
      csv = <<~CSV
        resource_type,resource_gid,field_key,locale,market_handle,status,source_text,translated_text,source_digest
        PRODUCT,#{gid},title,ja,,untranslated,Rose,ローズ,#{Translation.digest_for('Rose')}
      CSV
      allow(Translation).to receive(:find_or_initialize_by)
        .and_raise(ActiveRecord::RecordNotUnique, "boom")

      outcome = Translations::CsvImport.call(shop:, csv_text: csv, dry_run: false)

      expect(outcome.created).to eq(0), "報告宣稱 created=1 但 DB 裡什麼都沒有（首版行為）"
      expect(outcome.skipped).to eq(1)
      expect(outcome.errors.map { |e| e[:code] }).to eq([ "ERROR" ])
      expect(stored("title")).to be_nil
    end

    it "🔴 F3：overwrite 重匯**同一份**檔案 ⇒ 無列變更 ⇒ stamp 不得推進（與 GraphQL 同行為）" do
      import!("<p>薔薇</p>")
      status = ActsAsTenant.with_tenant(shop) do
        TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "ja")
      end
      stamp = status.updated_at

      travel(2.seconds) { import!("<p>薔薇</p>") }   # 一模一樣的內容，overwrite: true

      expect(status.reload.updated_at).to eq(stamp),
        "首版無條件 touch ⇒ 重匯同一份檔案把整個覆蓋範圍的快取白白全失效"
    end

    it "F3 反向：overwrite 重匯**不同**內容 ⇒ stamp 要推進" do
      import!("<p>薔薇</p>")
      status = ActsAsTenant.with_tenant(shop) do
        TranslationStatus.find_by!(resource_type: "PRODUCT", resource_id: product.id, locale_tag: "ja")
      end
      stamp = status.updated_at

      travel(2.seconds) { import!("<p>薔薇（改訂）</p>") }

      expect(status.reload.updated_at).to be > stamp
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
