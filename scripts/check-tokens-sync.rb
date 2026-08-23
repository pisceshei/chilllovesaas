#!/usr/bin/env ruby
# frozen_string_literal: true

# Design token 同源檢查——把鐵律 8「UI 值一律取自 tokens，不自創色值與尺寸」
# 從紀律變成機制。
#
# 背景：token 值曾同時存在**三份拷貝**（原型 `:root`、`docs/design/23` §1 的
# 程式碼區塊、`app/assets/tokens.css`），而三份已經漂移——23 §1 與 tokens.css
# 停在 2026-07 的估計值（`--bg:#f4f4f5`、`--focus:#2a78d6`），原型則已換成
# 研究 47／64 的**實測值**（`#f1f1f1`／`#005bd3`）並多出間距、字級、導航、
# 語意 5×5×3 等百餘顆。三份都自稱權威，讀哪一份決定你寫出哪一版 UI。
#
#   🔴 唯一 producer ＝ **原型 `docs/design/chilllove-admin-v2.html` 的 `:root` 區塊**。
#      實作端 `app/assets/tokens.css` 是它的機械副本（`scripts/sync-tokens.rb` 產生）；
#      `docs/design/23` §1 改為指標（2026-08-23 裁定，理由見該節的 dated 註）。
#
# 本腳本檢查兩件事：
#
#   規則 1｜`app/assets/tokens.css` 的 `:root` 區塊必須**逐位元組等於**原型的。
#     不比對「有沒有同名 token」而是比對整段文字——同名不同值正是漂移的形態，
#     只查名字的檢查會對 `#f4f4f5` vs `#f1f1f1` 全綠。
#
#   規則 2｜`docs/design/23` §1 不得復活第三份拷貝——判準是**有沒有一行以該選擇器起頭**
#     （去掉前導空白後），也就是有沒有真的貼進一段 CSS 宣告。
#     🔴 判準刻意不是「全文出現過這個字串」：該節的散文**必須**能引用這個選擇器來
#     說明規則本身，於是寫下規則的那句話會讓「全文不得出現」永遠為假——本檔第一版
#     就是這樣自我推翻的（實跑時被自己的說明文字判紅）。
#
# 不檢查什麼（誠實聲明）：不驗證實作端 CSS 的其餘部分是否只用 token 而不用裸值——
# 原型端的裸值規則在 `scripts/lint-prototype.py`，實作端尚未機械化（登記 docs/specs/91）。
#
# 用法：ruby scripts/check-tokens-sync.rb
# 退出碼：0=通過，1=有漂移，2=取證失敗（檔案或區塊不存在）

require_relative "lib/token_block"

SPEC23 = File.join(TokenBlock::ROOT, "docs", "design", "23-interaction-css-spec.md")

prototype_block = TokenBlock.extract_from_file(TokenBlock::PROTOTYPE)
tokens_block = TokenBlock.extract_from_file(TokenBlock::TOKENS)

violations = []

if tokens_block != prototype_block
  proto_lines = prototype_block.lines
  token_lines = tokens_block.lines
  differing = []
  [proto_lines.length, token_lines.length].max.times do |index|
    left = proto_lines[index]
    right = token_lines[index]
    differing << [index + 1, left, right] if left != right
  end
  detail = differing.first(5).map do |line_number, left, right|
    "  第 #{line_number} 行\n    原型  ：#{left.to_s.chomp.inspect}\n    tokens：#{right.to_s.chomp.inspect}"
  end.join("\n")
  violations << "app/assets/tokens.css 的 `:root` 區塊與原型不同步（共 #{differing.length} 行不同；" \
                "原型 #{proto_lines.length} 行／tokens #{token_lines.length} 行）。前 5 處：\n" \
                "#{detail}\n  修法：ruby scripts/sync-tokens.rb"
end

unless File.file?(SPEC23)
  warn "EVIDENCE_NOT_OBTAINED: 找不到 docs/design/23-interaction-css-spec.md"
  exit 2
end

pasted = File.readlines(SPEC23).each_with_index.select { |line, _| line.lstrip.start_with?(":root{") }
if pasted.any?
  where = pasted.map { |_, index| "第 #{index + 1} 行" }.join("、")
  violations << "docs/design/23-interaction-css-spec.md 有 CSS 宣告行復活了第三份 token 拷貝（#{where}）。\n" \
                "  2026-08-23 裁定：該節只放指標，值的唯一 producer 是原型的 root 區塊。\n" \
                "  三份拷貝曾經漂移（23 §1 與 tokens.css 停在估計值、原型是實測值），\n" \
                "  而三份都自稱權威 ⇒ 讀哪一份決定你寫出哪一版 UI。"
end

if violations.empty?
  puts "tokens 同源檢查通過（#{prototype_block.lines.length} 行逐位元組相同）。"
  exit 0
end

violations.each { |message| warn "::error::#{message}" }
exit 1
