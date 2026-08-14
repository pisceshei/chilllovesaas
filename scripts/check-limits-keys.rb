#!/usr/bin/env ruby
# frozen_string_literal: true

# limits.yml 的鍵型別檢查——把「所有鍵都必須是 String」從紀律變成機制。
#
# 背景（2026-08-15，PR #29 驗收後的註釋↔行為矛盾掃描發現）：
#   Psych 走 **YAML 1.1**，裸字 `on` / `off` / `yes` / `no` / `y` / `n` 一律解析成布林，
#   `~` / `null` 解析成 nil，`2026-08-15` 解析成 Date。這些規則對**值**是常識，
#   但沒人預期它同樣適用於**鍵**。
#
#   實際踩到的那一筆：`jurisdictions.hk.accounting.gift_card_entry_points.M27..M32`
#   原文寫成 `{ on: gift_card_issued_by_admin, ... }`，六個 `on` 鍵全部是 `true`（TrueClass）。
#
# 為什麼要 CI 擋而不是靠 review：
#   config/application.rb 用 `deep_symbolize_keys` 載入 limits.yml，而非字串鍵**原樣保留**
#   （`true` 不能 `to_sym`）⇒ 該筆的鍵實測是 `[true, :direction, :revenue]`，
#   `Rails.configuration.x.limits.dig(..., :M27).fetch(:on)` 得到 KeyError，
#   而 KeyError 的訊息看不出根因是 YAML 1.1。實作者最可能的反應是「那就改用 `true` 當鍵」，
#   那會把 bug 固化成契約——鍵名從此不是它在檔案裡看起來的樣子。
#   這種錯誤只在**鍵名剛好是那幾個字**時出現，寫的人與 review 的人都不會特地去想，
#   所以它屬於「必須由機制擋」的那一類。
#
# 檢查什麼：
#   規則 1｜TARGETS 列出的 YAML 檔中，**每一層 mapping 的鍵都必須解析成 String**。
#
# 不檢查什麼（🔴 誠實聲明，這段就是本腳本對外宣稱的契約，不得誇大）：
#   1. **不檢查值**。值寫成 `on` 而意圖是字串 "on"（而非布林 true）同樣會出錯，
#      但值的正確型別要讀規格才知道（`no_fund_pooling: true` 就該是布林），
#      機械判定會大量誤報 ⇒ 值的型別正確性仍靠 code review 與各 spec。
#   2. **只掃 TARGETS 列的檔**（目前只有 config/limits.yml，即鐵律 6 的唯一上限值來源）。
#      其他 config YAML 要納管，把路徑加進 TARGETS 即可，不必改邏輯。
#   3. **不檢查鍵是否重複**——`{ on: a, "on": b }` 在 YAML 1.1 下是兩個不同的鍵
#      （true 與 "on"），修好本規則後才會合併成重複鍵，那由 YAML 解析器自己的行為決定。
#
# 用法：ruby scripts/check-limits-keys.rb
# 退出碼：0=通過，1=有違規
#
# 相關：CLAUDE.md 鐵律 6（limits.yml 是唯一上限值來源）、config/application.rb 的載入段。

require "yaml"

ROOT = File.expand_path("..", __dir__)

# 納管的 YAML 檔（相對 ROOT）。要加檔案只改這個清單。
TARGETS = %w[
  config/limits.yml
].freeze

# YAML 1.1 會把這些**裸字**解析成非字串。用來在錯誤訊息裡點名根因，
# 而不是只丟一句「鍵不是 String」讓人自己猜。
# 🔴 這張表只用於**產生提示文字**，判定一律以 Psych 實際解析出的型別為準——
#    表漏了哪個字並不會讓違規逃掉（規則 1 檢查的是型別，不是字面）。
YAML11_COERCED_WORDS = {
  "TrueClass"  => %w[on yes y true],
  "FalseClass" => %w[off no n false],
  "NilClass"   => %w[~ null]
}.freeze

violations = []

# 走 Psych AST（不是走 load 出來的 Hash）的理由：AST 的 scalar node 帶 `start_line`，
# 能把違規指到**確切行號**；load 出來的 Hash 只剩值，報不出位置。
# node.to_ruby 是 Psych 的公開 API，回傳該 scalar 實際解析成的 Ruby 物件 ⇒
# 判定用的是解析器真正的行為，而不是我們重寫一份 YAML 1.1 規則。
walk = lambda do |node, rel_path, key_path|
  case node
  when Psych::Nodes::Mapping
    node.children.each_slice(2) do |key_node, value_node|
      resolved = key_node.to_ruby
      label = key_node.respond_to?(:value) ? key_node.value : resolved.inspect

      unless resolved.is_a?(String)
        klass = resolved.class.name
        words = YAML11_COERCED_WORDS[klass]
        hint =
          if words
            "YAML 1.1 把裸字 #{words.join(' / ')} 解析成 #{klass}"
          else
            "YAML 1.1 把這個裸字解析成 #{klass}"
          end

        # start_line 是 0-based。
        location = "#{rel_path}:#{key_node.start_line + 1}"
        full_key = (key_path + [ label ]).join(".")

        violations <<
          "#{location} 鍵 `#{label}`（路徑 #{full_key}）解析結果是 #{klass} 而不是 String——#{hint}。" \
          "修法：**把鍵加引號**寫成 `\"#{label}\":`。" \
          "🔴 不要改成用 #{resolved.inspect} 當鍵——config/application.rb 的 deep_symbolize_keys " \
          "對非字串鍵原樣保留，之後 Rails.configuration.x.limits 那一路 fetch(:#{label}) 會 KeyError。"
      end

      walk.call(value_node, rel_path, key_path + [ label ])
    end
  when Psych::Nodes::Sequence
    node.children.each_with_index { |child, i| walk.call(child, rel_path, key_path + [ i.to_s ]) }
  when Psych::Nodes::Document, Psych::Nodes::Stream
    node.children.each { |child| walk.call(child, rel_path, key_path) }
  end
end

scanned = []

TARGETS.each do |rel|
  path = File.join(ROOT, rel)
  unless File.exist?(path)
    warn "::error::#{rel} 不存在——TARGETS 列了一個不在倉庫裡的檔案，請修正 scripts/check-limits-keys.rb。"
    exit 1
  end

  scanned << rel
  walk.call(Psych.parse_file(path), rel, [])
end

if violations.empty?
  puts "OK：limits.yml 鍵型別檢查通過"
  puts "  - 掃描檔案：#{scanned.join(', ')}"
  puts "  - 所有 mapping 鍵皆解析為 String（不會被 YAML 1.1 轉成布林／nil／Date）"
  puts "  - 不檢查值的型別，理由見檔頭誠實聲明"
  exit 0
end

warn "::error::limits.yml 鍵型別檢查失敗（#{violations.size} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
