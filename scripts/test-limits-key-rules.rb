#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-limits-keys.rb` 的回歸測試（fixture 驅動）。
#
# ## 🔴 為什麼「檢查腳本自己綠」不算交付
#
# `docs/specs/65` §K 第 7 條要求「各有一個『故意違反』的 fixture，證明檢查真的會 fail」，
# 括號內逐字是：**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有。
# <!-- 🔴 2026-08-15 更正：本段初稿寫「§K.7 判準逐字是『只有前者綠不算交付』」，
#      那句話**不在 65 號裡**（`git grep` 零命中），是 PR #29 的轉述被我當成原文再加上「逐字」。
#      語義沒錯，但「逐字」是一行 grep 就能證偽的斷言——與本 PR 修的 y/n 假斷言同型。
#      main 上另有兩處同語病（scripts/test-money-rules.rb、ci.yml 的 money 段），
#      不在本 PR 範圍，已在 PR #33 描述登記待清。 -->
#
# 一個什麼都不檢查的腳本在乾淨倉庫上也是綠的。
# 要證明它有效，唯一的方法是**讓每一條規則各自被一個故意違反的 fixture 打紅**，
# 再加一條**反向斷言**（乾淨 fixture 必須 exit 0），
# 否則一個「永遠 fail」的檢查器會讓上面每一條都「通過」。
#
# 形態比照 `scripts/test-money-rules.rb` 與 `scripts/test-lint-rules.py`。
#
# ## 本測試存在的直接理由（2026-08-15）
#
# `check-limits-keys.rb` 送審時**沒有**回歸測試，PR #33 的兩個驗收方都指出了這件事，
# 而當時的理由是「既有兩支 check-*.rb 都沒有，比照辦理」——那個理由**已經不成立**：
# main 隨 PR #29 進來了 `scripts/test-money-rules.rb`，把「檢查器要有反向證明」
# 立成了專案慣例。
#
# 🔴 這支測試守的是一個**看不見的失效**：判定邏輯只要被改成
# `resolved.is_a?(String)` 的反面、或 `unless` 寫成 `if`，
# `check-limits-keys.rb` 在乾淨倉庫上**仍然 exit 0**，CI 全綠，
# 而它已經什麼都不擋了。
#
# 用法：ruby scripts/test-limits-key-rules.rb
# 退出碼：0=全過，1=有失敗

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-limits-keys.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/ci_violations")

# (fixture 目錄, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
#
# 🔴 **這張表是被突變測試打出來的**（2026-08-15）。初版只有三條，
#    而把 check-limits-keys.rb 改壞成六種形態後實測，**三種存活**：
#      M2 只認 TrueClass（放行 FalseClass／NilClass／Date） → 測試全綠
#      M3 刪掉 Sequence 遞迴（陣列裡的鍵不掃）             → 測試全綠
#      M4 ERB 閘門收窄成只認某一個字面                      → 測試全綠
#    也就是說：checker 實際擋得住的東西，有一大半**沒有任何測試在守**，
#    改壞了不會有人知道。下面五條就是為了把那三個缺口關掉。
#    ⇒ 加新規則到 checker 時，**先想「改壞它的哪一種寫法不會被抓」**，
#      那個答案就是你要補的 fixture。
CASES = [
  [ "limits_bool_key", 1, "TrueClass",
    "裸字 `on` 鍵被 Psych 解析成 true——config/limits.yml 的 M27–M32 踩過的原形態" ],
  [ "limits_false_key", 1, "FalseClass",
    "🔴 裸字 `no` ＝ **挪威的 ISO 3166 代碼**，鐵律 11 的法域 pack 最可能踩到的一種" ],
  [ "limits_nil_key", 1, "NilClass",
    "裸字 `~` 被解析成 nil——與布林是不同分支，之前完全沒被測到" ],
  [ "limits_date_key", 1, "Date",
    "看起來像日期的鍵被解析成 Date（生效日／匯率日結那類表會踩到）" ],
  [ "limits_seq_key", 1, "rules.0.on",
    "🔴 布林鍵藏在 **sequence 裡的 mapping**——守的是 Sequence 遞迴分支，" \
    "真實 limits.yml 有 17 處這種結構。" \
    "斷言用**帶索引的路徑**而不是 `TrueClass`：只斷言型別的話，把走訪從 " \
    "`key_path + [i.to_s]` 改成 `key_path`（診斷退化成 `rules.on`）仍會全綠" ],
  [ "limits_erb", 1, "ERB",
    "🔴 ERB fail-closed（輸出型標籤）：原始檔的 AST 看起來乾淨，loader render 後是 true 鍵" ],
  [ "limits_erb_tag", 1, "ERB",
    "🔴 ERB fail-closed（**非輸出型**控制流標籤）：與上一條是不同寫法，" \
    "少了它，把 ERB_TAG 收窄成單一字面值不會被抓到" ],
  [ "limits_clean", 0, "OK",
    "🔴 反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓上面每一條都「通過」" ]
].freeze

failures = []

CASES.each do |dir, want_status, want_output, why|
  path = File.join(FIXTURES, dir)
  unless Dir.exist?(path)
    failures << "#{dir}：fixture 目錄不存在（#{why}）"
    next
  end

  output = `ruby "#{CHECKER}" "#{path}" 2>&1`
  status = $?.exitstatus

  if status != want_status
    failures << "#{dir}：期望 exit #{want_status}，實得 #{status}（#{why}）\n      輸出：#{output.lines.first.to_s.strip}"
    next
  end

  next if output.include?(want_output)

  failures << "#{dir}：exit code 對，但輸出不含 `#{want_output}`（#{why}）\n      輸出：#{output.lines.first.to_s.strip}"
end

if failures.empty?
  puts "OK：limits 鍵型別檢查器的回歸測試通過（#{CASES.size} 條）"
  CASES.each { |dir, want_status, _, why| puts "  - #{dir} → exit #{want_status}：#{why}" }
  exit 0
end

warn "::error::limits 鍵型別檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-limits-keys.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
