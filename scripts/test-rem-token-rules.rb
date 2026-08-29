#!/usr/bin/env ruby
# frozen_string_literal: true

# `scripts/check-rem-tokens.rb` 的回歸測試（fixture 驅動）。
#
# 65 §K 第 7 條：檢查本身也要被測試——一條永遠不會紅的 CI 規則等於沒有。
# 形態比照 `scripts/test-limits-key-rules.rb`（fixture 目錄 ＋ 期望退出碼 ＋ needle）。
#
# 🔴 這張表在寫完 checker 後做過一輪手動突變（2026-08-28，D69）：
#   M1 REM regex 改成 /rem/（子字串匹配，`13pxrem` 也過）→ 被 px_size 的
#      needle 抓到？**不會**——13px 不含 rem 仍紅。改抓法：把 `next if` 反轉
#      成 `next unless` → clean fixture 轉紅 ⇒ 反向斷言（clean=0）殺掉它。
#   M2 拿掉零掃描 canary（`unless empty.empty?` 整段刪）→ family_empty 從 2
#      變 0 報通過 ⇒ family_empty 的期望碼 2 殺掉它。
#   M3 FAMILIES 的 `--lh-` 那條刪掉 → family_empty 反而還是 2（--lh- 掃 0 顆
#      的訊息換人出）……**存活**！⇒ 補 needle：family_empty 斷言訊息裡
#      **精確指名 `--lh-`**；並補 px_lineheight（lh 族的違規必須被抓）——
#      M3 下它會退化成 exit 0，期望碼 1 殺掉它。
#   M4 剝註釋那行刪掉 → comment_masked 把註釋裡的 `--t-999:13px` 當宣告
#      掃出來、exit 從 0 變 1 ⇒ comment_masked 的期望碼 0 殺掉它。
#   M5 exit 2 改 exit 0（取證失敗當通過）→ no_root 從 2 變 0 ⇒ 期望碼 2 殺掉。
#
# 用法：ruby scripts/test-rem-token-rules.rb
# 退出碼：0=全過，1=有失敗

require "open3"

ROOT = File.expand_path("..", __dir__)
CHECKER = File.join(ROOT, "scripts/check-rem-tokens.rb")
FIXTURES = File.join(ROOT, "spec/fixtures/rem_tokens")

# (fixture 檔, 期望 exit code, 輸出須包含的字串, 這條在防什麼)
CASES = [
  [ "clean.html", 0, "OK",
    "🔴 反向斷言：乾淨 fixture（rem 全對、含別名與 px 的其他家族）必須通過。" \
    "缺這條，永遠 fail 的檢查器會讓下面每一條都「通過」；也是突變 M1（判定反轉）的唯一殺手" ],
  [ "clean.html", 0, "--t-* 3 顆",
    "OK 訊息必須帶掃到的顆數——顆數是人肉核對「掃描真的發生了」的唯一線索" ],
  [ "px_size.html", 1, "`--t-325` 的值是 `13px`",
    "字級族的 px 違規：needle 帶 token 名與原值，壞掉時看得出抓的是哪顆" ],
  [ "px_lineheight.html", 1, "`--lh-400` 的值是 `16px`",
    "🔴 行高族的 px 違規**單獨列**：突變 M3（FAMILIES 刪掉 --lh- 那條）下" \
    "字級族照掃、本 fixture 退化成 exit 0——只有它殺得掉 M3 的違規半邊" ],
  [ "em_value.html", 1, "`--t-325` 的值是 `.8125em`",
    "em 也違規：em 隨父層字級不是 root 字級，兩族的語義是後者。" \
    "regex 若寫成寬鬆的 /em$/ 子字串匹配，rem 也以 em 結尾 ⇒ 這條與 clean 互為夾擊" ],
  [ "family_empty.html", 2, "--lh-",
    "🔴 零掃描 canary：fixture 只有 --t- 沒有 --lh-，必須 exit 2 且訊息**指名 --lh-**。" \
    "期望碼 2 殺突變 M2（canary 整段刪）；needle 指名家族殺 M3 的空轉半邊" \
    "（M3 下若仍回 2，訊息裡的家族名就會對不上）" ],
  [ "comment_masked.html", 0, "OK",
    "🔴 註釋裡引用 `--t-999:13px` 字樣不得被當成宣告（D68 的 */ 事故同根：" \
    "說明文字與宣告同形）。突變 M4（剝註釋那行刪掉）下本 fixture 轉紅" ],
  [ "no_root.html", 2, "EVIDENCE_NOT_OBTAINED",
    "🔴 fail-closed：檔案裡沒有 `:root` 區塊＝取證失敗（exit 2），不是通過。" \
    "TokenBlock.extract_from_file 對「檔在但區塊不在」回 nil ⇒ 本 fixture 守的是" \
    "那條路徑不會靜默變 0" ]
].freeze

failures = []

CASES.each do |fixture, want_exit, needle, why|
  path = File.join(FIXTURES, fixture)
  unless File.file?(path)
    failures << "fixture 不存在：#{fixture}（#{why}）"
    next
  end

  out, err, status = Open3.capture3(RbConfig.ruby, CHECKER, path)
  combined = out + err

  unless status.exitstatus == want_exit
    failures << "#{fixture}：期望 exit #{want_exit}、實得 #{status.exitstatus}。防的是：#{why}\n" \
                "──完整輸出──\n#{combined}"
    next
  end

  unless combined.include?(needle)
    failures << "#{fixture}：exit 碼對（#{want_exit}）但輸出不含 `#{needle}`。防的是：#{why}\n" \
                "──完整輸出──\n#{combined}"
  end
end

# 🔴 真 producer 必須通過——這不是重複 CI 裡的那步，而是本測試自己的完整性：
# fixture 全綠但真 producer 紅，代表 fixture 的形態已偏離真實檔案（例如真檔
# 改用了 fixture 沒覆蓋的寫法），此時該紅的是這裡，不是等 CI 才發現。
out, err, status = Open3.capture3(RbConfig.ruby, CHECKER)
unless status.exitstatus.zero?
  failures << "真 producer 未通過（exit #{status.exitstatus}）：\n#{out}#{err}"
end

if failures.empty?
  puts "OK：rem token 規則回歸 #{CASES.length} 格全過（＋真 producer 通過）"
  exit 0
end

warn "::error::rem token 規則回歸失敗（#{failures.length} 項）："
failures.each { |f| warn "  - #{f}" }
exit 1
