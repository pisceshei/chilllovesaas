# frozen_string_literal: true

module Translations
  # 「這個譯文值等於沒有翻譯」的**唯一**判準（docs/specs/67 §C.4(b)）。
  #
  # ①這是什麼：讀寫共用的純函式。`Upsert`（GraphQL 寫入）、`CsvImport`（匯入寫入）、
  #   `Resolve`（前台讀取）、`Audit`（稽核）四個消費者呼叫**同一支**。
  #
  # ②具體功能（完整值域）：`kind:` 兩值。
  #   - `:text` —— 標題／SEO 欄。只剝除不可見字元後判空。
  #     🔴 純文字欄裡的 `<p></p>` 是**真內容**（帶角括號的標題），不判空。
  #   - `:html` —— 富文本（`body_html`）。另外承認「語義空 HTML」：
  #     `<p></p>`／`<p><br></p>`／`<p>&nbsp;</p>`／`<p class="x"></p>`／`<div><p></p></div>`
  #     ／`<ul><li></li></ul>` 全部判空。
  #   不可見字元集＝`[[:space:]]`（含 U+3000 全形空白、U+00A0）＋`\p{Cf}`（含 U+200B ZWSP、
  #   U+FEFF BOM、U+200E LRM）＋U+0000。
  #
  # ③怎麼做到 / 為什麼是這個 parser：
  #   🔴 **HTML 走 `Loofah.fragment`，不是自己挑一個 parser**——理由不是偏好，是**同源**：
  #   `Catalog::SaveProduct#sanitize_description` 已經用 `Loofah.fragment` 做白名單 sanitize
  #   （複驗＝`grep -n "Loofah.fragment" app/services/catalog/save_product.rb`）。
  #   用同一支意味著「sanitize 看得到的元素」與「判空看得到的元素」**構造上一致**，
  #   不會出現「sanitizer 認為有 img、判空器認為沒有」這種只在某些輸入上發作的漂移。
  #   實測身分：`Loofah.fragment("<p>x</p>").class` ⇒ `Loofah::HTML4::DocumentFragment`
  #   （2026-08-25 於本機 `bundle exec ruby` 實跑）。
  #
  #   🔴 **HTML4 這個選擇本身有代價不對稱的證據，不是隨 Loofah 湊合**（2026-08-25 實測）：
  #   截斷輸入 `"<p><img src=x"`（RTE 崩潰或欄位截斷會產生）
  #     - `Loofah.fragment(...)`（HTML4）⇒ `"<p><img src=\"x\"></p>"`，`css("img").any? == true` ⇒ 判**非空**
  #     - `Nokogiri::HTML5.fragment(...)`  ⇒ `"<p></p>"`，`css("img").any? == false` ⇒ 判**空**
  #   判空＝**刪掉商家的譯文**（`Upsert` 對空值的動作是 `delete_all`），判非空最多是多留一列。
  #   ⇒ 錯誤代價不對稱 ⇒ 選在假陰性側。HTML5 在這裡會靜默毀資料。
  #
  #   🔴 **判空必須在 sanitize 之後跑**（`i18n.blank_value.runs_after_sanitize`）。
  #   反例：`<video src=x></video>` 送進來——sanitize 前 `video` 是承載內容的元素（判非空），
  #   sanitize 後它整個被白名單移除變成 `""`（真的什麼都不會顯示）。先判空就會存進一列
  #   「後台顯示已翻譯、前台是空白」的鬼列。`Upsert`／`CsvImport` 因此都先 sanitize 再判空。
  #
  #   🔴 **單一實作＋讀取端的尺寸上限 fast-path**（2026-08-25 二次修正，撤回首版裁定）：
  #   首版以「HTML 判準 ~85µs、50 列列表頁 ~4ms」為由否決研究建議的讀取端快篩——
  #   **那個量測是錯的**（對抗審查 C5 抓到，我方複測確認）：實測 17KB `body_html`
  #   一次判準 ≈1987µs、50 列全 parse ≈95ms（本機；審查方較慢的機器量到 14ms/700ms）。
  #   複驗＝對 ~17KB 中文段落跑 `Loofah.fragment` 判準 200 次取均值。
  #   ⇒ 修正案：**實作仍然只有這一份**，但讀取端可傳 `skip_parse_above:`（bytes）——
  #   `kind: :html` 且 bytesize 超過閾值時**不 parse、直接判非空**。理由：
  #   語義空 HTML 的形態（`<p>&nbsp;</p>`／`<p class="x"></p>`／空清單）結構上都是
  #   幾十 bytes 的小字串；大字串誤判成非空落在**假陰性側**（不刪資料、頂多多顯示），
  #   與本模組的代價不對稱原則同向。寫入端與稽核**永遠傳 nil**（完整判準）。
  #
  # ④跨功能影響：
  #   - 寫入端判空 ⇒ `Upsert` 刪列、`CsvImport` skip；**這是不可逆動作**，改判準前先讀上面的
  #     代價不對稱那段。
  #   - 讀取端判空 ⇒ `Resolve` 視同「沒有這個譯文」，繼續往鏈的下一階走。
  #   - 後台進度（`translation_status`）的分子是「有列」，不是「值非空」⇒ 兩者靠寫入端判空
  #     保持一致；若哪天允許存空值，進度數字與前台呈現會立刻變成兩個真相（鐵律 7）。
  #   - 稽核 `Translations::Audit` 用它掃出**立本規則之前**就落庫的空值列。
  module BlankValue
    # 即使不含任何文字也會佔版面／傳達內容的元素。
    #
    # 🔴 這**不是** void elements 清單：`area`／`base`／`col`／`link`／`meta`／`track`／`wbr`
    #    是 void 但不可見。判準是「使用者看不看得到東西」。組成＝
    #    WHATWG「Embedded content」分類的**恰十個元素**（audio canvas embed iframe img
    #    math object picture svg video；https://html.spec.whatwg.org/multipage/dom.html，
    #    2026-08-25）＋六個 embedded 之外仍然可見的加項：`hr`、`table`、
    #    表單四控件（input／select／textarea／button）。
    # 🔴 `br` **不在**清單裡——`<p><br></p>` 正是 RTE 的初始值，是本模組要抓的主要形態。
    # 🔴 `source` 也**不在**（2026-08-25 依對抗審查 D10 修正，首版誤列）：它是 void 且
    #    單獨渲染無物，只在 `picture`／`video`／`audio` 內有意義——而那三個父元素本身
    #    已在清單內，列它既違反判準又讓「WHATWG 推導」的宣稱失真。
    CONTENT_BEARING = %w[
      img video audio iframe embed object canvas svg math picture
      hr table input select textarea button
    ].freeze

    CONTENT_BEARING_SELECTOR = CONTENT_BEARING.join(",")

    # 空白（含全形 U+3000、NBSP U+00A0）＋Unicode Format 類（ZWSP U+200B／BOM U+FEFF／
    # LRM U+200E／RLM U+200F）＋NUL U+0000。
    # 🔴 一律用跳脫序列寫，不放字面不可見字元——字面 NUL 會讓 git 把整個檔案當二進位
    #    （本包寫檔時實際踩到一次，第 29 包也踩過同一個坑）。
    INVISIBLE = /[[:space:]\p{Cf}\u0000]/

    module_function

    # @param value [String, nil]
    # @param kind [Symbol] `:text` 或 `:html`（由 `Translations::Fields.kind` 決定）
    # @param skip_parse_above [Integer, nil] 讀取端 fast-path（見檔頭③）：`:html` 且
    #   bytesize 超過此值 ⇒ 不 parse、直接判非空。🔴 **寫入端與稽核一律傳 nil**——
    #   刪列／skip 是不可逆動作，必須跑完整判準；只有「多顯示一次」是可以便宜的。
    # @return [Boolean] true＝視同「沒有翻譯」，呼叫端據此刪列或往鏈的下一階走
    def blank?(value, kind: :text, skip_parse_above: nil)
      text = value.to_s
      return true if invisible_only?(text)
      return false unless kind == :html
      return false if skip_parse_above && text.bytesize > skip_parse_above

      fragment = Loofah.fragment(text)
      return false if fragment.css(CONTENT_BEARING_SELECTOR).any?

      # `fragment.text` 已由 parser 解實體（`&nbsp;`／`&#160;`／`&#8203;` 都變成真字元），
      # 所以這裡不需要——也**不得**——自己寫一份實體表（那就是漂移的第二個入口）。
      invisible_only?(fragment.text)
    end

    def invisible_only?(text)
      text.gsub(INVISIBLE, "").empty?
    end

    # 「這段原始輸入裡有沒有人看得到的文字或內容元素」——**不經 parser** 的判斷。
    #
    # 🔴 為什麼不能用 `blank?` 來回答這件事（2026-08-25 實測發現，本包自己踩到）：
    #   呼叫端要偵測的是「sanitize 把內容毀掉了」，而毀掉內容的機制之一正是
    #   **parser 自身的深度上限**（libxml2 在巢狀 256 層起丟棄子樹：實測
    #   `("<div>"*300) + "IMPORTANT"` sanitize 後為 0 bytes）。用 `blank?` 判 raw
    #   會走**同一個 parser**、撞**同一個懸崖**，於是回報「raw 也是空的」——
    #   偵測器與被偵測的失效共用同一個盲點，等於沒有偵測。
    #   ⇒ 這裡用正則剝標籤（parser-independent），只回答「剝掉標籤後還有沒有可見字元，
    #   或出現過 content-bearing 標籤名」。它不精確（不解實體、不懂巢狀），
    #   但它的**失效模式與 parser 無關**，這正是它的用途。
    #
    # @return [Boolean] true＝原始輸入確實帶有內容（因此 sanitize 後變空＝內容被毀）
    def text_bearing?(raw)
      text = raw.to_s
      stripped = drop_invisible_refs(text.gsub(/<[^>]*>/m, ""))
      return true unless invisible_only?(stripped)

      text.scan(/<\s*([a-zA-Z][a-zA-Z0-9]*)/).any? { |(tag)| CONTENT_BEARING.include?(tag.downcase) }
    end

    # 剝掉「解出來是不可見字元」的字元參照。
    # 🔴 這裡**不能**呼叫 parser（那就繞回 `text_bearing?` 要避開的懸崖），也不能用
    #   `CGI.unescapeHTML`——實測它在本專案的 Ruby 只解 5 個基本具名參照，數值參照原樣留著
    #   （`CGI.unescapeHTML("&#160;") == "&#160;"`），於是 `<p>&#160;</p>` 會被誤判成有內容。
    # ⚠️ 已知不精確：只處理數值參照（🔴 `&#x`／`&#X` 兩種大小寫都要收——HTML 允許大寫 X，
    #   libxml2 兩種都解；首版漏了大寫，於是 `<p>&#X200B;</p>` 被當成有內容、商家清空欄位
    #   會整個 mutation 被拒——審查 F4）與**不可見的**具名參照白名單；其餘參照一律當
    #   可見內容（落在「報錯而不是刪列」那一側，與本模組的代價不對稱同向）。
    INVISIBLE_NAMED_REFS = %w[nbsp ensp emsp thinsp hairsp zwnj zwj lrm rlm feff].freeze

    def drop_invisible_refs(text)
      text
        .gsub(/&#[xX]([0-9a-fA-F]+);|&#(\d+);/) do
          code = ::Regexp.last_match(1) ? ::Regexp.last_match(1).to_i(16) : ::Regexp.last_match(2).to_i
          char = begin
            code.chr(Encoding::UTF_8)
          rescue RangeError
            nil
          end
          char && invisible_only?(char) ? "" : ::Regexp.last_match(0)
        end
        .gsub(/&([a-zA-Z]+);/) { INVISIBLE_NAMED_REFS.include?(::Regexp.last_match(1).downcase) ? "" : ::Regexp.last_match(0) }
    end
  end
end
