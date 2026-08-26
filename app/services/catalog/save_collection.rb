# frozen_string_literal: true

module Catalog
  # 商品系列的宣告式 upsert（ML-3；形態沿用 `SaveProduct`／63 §B.4：建立與更新同一支，
  # 差別只在有無 id；lockVersion 涵蓋整棵樹）。
  #
  # 🔴 **與商品共用的三件事，刻意不另寫一份**：
  #   ① 譯文寫入走同一個 `Translations::Upsert`（只換 resource_type）；
  #   ② handle 生成走同一個 `HandleGenerator`；
  #   ③ AR 例外在這裡轉譯成 userErrors，不外洩（28 §0.3）。
  # 各寫一份的代價不是重複碼，是**語義漂移**——兩邊對「空字串＝清除」的解讀遲早不同。
  class SaveCollection
    Result = Data.define(:collection, :user_errors)

    # 整棵樹的拒絕載體（譯文、成員 ID⋯⋯）：任一子部分被拒 ⇒ 整筆存檔回滾。
    class TreeRejected < StandardError
      attr_reader :user_errors

      def initialize(user_errors)
        @user_errors = user_errors
        super("collection tree rejected")
      end
    end

    GID_PATTERN = %r{\Agid://chilllove/Collection/(\d+)\z}
    PRODUCT_GID_PATTERN = %r{\Agid://chilllove/Product/(\d+)\z}

    class << self
      # @param shop [Shop]
      # @param input [Hash] title／descriptionHtml／handle／seo／translations／collectionType／sortOrder／productIds
      # @return [Result]
      def call(shop:, input:)
        errors = []
        attributes = normalize(shop, input, errors)
        return Result.new(collection: nil, user_errors: errors) if errors.any?

        input[:id].present? ? update(shop, input, attributes) : create(shop, attributes)
      end

      private

      def normalize(shop, input, errors)
        source_locale = Locales::Registry.source_tag(shop)
        title = input[:title].to_s.strip
        errors << error([ "title" ], I18n.t("errors.collection.title_blank"), "BLANK") if title.empty?
        if title.length > Limits.fetch(:product, :title_max_chars)
          errors << error([ "title" ], I18n.t("errors.collection.title_too_long"), "TOO_LONG")
        end

        # 🔴 缺席／顯式 null＝**保持現值**（宣告式家族契約，見 CollectionSetInput 檔頭；
        #   與 SaveProduct 的 description_html 同一條規則）。2026-08-26 delta 審查抓到：
        #   F3 只封了 collection_type／sort_order，**同一個 normalize 裡同根因的說明欄沒動**
        #   ⇒ 任何不帶 descriptionHtml 的部分更新把系列說明清空、userErrors 為空。
        #   商品側早有同款事故（save_product.rb 的 V29-D1 註釋：變體子頁每存一次抹掉整段
        #   商品說明），參照物是對的、只抄了一半——這正是鐵律 20.2 第 2 類的形態。
        #   🔴 判準是 `.nil?` 不是 `.blank?`：空字串＝顯式清除，必須寫得進去。
        description = if input[:description_html].nil?
                        nil
        else
                        Catalog::SaveProduct.sanitize_description_for(input[:description_html].to_s)
        end
        # 🔴 上限與商品同一個鍵（2026-08-26 收斂輪 G3）：F5 把 SaveProduct 的 nil-guard
        #   抄了過來，緊接的 TOO_BIG 檢查卻沒抄——同一份內容在 productSet 回 TOO_BIG、
        #   在 collectionSet 靜默存進去；而 translations 的譯文硬上限明文「對齊
        #   product.description_max_bytes」⇒ 超限的系列說明其 body_html 譯文永遠寫不進去。
        #   沿用 product 命名空間與本檔 title 的既定慣例一致（同方法 `product.title_max_chars`）。
        if description && description.bytesize > Limits.fetch(:product, :description_max_bytes)
          errors << error([ "descriptionHtml" ], I18n.t("errors.collection.description_too_big"), "TOO_BIG")
        end

        # 🔴 宣告式契約（審查 F3）：**缺席＝保持現值，不得補預設**——初版
        #   `input[:collection_type] || "manual"` 讓「部分更新沒帶 collectionType」把
        #   智慧系列**靜默改成手動**（sortOrder 同型：缺席被重置回 manual）。
        #   與 SaveProduct#normalize 的 status 同款語義（那邊註釋：「保持現值比靜默改
        #   draft 安全」）。預設值只在 create 補（見 create）；型別驗證只對「有帶」執行。
        collection_type = input[:collection_type]&.to_s&.downcase
        if collection_type && !Collection::TYPES.include?(collection_type)
          errors << error([ "collectionType" ], I18n.t("errors.collection.type_invalid"), "INVALID")
        end

        sort_order = input[:sort_order]&.to_s&.downcase
        if sort_order && !Collection::SORT_ORDERS.include?(sort_order)
          errors << error([ "sortOrder" ], I18n.t("errors.collection.sort_order_invalid"), "INVALID")
        end

        manual_handle = input[:handle].presence
        if manual_handle && !manual_handle.match?(/\A[a-z0-9-]+\z/)
          errors << error([ "handle" ], I18n.t("errors.collection.handle_invalid"), "INVALID")
        elsif manual_handle && manual_handle.length > Limits.fetch(:handle, :max_chars)
          errors << error([ "handle" ], I18n.t("errors.collection.handle_too_long"), "TOO_LONG")
        elsif manual_handle && Limits.fetch(:handle, :reserved).map(&:to_s).include?(manual_handle)
          # 🔴 保留字檢查商品側早就有、系列側沒有（審查 R6-4）：本包解鎖系列改名後
          #    系列可被改成 "all"／"new"／"index"，撞平台路由段。
          errors << error([ "handle" ], I18n.t("errors.collection.handle_reserved"), "INVALID")
        elsif manual_handle && Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:collection, manual_handle))
          # 舊 handle 永不回收（62 §F.3；與 SaveProduct 同判準入口）。
          errors << error([ "handle" ], I18n.t("errors.collection.handle_redirected"), "HANDLE_TAKEN")
        end

        {
          title:,
          description_html: description,
          handle: manual_handle,
          collection_type:,
          sort_order:,
          seo: seo_attributes(input, errors),
          product_ids: input[:product_ids],
          sources: normalize_sources(shop, input, errors, current_collection_id(input)),
          source_locale:,
          translations_prepared: prepare_translations(shop, source_locale, input, errors)
        }
      end

      # === 第 11 包：sources／rules 契約（D50；值域＝limits collection.*）================
      #
      # 🔴 「契約與求值同 PR」（三方向 :87 的教訓：先開 input 後補服務＝「存檔成功但
      #   條件沒了」）——本方法與 RuleCompiler／Rebuild 同包交付，白名單三處同步
      #   （這裡、RuleCompiler 常數、dev doc 值域表）。
      STRING_RULE_TYPES = %w[product_title product_type product_vendor variant_title].freeze
      MONEY_RULE_TYPES = %w[variant_price variant_compare_at_price].freeze
      INT_RULE_TYPES = %w[variant_weight variant_inventory].freeze

      # sources 只准掛在 smart 系列上（有帶且非 nil 才檢查；[] 也算「有帶」——
      # 對 manual 帶空陣列同樣是契約誤用）。effective_type：create＝輸入或預設、
      # update＝現行型別（型別不可變）。
      def sources_smart_only_gate!(effective_type, sources)
        return if sources.nil? || effective_type == "smart"

        raise TreeRejected, [ error([ "sources" ], I18n.t("errors.collection.sources_manual"), "INVALID") ]
      end

      def normalize_sources(shop, input, errors, current_id = nil)
        # 🔴 祖先集合**每個請求算一次，而且只活在這個呼叫堆疊裡**（第九輪 N2）：
        #   第八輪把它記在 `class << self` 的 `@cycle_ancestors` ⇒ 那是**類別物件**的
        #   ivar，在 Puma 進程存活期間永不清除。後果有三：①被引用方的邊後來被刪掉
        #   之後，同一個 worker 對該系列的每一次合法存檔都被回一個**假的**
        #   `reference_cycle` INVALID（且 `normalize` 一有 errors 就 return ⇒
        #   `replace_sources!` 的第二道複查根本走不到，商家無自救路徑）；
        #   ②跨租戶無界成長、無淘汰；③多執行緒共用一個裸 Hash。
        #   ⇒ 改成純區域變數，一次請求算一次、隨堆疊消失。
        ancestors_memo = current_id ? Collections::ReferenceGraph.ancestors(shop, current_id) : nil
        raw_sources = input[:sources]
        return nil if raw_sources.nil?   # 缺席＝保持現值（宣告式家族語義）

        # 「sources 只准掛在 smart 上」的閘移到 create／update（sources_smart_only_gate!）：
        # normalize 這一層看不見更新目標的**現行**型別（F3 改制後 collection_type 缺席＝nil），
        # 在這裡判會把「更新智慧系列、沒帶 collectionType、帶 sources」誤殺。
        sources = Array(raw_sources).each_with_index.map do |src, s_index|
          normalize_source(shop, src.respond_to?(:to_h) ? src.to_h.symbolize_keys : src, s_index, errors, current_id, ancestors_memo)
        end
        # 🔴 來源陣列本身也要有上限（2026-08-26 第六輪 K6）：60 條上限只算**條件總數**，
        #   而空來源（`{rules: []}`，契約允許）貢獻 0 條 ⇒ 一次請求可無限量建 source 列，
        #   且寫入發生在 `Collection.lock` 之內 ⇒ 把 rebuild／resync 共用的序列化點
        #   壓住整個寫入時長。
        source_max = Limits.fetch(:collection, :max_sources_per_collection)
        if sources.length > source_max
          errors << error([ "sources" ], I18n.t("errors.collection.too_many_sources", max: source_max), "TOO_LONG")
        end
        # 60 條上限：per-collection 口徑（fail-closed，P11-U18；三道裁定 :289）。
        total = sources.sum { |src| src[:rules].length }
        maximum = Limits.fetch(:collection, :max_rules_per_collection)
        if total > maximum
          errors << error([ "sources" ], I18n.t("errors.collection.too_many_rules", max: maximum), "TOO_LONG")
        end
        sources
      end

      # 更新態的本系列 id（J5 的自我引用判準）；建立態沒有 id ⇒ nil。
      def current_collection_id(input)
        match = GID_PATTERN.match(input[:id].to_s)
        match && match[1].to_i
      end

      # J1／J2：規則值的欄寬鏡射。原字串與正規化後的 key 都要過。
      def value_within_limit?(value, path, errors)
        maximum = Limits.fetch(:collection, :condition_value_max_chars)
        return true if value.length <= maximum

        errors << error(path + [ "valueText" ],
                        I18n.t("errors.collection.rule_value_too_long", max: maximum), "TOO_LONG")
        false
      end

      def normalize_source(shop, src, s_index, errors, current_id = nil, ancestors_memo = nil)
        path = [ "sources", s_index.to_s ]
        target = (src[:target_type] || "products").to_s
        # v1 只收 products：variants／sub_collections 的機制屬後續包（schema 已就位）。
        errors << error(path + [ "targetType" ], I18n.t("errors.collection.target_type_unsupported"), "INVALID") unless target == "products"

        inclusion_match = (src[:inclusion_match] || "all").to_s
        exclusion_match = src[:exclusion_match]&.to_s
        errors << error(path + [ "inclusionMatch" ], I18n.t("errors.collection.match_invalid"), "INVALID") unless Limits.fetch(:collection, :condition_logic_modes).map(&:to_s).include?(inclusion_match)
        if exclusion_match && !Limits.fetch(:collection, :condition_logic_modes).map(&:to_s).include?(exclusion_match)
          errors << error(path + [ "exclusionMatch" ], I18n.t("errors.collection.match_invalid"), "INVALID")
        end

        # 🔴 只有 exclusion、沒有任何 inclusion 的來源一律拒（第九輪）：求值時
        #   `where_sql` 對空 inclusion 回 nil ⇒ 該來源貢獻空集合，於是商家存了一組
        #   「看起來設定好了」的規則卻永遠 0 成員、零錯誤訊息——與 J4（status 打錯字）
        #   同一形態的靜默無效輸入。
        raw_rules = Array(src[:rules])
        if raw_rules.any? && raw_rules.none? { |rule| (rule.respond_to?(:to_h) ? rule.to_h.symbolize_keys : rule)[:block].to_s != "exclusion" }
          errors << error(path + [ "rules" ], I18n.t("errors.collection.inclusion_required"), "INVALID")
        end

        rules = raw_rules.each_with_index.map do |rule, r_index|
          normalize_rule(shop, rule.respond_to?(:to_h) ? rule.to_h.symbolize_keys : rule,
                         path + [ "rules", r_index.to_s ], errors, current_id, ancestors_memo)
        end
        { target_type: target, inclusion_match:, exclusion_match:, rules: rules.compact }
      end

      def normalize_rule(shop, rule, path, errors, current_id = nil, ancestors_memo = nil)
        block = rule[:block].to_s
        type = rule[:condition_type].to_s
        relation = rule[:relation].to_s

        unless %w[inclusion exclusion].include?(block)
          errors << error(path + [ "block" ], I18n.t("errors.collection.block_invalid"), "INVALID")
          return nil
        end
        # 🔴 值域是「哪個區塊有哪些型別」（95 §1.2/1.3）：exclusion 只認 4 個 v1 支援型。
        allowed = block == "exclusion" ? Collections::RuleCompiler::EXCLUSION_TYPES : Collections::RuleCompiler::INCLUSION_TYPES
        unless allowed.include?(type)
          errors << error(path + [ "conditionType" ], I18n.t("errors.collection.condition_type_invalid"), "INVALID")
          return nil
        end
        # relation 白名單與編譯器同一份（RELATIONS）——寫入層先擋，rebuild 不該是
        # 商家第一次知道 relation 打錯的地方。
        unless Collections::RuleCompiler.relations_for(type).include?(relation)
          errors << error(path + [ "relation" ], I18n.t("errors.collection.relation_invalid"), "INVALID")
          return nil
        end

        attrs = { block:, condition_type: type, relation: }
        case type
        when "product_status"
          # 🔴 值域白名單（2026-08-26 收斂輪 J4）：同 normalize 的 collection_type／
          #   sort_order、同方法的 block／condition_type／relation 全部逐一白名單，
          #   唯獨狀態值直通 ⇒ 打錯字存檔成功、系列恆空、商家零回饋；而且與**合法值**
          #   `archived`（因 `PRODUCT_ELIGIBLE_SQL` 構造上恆 0 成員）在畫面上無法區分。
          value = rule[:value_text].to_s.strip
          if value.empty?
            errors << error(path + [ "valueText" ], I18n.t("errors.collection.value_required"), "BLANK")
            return nil
          end
          unless Limits.enum(:product, :status_values).map { |v| v.to_s.downcase }.include?(value.downcase)
            errors << error(path + [ "valueText" ], I18n.t("errors.collection.status_value_invalid"), "INVALID")
            return nil
          end
          attrs[:value_text] = value.downcase
        when *STRING_RULE_TYPES
          value = rule[:value_text].to_s.strip
          if value.empty?
            errors << error(path + [ "valueText" ], I18n.t("errors.collection.value_required"), "BLANK")
            return nil
          end
          return nil unless value_within_limit?(value, path, errors)

          # 官方：contains 類值 ≥3 字元（limits condition_value_contains_min_length）。
          if %w[contains not_contains].include?(relation) &&
             value.length < Limits.fetch(:collection, :condition_value_contains_min_length)
            errors << error(path + [ "valueText" ], I18n.t("errors.collection.contains_too_short"), "TOO_SHORT")
            return nil
          end
          attrs[:value_text] = value
        when "product_tag"
          key = Tags::Normalize.key(rule[:value_text])
          if key.empty?
            errors << error(path + [ "valueText" ], I18n.t("errors.collection.value_required"), "BLANK")
            return nil
          end
          value = rule[:value_text].to_s.strip
          # 🔴 存的是原字串、比對的是 key——**兩者都要在欄寬內**（J1／J2 同一個
          #   「DB 欄寬沒有鏡射到寫入層」的類）。key 可能比原字串**長**（NFKC 與
          #   casefold 會展開：ß→ss、㍿→株式会社）⇒ 只驗原字串會漏。
          return nil unless value_within_limit?(value, path, errors)
          return nil unless value_within_limit?(key, path, errors)

          attrs[:value_text] = value
        when *MONEY_RULE_TYPES
          if %w[is_set is_not_set].include?(relation)
            # 一元運算子：無值。
          else
            cents = Catalog::SaveProduct.parse_money_for(rule[:value_money], shop, path + [ "valueMoney" ], errors)
            return nil if cents.nil?

            # 🔴 BIGINT 上界也要鏡射到寫入層（第六輪 K3）：超出範圍時 `create!` 拋的
            #   `ActiveModel::RangeError` 不在任何一層的 rescue 清單裡 ⇒ 漏成 500。
            if cents > Limits.fetch(:collection, :condition_value_max_cents)
              errors << error(path + [ "valueMoney" ], I18n.t("errors.collection.rule_value_too_large"), "TOO_LONG")
              return nil
            end

            attrs[:value_cents] = cents
          end
        when *INT_RULE_TYPES
          if rule[:value_int].nil?
            errors << error(path + [ "valueInt" ], I18n.t("errors.collection.value_required"), "BLANK")
            return nil
          end
          attrs[:value_int] = rule[:value_int].to_i
        when "collection"
          match = rule[:referenced_collection_id].to_s.match(GID_PATTERN)
          if match.nil?
            errors << error(path + [ "referencedCollectionId" ], I18n.t("errors.collection.reference_invalid"), "INVALID")
            return nil
          end
          referenced_id = match[1].to_i
          unless Collection.where(shop_id: shop.id, id: referenced_id).exists?
            errors << error(path + [ "referencedCollectionId" ], I18n.t("errors.collection.reference_invalid"), "INVALID")
            return nil
          end
          # 🔴 自我引用一律拒（2026-08-26 收斂輪 J5）：`compile_collection_exclusion`
          #   讀的是**物化成員**，所以「排除自己」＝「凡已在本系列的商品就排除」
          #   ——不存在不動點，membership 每次 rebuild／resync 都翻面，每翻一次
          #   bump 一次 cache stamp、發一筆 `collections/update`（EXTERNAL topic）。
          #   與 P11-B10（A⇄B 互相引用、由 rake 兜底）不同：自引在兜底下是
          #   **每跑一次翻一次**，兜底本身就是震盪源。
          if current_id && referenced_id == current_id
            errors << error(path + [ "referencedCollectionId" ], I18n.t("errors.collection.reference_self"), "INVALID")
            return nil
          end
          # 🔴 **任何長度的環一律拒**（2026-08-26 第七輪 L1）：自引只是環的 n=1 格。
          #   「A 排除 B」讀 B 的物化成員 ⇒ 反單調函數；奇數環沒有不動點 ⇒ 成員週期
          #   震盪，而反向傳播（K8）以「有沒有變」為傳播條件 ⇒ **無界 job 鏈與無界
          #   outbox**（實測 n=3 週期 6、永不終止）。偶數環雖會停，答案卻取決於起始
          #   狀態——環在這個語義下沒有一個「對」的答案，所以不分奇偶一律拒。
          if current_id && ancestors_memo && ancestors_memo.include?(referenced_id)
            errors << error(path + [ "referencedCollectionId" ], I18n.t("errors.collection.reference_cycle"), "INVALID")
            return nil
          end
          attrs[:value_int] = referenced_id
        end
        attrs
      end

      # 第 11 包：整份取代 sources／rules（宣告式；nil＝缺席＝保持現值）。
      # 🔴 在呼叫端 transaction 內執行；update 路徑已持 `Collection.lock`（create 是新列
      #   無競爭）——這正是研究 §5 的序列化點：規則編輯與 rebuild/resync 都以
      #   collection 列鎖為界，後到者必見前者已提交的規則。
      def replace_sources!(shop, collection, sources)
        return if sources.nil?

        # 🔴 環的複查必須在**序列化點內**再做一次（2026-08-26 第八輪 M2）：
        #   `normalize` 的 `cycle_ancestors` 是純讀的 pre-flight，跑在 transaction 與
        #   `Collection.lock` **之外**，而那個列鎖只鎖被編輯的**這一列**——被引用方
        #   那一列從頭到尾沒鎖。兩個並行請求各加環的一端（A 加 A→B、B 加 B→A）鎖的
        #   是不同列，構造上不互斥 ⇒ 兩邊都看不到對方未提交的邊、兩邊都通過 ⇒ 環落庫。
        #   同倉庫對「跨兩列的不變量」的既有做法就是店級序列化（`HandleChange` 檔頭③），
        #   這裡沿用：鎖 shop 列 ⇒ 兩個請求排隊，後到者的複查看得到先到者已提交的邊。
        referenced = sources.flat_map { |src| src[:rules] }
                            .select { |rule| rule[:condition_type] == "collection" }
                            .filter_map { |rule| rule[:value_int] }
        if referenced.any?
          Catalog::HandleChange.serialize!(shop)
          # 🔴 `lock: true`（第九輪 N1）：普通讀吃的是本 txn 在**取得店鎖之前**建立的
          #   快照，看不到我們排隊期間對方提交的邊 ⇒ 這道複查會整個失效、環照樣落庫。
          ancestors = Collections::ReferenceGraph.ancestors(shop, collection.id, lock: true)
          offender = referenced.find { |id| id == collection.id || ancestors.include?(id) }
          if offender
            raise TreeRejected, [ error([ "sources" ], I18n.t("errors.collection.reference_cycle"), "INVALID") ]
          end
        end

        CollectionSource.where(shop_id: shop.id, collection_id: collection.id).destroy_all
        sources.each_with_index do |src, index|
          source = CollectionSource.create!(
            shop_id: shop.id, collection_id: collection.id,
            source_type: "conditions", target_type: src[:target_type],
            inclusion_match: src[:inclusion_match], exclusion_match: src[:exclusion_match],
            position: index
          )
          src[:rules].each_with_index do |rule, r_index|
            CollectionSourceRule.create!(
              shop_id: shop.id, collection_source_id: source.id,
              position: r_index, **rule
            )
          end
        end
        # 規則變了 ⇒ 物化尚未反映 ⇒ 標 PENDING（Rebuild 成功時標 OK）。
        collection.update_columns(rebuild_status: "PENDING", updated_at: Time.current)
      end

      # 🔴 commit **之後**才 enqueue（txn 內不掛外部工作；job 只帶 id，執行時重讀
      #   當前規則——研究 §5 競態防線的另一半：帶規則快照的 job 會用舊規則蓋新結果）。
      def enqueue_rebuild(shop, collection, sources)
        return if sources.nil? || collection.nil?

        Collections::RebuildJob.perform_later(shop.id, collection.id)
      end

      def seo_attributes(input, errors)
        seo = input[:seo]
        return {} if seo.nil?

        attributes = {}
        unless seo[:title].nil?
          value = seo[:title].to_s.strip
          if value.length > Limits.fetch(:content, :seo_title_max_chars)
            errors << error([ "seo", "title" ], I18n.t("errors.collection.seo_title_too_long"), "TOO_LONG")
          end
          attributes[:seo_title] = value.presence
        end
        unless seo[:description].nil?
          value = seo[:description].to_s.strip
          if value.length > Limits.fetch(:content, :seo_meta_description_max_chars)
            errors << error([ "seo", "description" ], I18n.t("errors.collection.seo_description_too_long"), "TOO_LONG")
          end
          attributes[:seo_description] = value.presence
        end
        attributes
      end

      def create(shop, attributes)
        effective_type = attributes[:collection_type] || "manual"
        sources_smart_only_gate!(effective_type, attributes[:sources])
        collection = nil
        ActsAsTenant.with_tenant(shop) do
          # 🔴 `requires_new:` 不是可選的謹慎，是**正確性**：Rails 的 joined 巢狀交易
          #    下，這個 block 內 raise 再於 block 外 rescue，**什麼都不會回滾**——
          #    部分寫入照樣被外層 commit（`Idempotency::Guard` 註釋記錄過同一個陷阱）。
          #    v1 的 collectionSet 沒有外層交易，所以現在「剛好」是對的；
          #    但這種正確性取決於呼叫者，日後有人加上冪等包裝就靜默失效，
          #    而症狀是「回了 userErrors，資料庫卻多了一筆半成品系列」。
          #    🔴 這不是推論，是實測（2026-08-23，MySQL 8.4 / Rails 8.1）：
          #    joined 巢狀 ⇒ 殘留列數 1；requires_new ⇒ 0。
          #    **request spec 驗不到這件事**（RSpec 測試交易是 joinable: false，
          #    兩種寫法都綠），守衛在 spec/services/catalog/save_collection_spec.rb。
          ActiveRecord::Base.transaction(requires_new: true) do
            collection = Collection.create!(
              title: attributes[:title],
              # 建立時缺席＝空說明（`description_html` NOT NULL）；更新時缺席＝保持現值。
              description_html: attributes[:description_html] || "",
              handle: attributes[:handle] || unique_handle(shop, attributes[:title]),
              collection_type: effective_type,
              sort_order: attributes[:sort_order] || "manual",
              **attributes.fetch(:seo)
            )
            sync_members!(shop, collection, attributes[:product_ids])
            replace_sources!(shop, collection, attributes[:sources])
            reject_translations!(shop, collection, attributes)
          end
        end
        enqueue_rebuild(shop, collection, attributes[:sources])
        Result.new(collection: collection.reload, user_errors: [])
      rescue TreeRejected => rejected
        Result.new(collection: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotUnique
        Result.new(collection: nil, user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(collection: nil, user_errors: translate_record_invalid(invalid))
      end

      # model 驗證（uniqueness）與 DB 唯一索引是兩條路徑，**兩條都要轉成同一個碼**——
      # 只處理其中一條的症狀是「單機測試回 HANDLE_TAKEN、併發時回 INVALID」。
      def translate_record_invalid(invalid)
        invalid.record.errors.map do |model_error|
          if model_error.attribute == :handle && model_error.type == :taken
            error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN")
          else
            error(nil, model_error.full_message, "INVALID")
          end
        end
      end

      def update(shop, input, attributes)
        match = GID_PATTERN.match(input[:id].to_s)
        return Result.new(collection: nil, user_errors: [ error([ "id" ], I18n.t("errors.collection.gid_invalid"), "INVALID") ]) unless match
        if input[:lock_version].nil?
          return Result.new(collection: nil,
                            user_errors: [ error([ "lockVersion" ], I18n.t("errors.collection.lock_version_required"), "BLANK") ])
        end

        collection = nil
        ActsAsTenant.with_tenant(shop) do
          # 見 create 的 `requires_new:` 說明——兩條路徑必須一致。
          ActiveRecord::Base.transaction(requires_new: true) do
            collection = Collection.lock.find_by(id: match[1])
            raise ActiveRecord::RecordNotFound if collection.nil?
            raise ActiveRecord::StaleObjectError.new(collection, "update") if collection.lock_version != input[:lock_version]

            # 第 6 包：系列 handle 可改（先前是靜默忽略——那比硬拒更糟，
            # 商家以為改了、其實沒改）。相同值＝no-op。
            new_handle = attributes[:handle]
            handle_changed = new_handle.present? && new_handle != collection.handle
            old_handle = collection.handle
            # 🔴 跨兩張表的不變量 ⇒ 店級序列化（HandleChange 檔頭③；與商品同一套）。
            Catalog::HandleChange.serialize!(shop) if handle_changed

            # 🔴 型別建立後**不可變**（審查 F3 連動；本尊官方逐字，取證 2026-08-26：
            #   "You can't change an automatic collection to a manual collection. Instead,
            #   create a manual collection and add the products that you want."
            #   https://help.shopify.com/en/manual/products/collections/manual-shopify-collection
            #   2026 新 sources 模型頁對此沉默＝未取得反例 ⇒ 從嚴照舊）。硬拒也順帶封掉
            #   「smart→manual 後 sources 列殘留、ResyncProduct 仍照算」的孤兒面。
            #   同值重送＝no-op。
            if attributes[:collection_type] && attributes[:collection_type] != collection.collection_type
              raise TreeRejected, [ error([ "collectionType" ],
                                          I18n.t("errors.collection.type_immutable"), "INVALID") ]
            end
            sources_smart_only_gate!(collection.collection_type, attributes[:sources])

            collection.assign_attributes(
              title: attributes[:title],
              handle: handle_changed ? new_handle : collection.handle,
              # `||` 而非直接指派：normalize 缺席時給 nil＝保持現值；
              # Ruby 的 "" 是 truthy ⇒ 顯式清空仍寫得進去（與 SaveProduct 同一形）。
              description_html: attributes[:description_html] || collection.description_html,
              sort_order: attributes[:sort_order] || collection.sort_order,
              **attributes.fetch(:seo)
            )
            collection.updated_at = Time.current
            collection.save!
            # 改名 301 同 txn（62 §F.3；與 SaveProduct 同一套語義）。
            if handle_changed
              Catalog::HandleChange.register!(shop:, resource: :collection,
                                              old_handle:, new_handle:)
            end
            sync_members!(shop, collection, attributes[:product_ids])
            replace_sources!(shop, collection, attributes[:sources])
            reject_translations!(shop, collection, attributes)
          end
        end
        enqueue_rebuild(shop, collection, attributes[:sources])
        Result.new(collection: collection.reload, user_errors: [])
      rescue TreeRejected => rejected
        Result.new(collection: nil, user_errors: rejected.user_errors)
      rescue ActiveRecord::RecordNotFound
        Result.new(collection: nil, user_errors: [ error([ "id" ], I18n.t("errors.collection.not_found"), "NOT_FOUND") ])
      rescue ActiveRecord::StaleObjectError
        Result.new(collection: nil, user_errors: [ error(nil, I18n.t("errors.collection.stale"), "STALE_OBJECT") ])
      rescue ActiveRecord::RecordNotUnique
        # 併發窗：輸家撞 `uq_collections_handle`（審查 R6-2，與商品同型）。
        Result.new(collection: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_taken"), "HANDLE_TAKEN") ])
      rescue Catalog::HandleChange::Raced
        Result.new(collection: nil,
                   user_errors: [ error([ "handle" ], I18n.t("errors.collection.handle_raced"), "HANDLE_TAKEN") ])
      rescue ActiveRecord::RecordInvalid => invalid
        Result.new(collection: nil, user_errors: translate_record_invalid(invalid))
      end

      # 宣告式成員同步（只對手動系列）：未列出＝移除，順序＝陣列順序。
      # 🔴 智慧系列送 productIds 一律忽略——成員是規則的函數，接受它等於製造第二個真相。
      # 成員 GID → id。🔴 **解析不出來或不屬於本店的一律報錯，不得靜默丟掉**：
      # 這是宣告式 API（未列出＝移除），靜默丟掉的症狀是「存檔成功，但成員少了一個」——
      # 沒有錯誤訊息、沒有紅字，商家要到前台才發現，而那時已經不知道是哪一步弄丟的。
      # 併發刪除（商品剛被同事刪掉）也走這條：回 NOT_FOUND 讓商家重載後看見商品真的沒了，
      # 比替他決定「那就不要那個成員」誠實。
      def resolve_member_ids(shop, product_ids, errors)
        parsed = Array(product_ids).map do |gid|
          id = gid.to_s[PRODUCT_GID_PATTERN, 1]
          errors << error([ "productIds" ], I18n.t("errors.collection.product_gid_invalid", gid: gid.to_s), "INVALID") if id.nil?
          id&.to_i
        end
        return [] if errors.any?

        ids = parsed.uniq
        found = Product.where(shop_id: shop.id, id: ids).pluck(:id).to_set
        missing = ids.reject { |id| found.include?(id) }
        missing.each do |id|
          errors << error([ "productIds" ], I18n.t("errors.collection.product_not_found", id:), "NOT_FOUND")
        end
        # 🔴 `pluck` 回的是 **DB 順序**不是送入順序——position 必須照商家給的陣列順序，
        #    否則「拖曳排序後儲存，順序又跳回去」。排序一律用原陣列。
        ids
      end

      def sync_members!(shop, collection, product_ids)
        return if product_ids.nil?
        return unless collection.collection_type == "manual"

        errors = []
        ids = resolve_member_ids(shop, product_ids, errors)
        raise TreeRejected, errors if errors.any?

        collection.collection_products.where.not(product_id: ids).delete_all
        ids.each_with_index do |product_id, index|
          record = collection.collection_products.find_or_initialize_by(product_id:)
          record.shop_id = shop.id
          record.position = index
          record.save!
        end
        # 第 3 包 cache stamp：成員集合變了（14 §F1 的 collections.products_updated_at）。
        Catalog::CacheStamps.bump_collection_members!(shop.id, collection.id)
      end

      # 譯文與商品共用同一個服務（只換 resource_type）。
      # 🔴 驗證與 sanitize 在 normalize（txn 外）的 `prepare_translations` 完成（審查 C4，
      #   與 SaveProduct 同拆法）；這裡只做 DB 寫入。
      def prepare_translations(shop, source_locale, input, errors)
        prepared = Translations::Upsert.prepare(
          shop:, source_locale:,
          translations: Array(input[:translations]).map { |entry| entry.respond_to?(:to_h) ? entry.to_h.symbolize_keys : entry }
        )
        errors.concat(prepared.user_errors)
        prepared
      end

      def reject_translations!(shop, collection, attributes)
        result = Translations::Upsert.commit(
          shop:,
          resource_type: "COLLECTION",
          resource_id: collection.id,
          source_locale: attributes[:source_locale],
          source_values: {
            "title" => collection.title,
            "body_html" => collection.description_html,
            "meta_title" => collection.seo_title,
            "meta_description" => collection.seo_description
          },
          prepared: attributes[:translations_prepared]
        )
        # ⚠️ 現行 `Upsert.commit` 只回空 user_errors ⇒ 構造上不可達的 fail-closed 網（審查 F7）。
        raise TreeRejected, result.user_errors if result.user_errors.any?
      end

      # 生成衝突＝數字尾碼（limits `collision_strategy_generated: numeric_suffix_from_1`，
      # 與 SaveProduct 同語義）。
      # 🔴 舊版是 `3.times` 重跑同一個確定性生成器——三輪必得同一個 candidate，
      #   任何衝突都直接掉進隨機 fallback（`collection-<8碼>`），而商品側是
      #   `veteran → veteran-1`。同倉兩套語義，且隨機 fallback 不經任何檢查
      #   （審查 P6-6）。隨機碼現在只留給「品質閘門不過」那一種情形。
      def unique_handle(shop, title)
        base = Catalog::HandleGenerator.call(title, resource: "collection").handle
        return base unless collection_handle_taken?(shop, base)

        (1..).each do |suffix|
          candidate = "#{base}-#{suffix}"
          return candidate unless collection_handle_taken?(shop, candidate)
        end
      end

      def collection_handle_taken?(shop, handle)
        return true if Limits.fetch(:handle, :reserved).map(&:to_s).include?(handle)
        return true if Catalog::HandleChange.path_reserved?(
          shop, Catalog::HandleChange.path_for(:collection, handle))

        Collection.where(shop_id: shop.id, handle:).exists?
      end

      def error(field, message, code)
        { field:, message:, code: }
      end
    end
  end
end
