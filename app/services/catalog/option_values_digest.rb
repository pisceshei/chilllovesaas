# 商品目錄相關的 service namespace。
module Catalog
  # 變體選項座標的正規化摘要——`product_variants.option_values_digest` 的**唯一產生處**。
  #
  # ## 它是什麼、不是什麼
  #
  # 🔴 **digest 是我方內部實作，本尊沒有這個概念**（2026-08-15 parity 查證：本尊
  # `ProductVariant` 型別上只有 `title` 與 `selectedOptions`，沒有任何組合鍵）。
  # 它只承擔**兩件事**：
  #   ① 當下狀態的唯一性兜底（DB 的 `uq_product_variants_option_values_digest`）；
  #   ② diff 時**沒有帶 id 的那些列**，在投影完成之後的比對鍵。
  #
  # 🔴 **它不是變體的身分**。primary match key 是 `variants[].id`
  # （`config/limits.yml` 的 `variant_identity_id_wins: true`；`docs/specs/63` §B.4
  # 「建立與更新是同一支 mutation，差別只在有沒有 `id`」）。
  #
  # 🔴 **不得對外曝露**：不進 GraphQL 型別、不進 GID、不進 feed／URL／CSV。
  # 因為它不外露，任何時候都可以一句 `UPDATE` 全表重算 ⇒ 不需要版本前綴欄。
  # **這兩件事綁在一起，不得只留其一。**
  #
  # ## 為什麼輸入是 id 不是字串
  #
  # `docs/specs/67` §B.3-4 逐字：「選項與選項值的**身分**——譯文掛在
  # `product_option_values.id` 上，不是掛在字串上。`63` §B.5『選項增刪時的變體身分保持』
  # 的前提是身分穩定；**若變體以「選項值字串」比對，切語言就會找不到變體**」。
  # ⇒ 這是規格層裁定，不是效能取捨。
  #
  # 連帶好處：**改名一個選項值（Red → Crimson）digest 完全不變**——改名走的是
  # `option_values.value` 的 in-place UPDATE，`id` 不動。變體 id、庫存、譯文全部存活。
  # 這與本尊一致：`productOptionUpdate` 的 `optionValuesToUpdate` 收
  # `OptionValueUpdateInput{ id: ID!（必填）… }`，**本尊的選項值也是有 id 的一等實體**。
  #
  # ## 為什麼排序鍵是 product_option_id 不是 position
  #
  # 🔴 `position` 是使用者**拖曳就會改**的顯示順序（本尊有 `productOptionsReorder`）；
  # `product_option_id` 是不可變主鍵。**身分鍵不得由可變資料決定。**
  #
  # 照 position 排序的話，每次重排選項都必須在同一 transaction 內重算該商品**所有**變體的
  # digest——任何一條路徑忘記重算就是靜默的身分斷裂，而那正是 `63` §B.5 要防的事故形態。
  #
  # ⚠️ **`docs/specs/13` §F1 坑第 3 條原文寫「按 option position 排序」，已於 2026-08-15
  # 改為 `product_option_id`**。該條的原意是「順序敏感 ⇒ 先正規化再 hash」，本裁定完整保留原意，
  # 只換掉排序基準。**這不算偏離本尊**——本尊根本沒有 digest（見上）。
  #
  # @see docs/DECISIONS.md D12
  # @see docs/specs/13-spec-products-inventory-media.md §F1-2
  # @see docs/specs/67-multilingual.md §B.3-4
  module OptionValuesDigest
    module_function

    # 算出一個變體的選項座標摘要。
    #
    # @param pairs [Array<Array(Integer, Integer)>] `[[product_option_id, option_value_id], ...]`
    # @return [String] 40 字元小寫 hex
    # @raise [TypeError, ArgumentError] 非整數輸入
    # @raise [ArgumentError] 同一個選項出現一次以上
    # @note 副作用：無。
    def call(pairs)
      # 🔴 嚴格 `is_a?(Integer)`，**不是** `Integer()`（2026-08-16，PR #38 驗收發現）：
      #    `Integer(1.9)` 回 **1**（靜默截斷）⇒ `[[1.9, 2.9]]` 與 `[[1, 2]]` 算出
      #    **同一個 digest**——而檔頭 @raise 宣稱「非整數輸入」會 raise，Float 卻溜過去。
      #    id 來自 DB bigint，正常路徑不會是 Float；但 digest 是唯一性兜底，
      #    「兜底」對輸入寬鬆就不是兜底了。`Integer("3")` 的字串轉換同理拒絕。
      normalized = pairs.map do |option_id, value_id|
        [ option_id, value_id ].each do |v|
          raise TypeError, "id 只收 Integer，實得 #{v.class}: #{v.inspect}" unless v.is_a?(Integer)
        end
        [ option_id, value_id ]
      end
      if normalized.map(&:first).uniq.size != normalized.size
        raise ArgumentError,
          "一個變體在一個選項上只能有一個值（實得 #{normalized.inspect}）——" \
          "這個約束在 DB 層由 uq_pvov_variant_option 擋住，這裡是它的 model 層對應"
      end

      Digest::SHA1.hexdigest(canonical(normalized))
    end

    # 正規化字串：依 `product_option_id` 升冪，每對編碼成 `"選項id:值id"`，以 `,` 相接。
    #
    # 🔴 **單射性**：兩個 id 都是十進位整數（字元集不含 `:` 與 `,`），且同一變體內
    # option_id 互異 ⇒ 字串可唯一解析回原始集合，**不存在分隔符注入碰撞**。
    #
    # 🔴 **若日後有人要把非數字（選項值字串、metaobject handle）塞進輸入，
    # 必須同時改成長度前綴編碼**，否則上面那句單射性就不成立了。
    #
    # @param pairs [Array<Array(Integer, Integer)>]
    # @return [String]
    # @note 副作用：無。
    def canonical(pairs)
      pairs.sort_by(&:first).map { |option_id, value_id| "#{option_id}:#{value_id}" }.join(",")
    end

    # 無選項變體（本尊的 `Default Title`）的 digest ＝ 空集合的 SHA1。
    #
    # 🔴 這個值也寫死在 `20260816000000` migration 的 `EMPTY_DIGEST`，兩處各有測試釘住。
    NO_OPTIONS = call([]).freeze
  end
end
