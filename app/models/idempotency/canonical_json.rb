# 冪等機制的 namespace。
module Idempotency
  # 參數指紋的正規化與雜湊。
  #
  # `fingerprint = SHA256(canonical_json(input))`（`docs/specs/11` §2.1(d)）。
  #
  # 🔴 **不做正規化會誤判 mismatch 而卡死**：同一個請求換一下欄位順序就會算出不同指紋，
  # 於是重試被判成「同一把 key 用於不同參數」（`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`），
  # 而呼叫端明明什麼都沒改。逐字依據是官方的
  # 「Ensure consistent ordering of input fields to avoid fingerprinting mismatches」。
  #
  # 五條規則（11 §2.1(d)），每一條都有理由：
  #
  # | # | 規則 | 為什麼 |
  # |---|---|---|
  # | ① | 物件 key **遞迴字典序排序** | JSON 物件的鍵順序**沒有語義**，序列化順序卻會變 |
  # | ② | **移除 null 欄位** | 「沒傳」與「傳 null」在 GraphQL input 上是同一件事 |
  # | ③ | 陣列**保持原順序** | 🔴 陣列順序**有語義**（變體位置、退款分攤順序），排序會把兩個不同的請求算成同一個 |
  # | ④ | 數字一律整數 cents | 金額不得以 float 進指紋（鐵律 3）。🔴 **遇到 `Float`／`BigDecimal` 一律 `raise TypeError`，不做轉換** |
  # | ⑤ | **不含 `idempotencyKey` 本身** | 否則指紋恆等於自己，永遠不可能偵測到參數不符 |
  #
  # 🔴 **規則④的表述在 2026-08-15 修過一次（PR #29 驗收 🟡 指出）**。
  # 原文寫的是「`1480.0` 與 `1480` 必須是同一個指紋」——那是**註釋自己發明的**，
  # 而且**與實作相反**：實作遇 `Float` 一律 `raise`（見下方 `normalize`），
  # 兩者永遠不會有「同一個指紋」，因為前者根本進不來。
  # 11 §2.1(d)④ 的原文**只有五個字**：「數字一律整數 cents」。
  #
  # ⚠️ **為什麼這種註釋比沒有註釋更糟**：它描述了一個**看起來很合理的正規化行為**
  # （把 `1480.0` 收斂成 `1480`），讀的人會據此認為「送 float 是安全的，會被自動處理」——
  # 而實際上那會拋例外。**錯的註釋會讓人做出錯的決定，沒有註釋只會讓人去看代碼。**
  # ⇒ 這也是為什麼本專案的規約是「複雜邏輯要註明**規格出處**」：
  #   出處逼你回去看原文，而回去看原文就會發現自己多寫了一句。
  #
  # ## ⚠️ 本類別**不做** claim/replay
  #
  # 它只負責「把 input 算成一個穩定的指紋」。搶佔 `processing` 列、偵測重複、
  # 回放結果的狀態機**刻意延後**，四個未決點見
  # `docs/worklog/2026-08-15-冪等指紋.md`。
  #
  # @see docs/specs/11-production-baseline.md §2.1(d)
  module CanonicalJson
    # 指紋裡一律不含的鍵（規則⑤）。比對時走 camelCase 與 snake_case 兩種寫法。
    EXCLUDED_KEYS = %w[idempotencyKey idempotency_key].freeze

    class << self
      # 把輸入正規化成穩定的 JSON 字串。
      #
      # @param input [Hash, Array, Object] mutation 的參數（通常是 Hash）
      # @return [String] 正規化後的 JSON
      # @note 副作用：無。
      # @see docs/specs/11-production-baseline.md §2.1(d)
      def dump(input)
        JSON.generate(normalize(input, root: true))
      end

      # 算出參數指紋。
      #
      # @param input [Hash, Array, Object] mutation 的參數
      # @return [String] 64 字元的 SHA-256 十六進位字串
      # @note 副作用：無。
      # @see docs/specs/11-production-baseline.md §2.1(d)
      def fingerprint(input)
        Digest::SHA256.hexdigest(dump(input))
      end

      # 遞迴正規化。
      #
      # @param value [Object] 任意輸入
      # @param root [Boolean] 是否為頂層——**只有頂層**套用規則⑤（排除 idempotencyKey）
      # @return [Object] 正規化後的值
      # @note 副作用：無。
      def normalize(value, root: false)
        case value
        when Hash
          normalize_hash(value, root:)
        when Array
          # 🔴 **不排序**：陣列順序有語義（規則③）。
          value.map { |item| normalize(item) }
        when Float, BigDecimal
          # 🔴 規則④：金額不得以 float 進指紋。float 的十進位表示不穩定
          # （`0.1 + 0.2` 的字串化在不同路徑上可能不同），而金額在本專案一律是
          # integer cents（鐵律 3）—— 這裡遇到 float 代表**上游已經漏了單位邊界**。
          raise TypeError,
            "指紋不接受浮點數 #{value.inspect}——金額一律 integer cents（鐵律 3／11 §2.1(d) 規則④）"
        else
          value
        end
      end

      private

      # 🔴 規則⑤**只在頂層生效**。第一版寫成每一層都排除，被自家 spec 抓到：
      # 一個巢狀的、真的叫 `idempotencyKey` 的欄位（例如 metafield 值、巢狀 job 規格）
      # 會被靜默丟出指紋 ⇒ 兩個實際上不同的請求算出**同一個指紋**，
      # 而參數不符（`IDEMPOTENCY_KEY_PARAMETER_MISMATCH`）就永遠偵測不到。
      # 規格 11 §2.1(d) ⑤ 的原文是「不含 `idempotencyKey` **本身**」——本身＝頂層那把。
      def normalize_hash(hash, root:)
        hash
          .reject { |key, val| (root && EXCLUDED_KEYS.include?(key.to_s)) || val.nil? }   # ⑤ ＋ ②
          .sort_by { |key, _| key.to_s }                                                  # ①
          .to_h { |key, val| [ key.to_s, normalize(val) ] }
      end
    end
  end
end
