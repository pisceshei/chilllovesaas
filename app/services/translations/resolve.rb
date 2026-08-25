# frozen_string_literal: true

module Translations
  # 一次解析的結果。
  #
  # @!attribute value [String, nil] 要輸出的字串；`source == :omitted` 時為 nil
  # @!attribute locale [String, nil] 這個字串**實際**是什麼語言（第 34 包的 `lang` 屬性值）
  # @!attribute depth [Integer] 離請求語言幾步（以**完整**截尾鏈的索引計，與 scope 無關
  #   ——2026-08-25 依審查 A3 修正，首版用過濾後索引，「請求語言不在 scope」時會塌回 0）。
  #   0＝請求語言直接命中（或請求語言就是來源語言）；1..n＝落在鏈的第 n 階；
  #   鏈長＝落到 base row。遙測門檻 `i18n.resolve.fallback_telemetry_min_depth` 比對這個值。
  # @!attribute source [Symbol] `:translation`／`:base`／`:omitted`
  Resolved = Data.define(:value, :locale, :depth, :source) do
    # 🔴 第 34 包判斷「要不要加 lang 屬性」用這個，**不是**比對字串是否等於原文
    #    （譯文與原文碰巧相同是合法的，例如品牌名）。
    def fallback? = depth.positive?

    # 呼叫端據此決定「整個欄位不輸出」（67 §B.1 optional 的行為）。
    def omitted? = source == :omitted
  end

  # 前台內容譯文解析器（docs/specs/67 §C.4；第 7 包）。
  #
  # ①這是什麼：給定 (資源, 欄位, 請求語言)，回答「前台該顯示哪個字串、它其實是什麼語言」。
  #   §C.4 的四步演算法就是這一支：
  #   ```
  #   1. translations[L]                 # 請求語言
  #   2. for A in fallback_chain(L)      # BCP-47 截尾鏈
  #        translations[A]
  #   3. base row                        # ＝來源語言原文
  #   4. 仍為空 ⇒ 依 §B.1 欄位類別：required→回 3 的值；optional→**整個欄位不輸出**
  #   ```
  #
  # ②具體功能（完整值域與規則）：
  #   - `scope:` 兩值。`:published`（預設，前台）只在 `shop_locales.published` 的語言裡解析；
  #     `:enabled` 給預覽連結用（67：「未發布＝只能預覽連結」）。
  #     🔴 **不在 scope 內的候選一律跳過（保留 depth 索引），不是報錯**——請求未發布語言的
  #     URL 該在路由層 404（`i18n.storefront.unpublished_locale_status: 404`），不是在這裡
  #     才發現；但在路由層尚未落地前，這裡落到 base 仍如實回報 `fallback?=true` 與遙測。
  #   - 🔴 **`resolve()` 不收 market 參數**（67 §C.2 沿革／驗收 I18N-6）。市場影響「曝光」與
  #     「錢」，不影響「內容」；`translations.market_id` 已刪欄。想加回來的人先讀 §C.2。
  #   - 空值（含語義空 HTML）視同沒有譯文 ⇒ 繼續往下一階（`Translations::BlankValue`）。
  #     🔴 這一條讓**立本規則之前**已落庫的空值列不會把使用者卡在空白畫面上。
  #
  # ③怎麼做到 —— 三個非顯而易見的點：
  #   🔴 **(a) 請求語言就是來源語言時，depth 必須是 0**。來源語言的文字在 base row，
  #      正規寫入路徑不會產生來源語言的譯文列（`Upsert` 以 code=`INVALID`、i18n key
  #      `errors.translation.source_locale_not_translatable` 擋；繞道寫入的歷史列由
  #      `Translations::Audit` 的 `source_locale_row` 規則登記）。若照「查不到 ⇒ 一路走到 base ⇒ depth=n+1」算，**每一次正常的來源語言渲染
  #      都會發一筆 fallback_hit** ——遙測會被自己的正常路徑淹沒，§E.4 的缺漏可視化就廢了。
  #      實作上不需要特例分支：候選清單裡遇到 `== source_locale` 就直接回 base，
  #      而來源語言的候選索引恰好是 0。
  #   🔴 **(b) 鏈的中間階也可能是來源語言**（來源 `en`、請求 `en-GB`）：同樣直接回 base，
  #      不去 `translations` 查一個按定義不存在的列。
  #   🔴 **(c) 批載查詢刻意不把 `field_key` 放進 IN 清單**。MySQL 官方：多個 IN 清單的
  #      等值 range 數是**各清單長度的乘積**；`eq_range_index_dive_limit` 預設 200，
  #      達到就從 index dive 換成統計估算 ⇒ 同一支查詢的執行計畫無預警改變。
  #      50 資源 × 3 階 × 4 欄 = 600 > 200；拿掉 field 維度後是 50 × 3 = 150。
  #      欄位在 Ruby 端過濾，每列最多 4 欄，浪費極小。
  #      出處：https://dev.mysql.com/doc/refman/8.4/en/range-optimization.html（2026-08-25）
  #      ＋ https://dev.mysql.com/blog-archive/you-asked-for-it-new-default-for-eq_range_index_dive_limit/（2026-08-25）
  #      ✅ **P7-L6 已取得**（2026-08-25 於 bt3 正式環境實查）：`@@eq_range_index_dive_limit
  #      = 200`（MySQL 8.4.10），與推導所用的官方預設值相同。
  #      複驗＝`SELECT @@eq_range_index_dive_limit;`。
  #   🔴 **(d) 按 `resource_type` 分組發查詢，不用 row constructor**
  #      （`(resource_type, resource_id) IN ((..),(..))`）。MySQL 對 row constructor 走 range
  #      有四個條件，其中「右側必須多於一個 row constructor」在單筆時不成立而退化成全掃。
  #      `Translation::RESOURCE_TYPES` 封閉在兩值 ⇒ 每次 batch 最多 2 條 SQL。
  #      🔴 這是對 67 §F.3(c) 字面「**一次** IN」的刻意偏離，理由如上。
  #   - 索引：`uq_translations_resource_locale_field (shop_id, resource_type, resource_id,
  #     locale_tag, field_key)` 的 leftmost prefix 完全吻合本查詢的
  #     `shop_id(=) → resource_type(=) → resource_id(IN) → locale_tag(IN)`。
  #     🔴 改索引欄序會讓整個批載退回掃描。
  #
  # ④跨功能影響（預先對接）：
  #   - **第 30 包**（Liquid 生產化）：`ProductDrop` 建構時呼叫 `.batch` 做 preload，
  #     key 是 `[resource_type, resource_id]` 二元組。**不得**在 drop 的每個 method 裡呼叫
  #     `.field`（那就是 N+1）。本包不碰 `poc/`。
  #   - **第 33 包**（渲染管線／cache stamp 自檢）：`.batch` 回傳的 `touched_sources`
  #     要進 `cache_stamp` 自檢。🔴 本包**只回傳、不呼叫**——接收端
  #     （`catalog_flow.cache_stamp_selfcheck_envs`）在 `app/` 尚無實作。
  #   - **第 34 包**（三層字串／lang／Vary）：`Resolved#fallback?` 決定要不要加 `lang`；
  #     `lang` 的值是 `Resolved#locale`（可能是 `zh-Hant` 而不是請求的 `zh-Hant-HK`）。
  #   - **第 3 包**（cache stamp）：`translations` 目前**不在** `catalog_flow.cache_stamp_sources`，
  #     因為對應欄位還沒立（見 `docs/dev/m2-translations-resolve.md`「交給下游的需求」U21/U22）。
  #   - 🔴 **後台 GraphQL 禁止接本模組**：`Types::ProductType#translations` 與
  #     `Types::CollectionType#translations` 是對 `locale_tag` **精確比對**，這是刻意的。
  #     admin SPA 把回來的列直接當表單值（`ProductDetailPage.tsx` 的 `toTranslationMap`），
  #     若吃到 fallback 值，商家一按儲存就把來源語言原文寫成該語言的「真譯文」，
  #     從此 outdated 與進度數字全部失真。反向 spec 見
  #     `spec/services/translations/resolve_spec.rb`「後台 GraphQL 不得產生鏈」。
  class Resolve
    # 🔴 fail-closed 的類別→resource_type 對照：不用 `class.name.upcase` 那種推導，
    #   因為未知型別會被推導成一個看起來合理但查不到任何列的字串（靜默回全部 base）。
    #   新增可翻資源類型時同步 `Translation::RESOURCE_TYPES` 與這裡。
    RESOURCE_TYPE_BY_CLASS = { "Product" => "PRODUCT", "Collection" => "COLLECTION" }.freeze

    class << self
      # 批次解析（**這是主要 API**）。
      #
      # @param shop [Shop]
      # @param resources [Array<Product, Collection>] 已載入的 base row（base 值從這裡取，不另查）
      # @param fields [Array<String>] 要解析的欄位（`Translations::Fields::ALL` 的子集）
      # @param locale [String] 請求語言
      # @param scope [Symbol] `:published`（預設）／`:enabled`
      # @return [Hash{Array(String,Integer) => Hash{String => Resolved}}]
      #   key＝`[resource_type, resource_id]`，value＝`{field_key => Resolved}`
      # @raise [ArgumentError] resources 超過 `i18n.resolve.max_resources_per_batch`
      # @note 副作用：每個 distinct resource_type 一條 SELECT；`depth >= 1` 時發
      #   `i18n.fallback_hit` notification（無訂閱者＝零成本）。
      def batch(shop:, resources:, fields: Fields::ALL, locale:, scope: :published)
        records = Array(resources)
        max = Limits.fetch(:i18n, :resolve, :max_resources_per_batch)
        if records.length > max
          raise ArgumentError, "一次最多解析 #{max} 筆資源（收到 #{records.length}）；" \
                               "超過會讓 locale_tag × resource_id 的等值 range 數逼近 eq_range_index_dive_limit"
        end
        return {} if records.empty?

        # 🔴 呼叫端傳錯店的物件時要炸，不能靜默回別店的 base 文字（審查 A10）：
        #   查詢層全部帶 shop_id（隔離無破洞），但 base 值是直接從**傳進來的物件**讀的
        #   ——那一步只有這個斷言在守。先驗型別（未知類別在這裡就炸，而不是對一個
        #   沒有 shop_id 的物件 NoMethodError），再驗歸屬。
        records.each do |record|
          resource_type_for(record)
          next if record.shop_id == shop.id

          raise ArgumentError, "resources 含不屬於本店的資源：" \
                               "#{record.class.name}##{record.id}（shop_id=#{record.shop_id}≠#{shop.id}）"
        end
        # 🔴 內層 hash 的 key 統一成 String——首版 `field()` 用 `field.to_s` fetch、
        #   內層卻用原始物件當 key，Symbol 呼叫端會 KeyError（審查 A7）。
        field_keys = Array(fields).map(&:to_s)

        # 🔴 自己開租戶脈絡（形態同 `Locales::Registry`）：呼叫端是 Liquid drop 與 rake 任務，
        #   不保證跑在 `ActsAsTenant.current_tenant` 已設定的請求脈絡裡；沒有這一層，
        #   `Translation.where` 會拋 `NoTenantSet`。`shop:` 是顯式參數 ⇒ 這裡是**唯一**
        #   知道租戶是誰的地方，不該把設租戶的責任推給每一個呼叫端。
        ActsAsTenant.with_tenant(shop) do
          source_locale = Locales::Registry.source_tag(shop)
          allowed = allowed_tags(shop, scope)
          # 🔴 走訪清單是**未過濾**的完整截尾鏈；scope 在走訪時「跳過」而不是事先「移除」
          #   （2026-08-25 依審查 A3 修正）。首版用 select 先移除，於是「請求語言不在
          #   scope 內」時候選塌陷、`depth` 從 0 起算 ⇒ 明明落到來源語言卻回報
          #   `fallback?=false`、第 34 包不加 `lang`、遙測全盲。depth 的語義＝
          #   「離請求語言幾步」，它必須以完整鏈的索引計，與 scope 無關。
          walk = Locales::FallbackChain.candidates(locale)
          rows = load_rows(shop, records, walk & allowed, source_locale)

          records.each_with_object({}) do |record, out|
            type = resource_type_for(record)
            out[[ type, record.id ]] = field_keys.index_with do |field|
              resolve_one(shop:, record:, type:, field:, locale:,
                          walk:, allowed:, source_locale:, rows:)
            end
          end
        end
      end

      # 單一資源的便利包裝。
      #
      # 🔴 **不得在迴圈裡呼叫**——它每次都會重查 `shop_locales`（來源語言與 published 集合）。
      #   要解析多筆一律用 `.batch`。第 30 包的 preload 走 `.batch`。
      #
      # @return [Hash{String => Resolved}]
      def fields_for(shop:, resource:, fields: Fields::ALL, locale:, scope: :published)
        batch(shop:, resources: [ resource ], fields:, locale:, scope:)
          .fetch([ resource_type_for(resource), resource.id ])
      end

      # @return [Resolved]
      def field(shop:, resource:, field:, locale:, scope: :published)
        fields_for(shop:, resource:, fields: [ field ], locale:, scope:).fetch(field.to_s)
      end

      # 第 33 包的 cache stamp 自檢用：本次解析實際讀過哪些來源。
      # 🔴 只回傳，**不呼叫**任何自檢——接收端尚未存在（見檔頭④）。
      def touched_sources = [ :translations ].freeze

      private

      def resource_type_for(record)
        RESOURCE_TYPE_BY_CLASS.fetch(record.class.name) do
          raise ArgumentError, "不支援的可翻資源類型：#{record.class.name}"
        end
      end

      # scope 決定「哪些語言的譯文可以被讀」。
      # 🔴 fail-closed：未知 scope 一律 raise，不預設成比較寬的那一個。
      def allowed_tags(shop, scope)
        case scope
        when :published then Locales::Registry.published_tags(shop)
        when :enabled then Locales::Registry.enabled_tags(shop)
        else raise ArgumentError, "未知的 scope：#{scope.inspect}（只有 :published / :enabled）"
        end
      end

      # 一條 SELECT / resource_type（見檔頭③(c)(d)）。只載入 scope 內的語言——
      # 走訪時對 scope 外候選是「跳過」，但**資料庫層根本不去讀它們的列**（未發布語言的
      # 譯文保留而不可取用，兩層都要成立）。
      # @return [Hash{Array(String,Integer,String,String) => String}] 值查表
      def load_rows(shop, records, allowed_candidates, source_locale)
        lookup_tags = allowed_candidates - [ source_locale ]
        return {} if lookup_tags.empty?

        records.group_by { |record| resource_type_for(record) }.each_with_object({}) do |(type, group), out|
          Translation
            .where(shop_id: shop.id, resource_type: type,
                   resource_id: group.map(&:id), locale_tag: lookup_tags)
            .pluck(:resource_id, :locale_tag, :field_key, :value)
            .each { |id, tag, field, value| out[[ type, id, tag, field ]] = value }
        end
      end

      def resolve_one(shop:, record:, type:, field:, locale:, walk:, allowed:, source_locale:, rows:)
        kind = Fields.kind(field)

        walk.each_with_index do |tag, depth|
          # 檔頭③(a)(b)：來源語言的內容在 base row，不在 translations。
          # 🔴 這一格在 scope 檢查**之前**：來源語言是最終 fallback，即使它被
          #   `update_columns` 之類繞道改成未發布（model 驗證擋不到的形態），
          #   鏈也不得斷在半路——沒有這個順序，前台會顯示空白。
          return base_result(shop:, record:, type:, field:, locale:, depth:,
                             source_locale:, kind:) if tag == source_locale
          # scope 外＝跳過但**保留 depth 索引**（見 batch 內的修正註釋）。
          # ⚠️ **這一行目前構造上不可達**：`load_rows` 只載入 scope 內的語言，所以
          #   scope 外的候選在 `rows` 裡本來就查不到值、下一行的判空會接住它。
          #   突變驗證：刪掉它測試**不會紅**（N16）⇒ 它是縱深防禦，不是承重守衛，
          #   **不得**宣稱有測試證明它有效。留著的理由是承重的那一道在別的方法裡
          #   （`load_rows` 的 `allowed_candidates`），日後若有人為了預載而把完整
          #   `rows` 傳進來，這一行是唯一還站著的防線。
          next unless allowed.include?(tag)

          value = rows[[ type, record.id, tag, field ]]
          next if BlankValue.blank?(value, kind:, skip_parse_above: read_fast_path)

          emit(shop:, locale:, resolved: tag, type:, field:, depth:)
          return Resolved.new(value:, locale: tag, depth:, source: :translation)
        end

        base_result(shop:, record:, type:, field:, locale:, depth: walk.length,
                    source_locale:, kind:)
      end

      # 讀取端 fast-path 閾值（`i18n.blank_value.read_fast_path_max_bytes`；C5 修正）。
      # 🔴 只有 Resolve 用；寫入端與稽核走完整判準（BlankValue 檔頭③）。
      def read_fast_path
        Limits.fetch(:i18n, :blank_value, :read_fast_path_max_bytes)
      end

      def base_result(shop:, record:, type:, field:, locale:, depth:, source_locale:, kind:)
        value = Fields.base_value(record, field)

        # optional 欄位缺翻譯且原文也空 ⇒ **整個欄位不輸出**（67 §B.1；不是輸出空字串）。
        # base 的判空同樣走讀取端 fast-path（大 body ⇒ 視為有內容，落假陰性側）。
        # 🔴 omitted **不發遙測**（審查 F9）：首版把 emit 放在這個分支之前，於是每個沒有
        #   SEO 描述的商品每次渲染都發一筆 `resolved_locale: "en"`——但根本沒有任何字串
        #   被輸出，「回落到了來源語言」是假訊息。遙測的語義＝「使用者看到了 fallback
        #   內容」；什麼都沒輸出就什麼都不記。
        if Fields.missing(field) == :optional &&
           BlankValue.blank?(value, kind:, skip_parse_above: read_fast_path)
          return Resolved.new(value: nil, locale: nil, depth:, source: :omitted)
        end

        emit(shop:, locale:, resolved: source_locale, type:, field:, depth:)

        # 🔴 required 欄位即使原文也空，仍然回 base（值可能就是 ""）。
        #   來源本身沒有內容是**事實**，不是「缺翻譯」——這時候顯示空白是對的，
        #   67 §B.1 的「顯示原文優於顯示空白」講的是「有原文卻顯示空白」那種情形。
        Resolved.new(value:, locale: source_locale, depth:, source: :base)
      end

      # 🔴 遙測 payload **不得**放 `resource_id`：那是無界集合，進了 label 就是基數爆炸。
      #   Prometheus 官方：`Do not use labels to store dimensions with high cardinality
      #   (many different label values), such as user IDs, email addresses, or other
      #   unbounded sets of values.`
      #   出處：https://prometheus.io/docs/practices/naming/（2026-08-25）
      #
      # 🔴 `depth == 0` 一律不發（＝請求語言直接命中，或請求語言就是來源語言）。
      #   67 §C.4(d) 的字面是「落到步驟 3 以後」，但該句寫於 market 維度還在、步驟編號為 5 的
      #   版本（§C.2 沿革），刪欄後步驟重編為 4 而 (d) 未同步 ⇒ 「步驟 3」現在指到 base row。
      #   我方採 `depth >= 1`（＝**只要沒命中請求語言就記**），它同時涵蓋兩種讀法，
      #   且 `depth` 欄位本身就能區分「走了鏈」與「落到 base」。這是 ours 的解讀，
      #   不得寫成「照 §C.4(d) 字面實作」。
      def emit(shop:, locale:, resolved:, type:, field:, depth:)
        return if depth < Limits.fetch(:i18n, :resolve, :fallback_telemetry_min_depth)

        ActiveSupport::Notifications.instrument(
          "i18n.fallback_hit",
          shop_id: shop.id, requested_locale: locale, resolved_locale: resolved,
          resource_type: type, field_key: field, depth:
        )
      end
    end
  end
end
