#!/usr/bin/env ruby
# frozen_string_literal: true

# 字級與行高 token 的 rem 完整性檢查——D68（2026-08-28 使用者裁定）的 B 道驗收。
#
# 背景：`--t-*`／`--lh-*` 兩族由 px 改 rem（本尊同形：`--p-font-size-325 = .8125rem`，
# 取證見 docs/DECISIONS.md D63／D68）。這個轉換在預設 16px 下**恆等**
# （`.8125rem × 16 = 13px`）⇒ 既有的「前後逐元素比對」驗收法對它**驗不出對錯**。
# D68 的擾動法（root ×2 量比值）只覆蓋「剛好有元素在用」的 token；
# 本腳本是**唯一對 token 表完整**的那一道：兩族的每一顆都必須是 rem。
#
#   規則 1｜producer（原型 `:root`）內每一顆 `--t-<數字>`／`--lh-<數字>` 的值
#     必須匹配 `^-?\.?\d*\.?\d+rem$`（即 `1rem`／`.75rem`／`0.6875rem` 形態）。
#     px、em、無單位、calc() 一律違規——這兩族的語義就是「隨 root 字級縮放的長度」。
#     🔴 只掃**數字後綴**的 token 名：`--t-sm`／`--t-md` 這類**別名**刻意不在射程
#     （它們的值是 `var(--t-325)`，單位由被指向者決定；把別名也框進來的話，
#     規則會誤傷所有間接層）。
#
#   規則 2｜零掃描 canary：兩族**各自**必須至少找到一顆。
#     「沒有違規」與「沒有東西可查」不是同一件事——token 全被改名、區塊被
#     搬走、regex 打錯，三種情況都會讓規則 1 空轉全綠（zero-expectation canary，
#     前例＝check-limits-keys 的 limits_empty 事故）。找不到 ⇒ exit 2。
#
# 不檢查什麼（誠實聲明）：
#   - `--sp-`／`--r-`／`--h-`／`--sz-` 維持 px 是**現行裁定**（docs/specs/91 §3.42 W-1
#     登記待另案）⇒ 不掃。日後那個裁定落地時把家族清單加進 FAMILIES 即可。
#   - 消費端硬編 px（元件規則裡直接寫 `font-size: 13px`）本腳本看不到——
#     那要靠擾動法（91 §3.42 W-3，尚未機械化）。
#   - `app/assets/tokens.css` 不另掃：它與 producer 逐位元組同源，
#     由 `scripts/check-tokens-sync.rb` 守；再掃一次是第二份判準。
#
# 用法：ruby scripts/check-rem-tokens.rb [producer檔路徑]
#   （路徑參數供回歸測試注入 fixture；不給則用真 producer）
# 退出碼：0=通過，1=有違規，2=取證失敗（檔案／區塊不存在、兩族任一為空）

require_relative "lib/token_block"

producer = ARGV[0] ? File.expand_path(ARGV[0]) : TokenBlock::PROTOTYPE
block = TokenBlock.extract_from_file(producer)

# 🔴 掃描前先剝 CSS 註釋。D68 實測事故：註釋裡寫「--t-*/--lh-*」，`*/` 提早終結
# 註釋、殘骸吞掉緊鄰宣告（91 §3.42 W-2）。不剝註釋的話，說明文字裡引用的
# token 名（例如本註釋自己）會被當成宣告掃出假結果——lint-prototype 的
# r_px_breakpoint 就是這樣產生假陽性的（91 §3.37 W-1）。
scannable = block.gsub(%r{/\*.*?\*/}m, " ")

FAMILIES = { "--t-" => /--t-(\d+)\s*:\s*([^;]+);/, "--lh-" => /--lh-(\d+)\s*:\s*([^;]+);/ }.freeze
REM = /\A-?\d*\.?\d+rem\z/

violations = []
counts = {}

FAMILIES.each do |family, pattern|
  found = scannable.scan(pattern)
  counts[family] = found.length
  found.each do |num, raw|
    value = raw.strip
    next if value.match?(REM)

    violations << "`#{family}#{num}` 的值是 `#{value}`——這兩族必須是 rem（D68；" \
                  "本尊同形 `--p-font-size-325 = .8125rem`）。px 在使用者調大瀏覽器" \
                  "預設字級時不縮放，恆等於放棄該顆的無障礙行為。"
  end
end

empty = counts.select { |_, n| n.zero? }.keys
unless empty.empty?
  warn "EVIDENCE_NOT_OBTAINED: #{empty.join('、')} 家族在 producer 的 `:root` 掃到 0 顆——" \
       "「沒有違規」與「沒有東西可查」不是同一件事（token 改名／區塊搬走／regex 失配" \
       "三種情況在這裡同形）。producer＝#{producer}"
  exit 2
end

if violations.empty?
  puts "OK：rem 完整性通過（#{counts.map { |f, n| "#{f}* #{n} 顆" }.join('、')}，全部 rem）"
  exit 0
end

warn "::error::rem token 完整性檢查失敗（#{violations.length} 項）："
violations.each { |v| warn "  - #{v}" }
exit 1
