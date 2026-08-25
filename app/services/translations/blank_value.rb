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
  #   🔴 **只有一份實作，讀寫都跑完整判準**（ours，2026-08-25）：研究階段曾建議讀取熱路徑
  #   只跑不可見字元快篩（~1.1µs）、完整 HTML 判準（~85µs）留給寫入端。**否決**——
  #   理由是量級不成比例：四個可翻欄位裡只有 `body_html` 是 `:html`，一張商品詳情頁
  #   ≈1 次 HTML 判準（85µs），50 筆的列表頁即使全解析 `body_html` 也只有 ~4ms；
  #   而兩套判準的代價是「讀寫對同一個值給不同答案」這種只在特定輸入發作的漂移
  #   （正是本模組存在的理由）。省 85µs 不值得買回一個 U11 型的已知限制。
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
    #    是 void 但不可見。判準是「使用者看不看得到東西」，來源＝WHATWG HTML
    #    「Embedded content」分類（https://html.spec.whatwg.org/multipage/dom.html，2026-08-25）
    #    ＋三個 embedded 之外仍然可見的加項：`hr`（水平線）、`table`（框線）、表單控件。
    # 🔴 `br` **不在**清單裡——`<p><br></p>` 正是 RTE 的初始值，是本模組要抓的主要形態。
    CONTENT_BEARING = %w[
      img video audio iframe embed object canvas svg math picture source
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
    # @return [Boolean] true＝視同「沒有翻譯」，呼叫端據此刪列或往鏈的下一階走
    def blank?(value, kind: :text)
      text = value.to_s
      return true if invisible_only?(text)
      return false unless kind == :html

      fragment = Loofah.fragment(text)
      return false if fragment.css(CONTENT_BEARING_SELECTOR).any?

      # `fragment.text` 已由 parser 解實體（`&nbsp;`／`&#160;`／`&#8203;` 都變成真字元），
      # 所以這裡不需要——也**不得**——自己寫一份實體表（那就是漂移的第二個入口）。
      invisible_only?(fragment.text)
    end

    def invisible_only?(text)
      text.gsub(INVISIBLE, "").empty?
    end
  end
end
