#!/usr/bin/env ruby
# frozen_string_literal: true

# 把原型的 `:root` token 區塊機械複製到 `app/assets/tokens.css`。
#
# 這是 `scripts/check-tokens-sync.rb` 的修法端：檢查腳本只說「不同步」，
# 由本腳本執行同步，**人不手抄**——手抄正是漂移的來源。
#
# 用法：ruby scripts/sync-tokens.rb
# 退出碼：0=已同步（有無改動都算成功），2=取證失敗

require_relative "lib/token_block"

prototype_block = TokenBlock.extract_from_file(TokenBlock::PROTOTYPE)
header = <<~HEADER
  /* 🔴 本檔是機械副本，**不要手改**。
     唯一 producer ＝ docs/design/chilllove-admin-v2.html 的 `:root` 區塊。
     同步：ruby scripts/sync-tokens.rb　／　檢查：ruby scripts/check-tokens-sync.rb
     為什麼不手改：值曾有三份拷貝並已漂移（23 §1 與本檔停在 2026-07 估計值、
     原型已換成研究 47／64 實測值），三份都自稱權威。見 docs/design/23 §1 的 dated 註。 */
HEADER

# binwrite 而非 write：理由見 TokenBlock.extract_from_file 的行尾註釋。
File.binwrite(TokenBlock::TOKENS, header + prototype_block + "\n")
puts "已同步 #{prototype_block.lines.length} 行 token 到 app/assets/tokens.css。"
