# frozen_string_literal: true

module Locales
  # BCP-47 截尾 fallback 鏈（docs/specs/67 §C.4(a)；`i18n.fallback_chain_mode: bcp47_truncation`）。
  #
  # ①這是什麼：純函式。給一個語言標籤，回傳「這個語言缺譯文時，還可以去看哪些語言」的
  #   **有序**清單（不含自己）。它不碰資料庫、不知道商店啟用了什麼——那是 `Translations::Resolve`
  #   的事（本模組只回答「BCP-47 上誰是誰的上位」，Resolve 才回答「這家店能不能看」）。
  #
  # ②具體功能（完整值域）：
  # ```
  #   zh-Hant-HK → ["zh-Hant"]        # 截掉 region；到 zh 就停（zh 在禁用表）
  #   zh-Hant    → []                 # 已經是最短合法形態
  #   zh-Hans-CN → ["zh-Hans"]
  #   en-GB      → ["en"]
  #   pt-BR      → ["pt"]
  #   ja         → []
  # ```
  #   鏈長上限＝2（`i18n.resolve.max_chain_length: 3` 是「候選數」含自己；`Tag::FORMAT`
  #   只有 language[-script][-region] 三段，所以截尾最多兩次）。
  #
  # ③怎麼做到：逐段截尾，命中 `i18n.forbidden_locale_tags` 即**停止整條鏈**（不是跳過該階
  #   繼續截）——67 §C.4(a) 逐字：「不得續截到只剩語言碼、若該語言碼本身被禁用」，且
  #   「這是 zh 唯一被特別處理的地方，而處理方式是**縮短鏈**，不是特例分支」。
  #
  #   🔴 **這一條與 CLDR 同構，不是我方自創的加嚴**（2026-08-25 取證；引文於同日
  #   對抗審查 D1 後**二次修正**——首版引了一個不存在的檔案路徑與一段無法溯源的
  #   「官方逐字」，已撤回，以下三個來源皆經親自抓取複驗）：
  #   ① CLDR 正典 XML `common/supplemental/supplementalData.xml` 第 5157 行（main 分支）：
  #      `<parentLocale parent="root" localeRules="nonlikelyScript" locales="…sr_Latn…zh_Hant"/>`
  #      ——`zh_Hant` 的 parent 明文是 **root**，規則名 `nonlikelyScript`。
  #      https://raw.githubusercontent.com/unicode-org/cldr/main/common/supplemental/supplementalData.xml
  #   ② 理由在 CLDR 的 TR35（LDML 規格，unicode-org/cldr repo 內）逐字：
  #      `In some cases, the normal truncation inheritance does not function well. For example,
  #      if the truncation algorithm changes script, then a mixture of child and parent textual
  #      data is a mishmash of different scripts.`
  #      https://raw.githubusercontent.com/unicode-org/cldr/main/docs/ldml/tr35.md
  #   ③ 衍生 JSON（unicode-org/**cldr-json** repo，非正典）把同一事實寫成 `"zh-Hant": "und"`：
  #      https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-core/supplemental/parentLocales.json
  #   ⇒ 我方的「截到 zh 就停」＝CLDR 的「zh-Hant 的 parent 是 root」。差別只在我方沒有 root
  #   這一階（root 之後我們接的是 base row ＝來源語言），不在截尾規則本身。
  #
  #   🔴 **與 RFC 4647 §3.4 Lookup 的差異必須誠實登記**：Lookup 的字面演算法是
  #   「逐段截尾直到剩下語言碼，都不中就用 default」，它**不知道 script 的語義**，
  #   所以照字面實作會產生 `zh-Hant → zh`。我方（與 CLDR）在此處**刻意偏離 RFC 字面**，
  #   理由是 zh 的字體歧義（`i18n.forbidden_locale_tags` 的立法理由）。這是 ours 裁定
  #   ＋CLDR 佐證，**不得寫成「照 RFC 實作」**。
  #
  # ④跨功能影響：唯一消費者＝`Translations::Resolve`（第 7 包）。第 34 包的 `lang` 屬性值
  #   必須是 Resolve 回傳的 `resolved_locale`（可能是 `zh-Hant`），**不是**請求語言
  #   （`zh-Hant-HK`）——W3C 的 `lang` 語義是「這段文字實際是什麼語言」。
  #   新增任何「語言 A 缺了看 B」的需求，改這裡，不要在呼叫端各寫一份。
  module FallbackChain
    # 本模組只實作這一種模式；limits 若被改成別的值一律 raise（fail-closed，
    # 不得靜默退化成「沒有鏈」——那會讓 zh-Hant-HK 的使用者直接掉到英文）。
    SUPPORTED_MODE = "bcp47_truncation"

    class UnsupportedMode < StandardError; end

    module_function

    # @param tag [String] 請求的語言標籤（會先正規化大小寫）
    # @return [Array<String>] 依序的 fallback 目標，**不含 tag 自己**；無可回落時回 []
    # @raise [UnsupportedMode] `i18n.fallback_chain_mode` 不是 bcp47_truncation
    def chain(tag)
      assert_mode!
      normalized = Locales::Tag.normalize(tag)
      parts = normalized.split("-")
      result = []

      while parts.length > 1
        parts = parts[0..-2]
        candidate = parts.join("-")
        break if forbidden?(candidate)
        # 🔴 截尾在結構上永遠產生不出 never_fallback_pairs 的另一半（zh-Hant 的前綴
        #    不可能是 zh-Hans），但這道過濾仍然留著：它是**模式無關**的不變量，
        #    日後若有人加第二種 mode，禁令必須繼續成立。
        #    ⚠️ 突變驗證：刪掉它，現有測試**不會紅**（構造上不可達）——
        #    所以它是 fail-closed 的防線，不是承重守衛，不得宣稱「測試證明它有效」。
        break if never_pair?(normalized, candidate)

        result << candidate
      end

      result
    end

    # 解析時要依序嘗試的完整候選（含 tag 自己）。Resolve 的實際輸入。
    #
    # @param tag [String]
    # @return [Array<String>] `[tag, *chain(tag)]`，長度 ≤ `i18n.resolve.max_chain_length`
    def candidates(tag)
      [ Locales::Tag.normalize(tag), *chain(tag) ]
    end

    def assert_mode!
      mode = Limits.fetch(:i18n, :fallback_chain_mode).to_s
      return if mode == SUPPORTED_MODE

      raise UnsupportedMode, "i18n.fallback_chain_mode=#{mode} 尚未實作（只支援 #{SUPPORTED_MODE}）"
    end

    def forbidden?(candidate)
      Limits.fetch(:i18n, :forbidden_locale_tags)
            .map { |value| value.to_s.downcase }
            .include?(candidate.downcase)
    end

    # `i18n.never_fallback_pairs` 的雙向比對。以**子標籤邊界**判定覆蓋範圍：
    # `zh-Hant` 這條規則涵蓋 `zh-Hant-HK`，但不涵蓋 `zh-Hantx`（若存在）。
    def never_pair?(requested, candidate)
      Limits.fetch(:i18n, :never_fallback_pairs).any? do |pair|
        a, b = pair.map(&:to_s)
        (covers?(a, requested) && covers?(b, candidate)) ||
          (covers?(b, requested) && covers?(a, candidate))
      end
    end

    def covers?(rule, tag)
      tag == rule || tag.start_with?("#{rule}-")
    end
  end
end
