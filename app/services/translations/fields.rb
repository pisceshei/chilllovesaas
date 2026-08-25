# frozen_string_literal: true

module Translations
  # 可翻欄位的**單一**中繼資料表（docs/specs/67 §B.1／§B.2）。
  #
  # ①這是什麼：四個可翻欄位各自的三件事——值的形態（text/html）、缺翻譯時的行為
  #   （required/optional）、以及它在 base row 上對應哪個屬性。
  #
  # ②具體功能（完整值域）：v1 射程恰四欄（67 §B.2）。
  #
  #   | field_key        | kind  | missing  | base 屬性        | 缺翻譯時前台看到什麼 |
  #   |------------------|-------|----------|------------------|----------------------|
  #   | title            | text  | required | title            | 來源語言原文         |
  #   | body_html        | html  | required | description_html | 來源語言原文         |
  #   | meta_title       | text  | optional | seo_title        | **整個欄位不輸出**   |
  #   | meta_description | text  | optional | seo_description  | **整個欄位不輸出**   |
  #
  #   `required`／`optional` 的行為出處＝`i18n.missing_translation_behavior`
  #   （required: source_text／optional: omit_field／never: source_value）與 67 §B.1 表。
  #   🔴 **沒有第四種行為**：不得靜默輸出空字串、key 名或 nil（67 §B.1 原則 2）。
  #
  # ③怎麼做到：`PRODUCT` 與 `COLLECTION` 的 base 屬性名恰好同名（兩張表都有
  #   title／description_html／seo_title／seo_description，複驗＝
  #   `grep -n "seo_title\|description_html" db/schema.rb | grep -c .`），所以 `BASE_ATTRIBUTE`
  #   不需要按 resource_type 分岔。**新增第三種 resource_type 時先確認這個巧合仍成立**
  #   ——不成立就要把這張表改成 `{resource_type => {field => attr}}`，不要在呼叫端加分支。
  #
  # ④跨功能影響：
  #   - `Upsert#normalize` 的欄位白名單與長度上限；
  #   - `CsvImport#validate`（`Upsert::FIELDS`）與 `#source_text_for`（原本自己寫了一份
  #     `case row.field` 的對照，本包合併到這裡）；
  #   - `Resolve` 的 kind 與 missing 行為；
  #   - `CsvExport` 的欄位集合。
  #   🔴 新增可翻欄位＝改這一張表，**不是**在四個消費者各加一行。
  module Fields
    KIND = {
      "title" => :text,
      "body_html" => :html,
      "meta_title" => :text,
      "meta_description" => :text
    }.freeze

    # 🔴 這與 `Upsert::REQUIRED_FIELDS`／`OPTIONAL_FIELDS` **語義不同，只是目前值相同**：
    #    Upsert 的那兩個常數是**翻譯進度的分母**（`translation_status.required_fields`），
    #    本表是**缺翻譯時前台怎麼辦**。兩者現在一致純屬 v1 射程小。
    #    `spec/services/translations/fields_spec.rb` 有一格 tripwire 斷言兩者相等——
    #    它紅掉時要做的是**裁定哪一邊該變**，不是把常數改成一致把測試弄綠。
    MISSING = {
      "title" => :required,
      "body_html" => :required,
      "meta_title" => :optional,
      "meta_description" => :optional
    }.freeze

    BASE_ATTRIBUTE = {
      "title" => :title,
      "body_html" => :description_html,
      "meta_title" => :seo_title,
      "meta_description" => :seo_description
    }.freeze

    ALL = KIND.keys.freeze

    module_function

    # @param field [String]
    # @return [Symbol] `:text` / `:html`；未知欄位一律 `:text`（保守：不對未知值跑 HTML parser）
    def kind(field) = KIND.fetch(field.to_s, :text)

    # @param field [String]
    # @return [Symbol] `:required` / `:optional`
    def missing(field) = MISSING.fetch(field.to_s, :required)

    # @param resource [Product, Collection]
    # @param field [String]
    # @return [String] base row（＝來源語言）的原文；未知欄位回 ""
    def base_value(resource, field)
      attribute = BASE_ATTRIBUTE[field.to_s]
      return "" if attribute.nil?

      resource.public_send(attribute).to_s
    end

    # 譯文長度上限沿用**來源欄位**的上限（`i18n.per_field_limits_follow_source_field`）：
    # 另立一套（英文 255／中文 500）會讓匯出→匯入來回炸掉。
    #
    # @param field [String]
    # @return [Integer] 上限值。單位由 `measure` 決定，見下。
    # @raise [KeyError] 未知欄位。🔴 `kind`／`missing` 對未知值有安全預設可回；上限**沒有**
    #   ——靜默回某個別欄的數字（首版的 `else` 分支就是這樣）等於給新欄位一個看起來
    #   合法、實際上是別人的上限，正是「新增可翻欄位＝改這一張表」最會踩的那種陷阱。
    LIMIT_KEYS = {
      "title" => [ :product, :title_max_chars ],
      "body_html" => [ :product, :description_max_bytes ],
      "meta_title" => [ :content, :seo_title_max_chars ],
      "meta_description" => [ :content, :seo_meta_description_max_chars ]
    }.freeze

    def limit(field)
      keys = LIMIT_KEYS.fetch(field.to_s) do
        raise KeyError, "未知的可翻欄位 #{field.inspect}——上限沒有安全預設，先在 Fields 登記"
      end
      Limits.fetch(*keys)
    end

    # 🔴 **上限的單位不是同一種，量錯就等於沒有上限**：`*_max_chars` 是字元數，
    #   `description_max_bytes` 是**位元組**數，而 base 的 `SaveProduct#normalize` 用的正是
    #   `description.bytesize`（複驗＝`grep -n "description.bytesize" app/services/catalog/save_product.rb`）。
    #   本包之前譯文端一律用 `value.length` 量 ⇒ 同一個 `description_max_bytes`，
    #   base 擋在 N bytes、譯文卻放行到 N **字元**；一段中文譯文（每字 3 bytes）
    #   等於拿到三倍額度。這不是「譯文比較寬鬆」的裁定，是量錯單位。
    #   把「哪個欄位用哪個單位」收在這裡，呼叫端不必自己記。
    #
    # @param field [String]
    # @param value [String]
    # @return [Integer] 與 `limit(field)` 同單位的量值
    def measure(field, value)
      kind(field) == :html ? value.to_s.bytesize : value.to_s.length
    end
  end
end
