# 冪等機制的 namespace。
module Idempotency
  # 「哪些 mutation 必須帶 `idempotencyKey`」的唯一判準來源。
  #
  # 清單住在 `config/limits.yml` 的 `idempotency.required_for`（鐵律 6），
  # **不在程式碼裡各自列一份**——那正是鐵律 7 要防的漂移形態。
  #
  # ## 🔴 我方的清單比本尊長，而且不會因升版變成 parity
  #
  # 本尊自 2026-04 起強制冪等的是 **17 支**，全部是 refund／inventory／location
  # 三類，也就是 **Shopify 自己的金流寫入點**——不涵蓋我方自有的金流路徑。
  # 特別是**本尊的 `orderCreate` 至 unstable 版都沒有任何冪等機制**。
  # ⚠️ 我方目前**沒有** `orderCreate` 這支 mutation——訂單成立走 `draftOrderComplete`
  #    （已在 ours 段）與結帳流程；CLAUDE.md 鐵律 5 的「訂單成立必帶 idempotencyKey」
  #    由前者承載。日後若真的加，它必須進 ours 段。
  # 我方擴充的判準沿用 NP1-D：「凡金流寫入一律強制冪等，不論本尊有無強制」。
  # ⇒ 升版時**不得**把 ours 段併進官方段（`limits.yml` 的註解已標分隔）。
  #
  # ## ⚠️ 形態也與本尊不同
  #
  # 本尊主流是 GraphQL **directive**：`refundCreate(...) @idempotent(key: "…")`；
  # 我方走 mutation **參數**。兩者語義相同、形狀不同，登記於 D14 偏離 F。
  # （該 directive 的 SDL 定義 shopify.dev 上**沒有獨立頁面**，我方寫的
  # `directive @idempotent(key: String!) on FIELD` 是從用法反推的假設。）
  #
  # @see config/limits.yml `idempotency`
  # @see docs/DECISIONS.md D14 偏離 E／F
  module RequiredMutations
    class << self
      # 這支 mutation 是否必須帶冪等鍵。
      #
      # @param mutation_name [String, Symbol] GraphQL 上的 mutation 名（camelCase）
      # @return [Boolean]
      # @note 副作用：無；只讀已載入的 limits 設定。
      # @see docs/specs/11-production-baseline.md §2.1
      def required?(mutation_name)
        # 🔴 正規化為 camelCase 再比對（2026-08-24 對抗審查 high）：limits 清單是
        #    camelCase（inventoryAdjustQuantities）、BaseMutation 傳的是 graphql_name
        #    （PascalCase InventoryAdjustQuantities）——不正規化則**整個 enforce 機制
        #    對所有 mutation 恆 false**（實測），清單裡的每一支都在裸奔。
        name = mutation_name.to_s
        all.include?(name[0].downcase + name[1..].to_s)
      end

      # 租戶域的強制清單。
      #
      # 🔴 **刻意不含 `required_for_platform`**：那兩支是台灣統一發票的平台域 mutation，
      # 是 **pack-scoped** 的（`jurisdictions.tw.tax_invoice`）——HK 為 default 時
      # 它們**根本不存在於 schema**。把兩份清單混在同一個檢查點，
      # HK 首發的 schema 快照測試會直接紅掉（`limits.yml` 該鍵的註解已寫明）。
      #
      # @return [Array<String>] mutation 名清單
      # @note 副作用：無。
      def all
        @all ||= Limits.fetch(:idempotency, :required_for).map(&:to_s).freeze
      end

      # 測試用：清掉 memoize（`Limits` 是 boot 期載入，正常執行期不會變）。
      #
      # @return [void]
      # @note 副作用：清除本模組的記憶體快取。
      def reset!
        @all = nil
      end
    end
  end
end
