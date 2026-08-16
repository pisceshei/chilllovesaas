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
# 🔴 **第二輪突變測試（2026-08-15）：型別字串當 needle 不夠，行號完全沒被守。**
#    上面那三條缺口關掉之後再突變一次，又有三種存活：
#      M9  行號改成 `node.start_line`（少 1，Psych 是 0-based）      → 測試全綠
#      M10 行號固定寫死 `1`                                          → 測試全綠
#      M13 診斷不印 `#{rel}:#{line}` 前綴（只留型別與路徑）          → 測試全綠
#    原因是 needle 只有 `TrueClass`／`Date` 這種型別名，**行號怎麼算都不影響它命中**。
#    而行號正是這支 checker 的實用價值所在——真實 limits.yml 一千多行，
#    報「有一個鍵是 TrueClass」而不指到行，人得自己二分搜尋。
#    ⇒ 五條純型別斷言一律改成 **`config/limits.yml:<行號>` ＋ 型別** 的複合 needle。
#    ⚠️ 行號寫死在下表 ⇒ **改動任一 fixture 的行數就必須同步改這裡**，這是刻意的耦合：
#      fixture 一動，斷言就該重新確認，不該靜默沿用。
CASES = [
  [ "limits_bool_key", 1, "config/limits.yml:8 鍵 `on`",
    "裸字 `on` 鍵被 Psych 解析成 true——config/limits.yml 的 M27–M32 踩過的原形態。" \
    "needle 含行號：見 CASES 上方 M9／M10／M13" ],
  [ "limits_bool_key", 1, "TrueClass",
    "同一 fixture 的型別斷言（與上一條分開列，壞掉時看得出是行號錯還是型別判定錯）" ],
  [ "limits_false_key", 1, "config/limits.yml:13 鍵 `no`",
    "🔴 裸字 `no` ＝ **挪威的 ISO 3166 代碼**，鐵律 11 的法域 pack 最可能踩到的一種" ],
  [ "limits_false_key", 1, "FalseClass",
    "同上，型別分支（FalseClass 與 TrueClass 在 checker 裡是不同的 is_a? 判定）" ],
  [ "limits_nil_key", 1, "config/limits.yml:9 鍵 `~`",
    "裸字 `~` 被解析成 nil——與布林是不同分支，之前完全沒被測到" ],
  [ "limits_nil_key", 1, "NilClass",
    "同上，型別分支" ],
  [ "limits_nil_key", 1, "config/limits.yml:10 鍵 `null`",
    "🔴 fixture 註釋長期斷言「`null:` 同理」卻**只放了 `~`**——未實測的斷言，" \
    "與本倉庫剛被燒過的 y/n 那次同型（規格說會轉，Psych 5 實測不轉）。" \
    "現已實際放進 fixture 並斷言：實測 Ruby 3.4.10 / Psych 5.2.2 下 " \
    "`null` / `Null` / `NULL` / `~` 全部 → NilClass" ],
  [ "limits_nil_key", 1, "config/limits.yml:11 鍵 `NULL`",
    "同上，**大小寫變體**——診斷訊息宣稱「含大小寫變體」，這條讓那句話有測試在守" ],
  [ "limits_nil_key", 1, "config/limits.yml:12 鍵 `Null`",
    "第 7 輪補：fixture 註釋宣稱實測涵蓋 null/Null/NULL/~ 四種，檔內卻只有三種——"     "「宣稱四種、實放三種」與 y/n 假斷言同型，只是規模小。現已補齊第四種" ],
  [ "limits_date_key", 1, "config/limits.yml:6 鍵 `2026-08-15`",
    "看起來像日期的鍵被解析成 Date（生效日／匯率日結那類表會踩到）" ],
  [ "limits_date_key", 1, "Date",
    "同上，型別分支" ],
  [ "limits_seq_key", 1, "config/limits.yml:9 鍵 `on`（路徑 rules.0.on",
    "🔴 布林鍵藏在 **sequence 裡的 mapping**——守的是 Sequence 遞迴分支，" \
    "真實 limits.yml 有 17 處這種結構。" \
    "needle 含**帶索引的路徑**而不只是 `TrueClass`：只斷言型別的話，把走訪從 " \
    "`key_path + [i.to_s]` 改成 `key_path`（診斷退化成 `rules.on`）仍會全綠。" \
    "🔴 尾端刻意不含右括號——`（路徑 rules.0.on` 之後接的是 `）解析結果⋯`，" \
    "多打一個 `）` 會讓這條永遠不命中" ],
  [ "limits_erb", 2, "ERB",
    "🔴 ERB fail-closed（輸出型標籤）：原始檔的 AST 看起來乾淨，loader render 後是 true 鍵" ],
  [ "limits_erb_tag", 2, "含 ERB tag（",
    "🔴 ERB fail-closed（**非輸出型**控制流標籤）：與上一條是不同寫法，" \
    "少了它，把 ERB_TAG 收窄成單一字面值不會被抓到。"     "needle 用 checker 獨有片語「含 ERB tag（」而非裸 `ERB`（第 7 輪 🟡）："     "收窄 ERB_TAG 後這份 fixture 會落到總括 rescue、也是 exit 2，"     "裸 needle 只靠「rescue 訊息恰好不含 ERB 字樣」這條薄邊際分辨，換個措辭就誤判" ],
  [ "limits_missing_target", 2, "TARGETS",
    "🔴 **fail-closed：TARGETS 列的檔不存在時必須 exit 2**。" \
    "本倉庫的 config/limits.yml 一直都在 ⇒ 這個分支在 CI 上永遠走不到，" \
    "把 `unless File.exist?` 整段刪掉、或把 `exit` 改成 `next`，" \
    "在真倉庫上完全看不出差別，而 checker 已退化成「檔案被改名／誤刪也報通過」。" \
    "fixture＝一個**只有 README、沒有 config/limits.yml** 的目錄。" \
    "🔴 **期望碼是 2 不是 1，這是本條能不能守住的關鍵**（PR #40 第 2 輪驗收指出，複驗成立）：" \
    "改成 `next` 之後控制流會落到 scanned.empty? canary，而 canary 的訊息**也含 `TARGETS`**、" \
    "原本也 exit 1 ⇒ 兩條路徑完全無法分辨，該突變存活。" \
    "只改 needle 沒有用（第一句 warn 在 next 之前就印了）⇒ 唯一的解是不同退出碼" ],
  [ "limits_bad_yaml", 2, "Psych::SyntaxError",
    "🔴 **YAML 壞掉也是「檢查跑不了」，必須回 2**（PR #40 第 3 輪驗收指出）。" \
    "沒有 rescue 時 Psych::SyntaxError 直接冒出去，Ruby 以 **exit 1 ＋ backtrace** 結束——" \
    "而 1 的定義是「檢查跑了，發現違規」⇒ **退出碼會說謊**，" \
    "自動化只看碼會把「解析不了」讀成「有鍵型別違規」。" \
    "教訓：退出碼三分一旦立了，就得把**所有非零出口**都歸位" ],
  [ "limits_alias_key", 2, "Psych::AnchorNotDefined",
    "🔴 **第 5 輪照著「例外類別列不完」的懷疑找出來的活缺口**：`*nope: 1`（不存在的錨點當鍵）。" \
    "三件事同時繞過第 4 輪的修法——①`Psych.parse_file` **解析成功**（別名是合法語法）；" \
    "②炸點在 `key_node.to_ruby`，即 `walk` 裡面、第 4 輪那個 rescue 的**外面**；" \
    "③類別是 `Psych::AnchorNotDefined`，不是 `Psych::SyntaxError`。結果是裸 exit 1。" \
    "⇒ 判準因此改成語義的：**checker 自己炸了就是沒檢查完，一律 2**，不再逐一列舉類別。" \
    "needle 用類別名，讓「攔到的是哪一種」也留下紀錄（與 limits_bad_yaml 對照，" \
    "兩份走的是同一個 rescue 但類別不同——這正是「列舉列不完」的證據）" ],
  [ "limits_empty", 3, "0 個 mapping 鍵",
    "🔴 **0 鍵 canary**（第 6 輪驗收指出，實測復現）：canary 原本只數檔案不數鍵，"     "limits.yml 清空成只剩註釋時照樣 exit 0 報通過——而它是鐵律 6 的唯一上限值來源，"     "不可能合法地沒有任何鍵。「沒有違規」與「沒有東西可查」同形態第三次出現"     "（TARGETS 空＝檔案層、本條＝內容層）。與 TARGETS canary 不同，這條 fixture 蓋得到" ],
  [ "limits_bad_encoding", 2, "不是合法的 UTF-8",
    "🔴 第 8 輪：File.read 讀壞位元組不炸、炸在 raw.match?（ArgumentError）——"     "在讀檔 rescue 與總括 rescue **中間**，裸 exit 1。第 5 輪「所有非零出口歸位」"     "的清點漏了「讀進來的東西不合法」這一格 ⇒ 明確驗 valid_encoding?，fail-closed 到 2" ],
  [ "limits_clean", 0, "OK",
    "🔴 反向斷言：乾淨 fixture 必須通過。缺這條，一個永遠 fail 的檢查器會讓上面每一條都「通過」" ]
].freeze

# 🔴 斷言失敗時印**完整輸出**，不是只印第一行（PR #40 第 2 輪驗收指出）。
#    checker 違規輸出的第一行是抬頭（`::error::… 檢查失敗（N 項）：`），
#    行號與型別都在第二行起 ⇒ 行號斷言失配時，只印第一行的訊息會說
#    「輸出不含 config/limits.yml:6」再附上一行看不出實際行號的抬頭，
#    人得自己重跑一次才知道實際報了第幾行。
#    這正是 worklog Pending 5 擔心的「紅得對，但訊息看不出原因」。
indent = ->(text) { text.to_s.lines.map { |l| "        #{l.rstrip}" }.join("\n") }

# 🔴 canary：**本測試自己也會「沒有失敗」與「沒有檢查」長得一模一樣**
#    （PR #40 第 5 輪驗收指出——形態與這支測試剛在 checker 補的那個一模一樣，只是升了一層）。
#    把 `CASES` 清空或砍剩兩條，這支會印「OK：⋯（0 條 / 0 個 fixture）」並 exit 0。
#    上面迴圈裡的 `Dir.exist?` 只守「fixture 目錄被刪」，**守不住「case 被刪」**。
#    ⚠️ 而這條退化路徑是**現實的**，不是理論：`CASES` 的行號與 fixture 行數是硬耦合
#    （Pending 5／7 自承），改 fixture 就得手改斷言 —— 被嫌煩時最省事的做法就是刪 case。
#    🔴 數字只准往上調。要調低必須在 PR 描述說明刪了哪一條、為什麼那條不再需要。
MIN_CASES = 20
if CASES.size < MIN_CASES
  warn "::error::CASES 只剩 #{CASES.size} 條（下限 #{MIN_CASES}）——這不是通過，是檢查被砍掉了。" \
       "若確實要移除某條，請一併調低 MIN_CASES 並在 PR 描述說明理由。"
  exit 1
end

# 🔴 第 7 輪補的兩條結構斷言（🟡：MIN_CASES 只擋條數，18 條全複製 limits_clean 也會過）：
#    ①fixture 種類數也有下限——複製貼上撐條數會被抓；
#    ②**四種退出碼都必須各有 case**——把某一類全刪（例如所有 exit 2 的 fail-closed），
#      條數可能仍夠，但整個失敗類別從測試裡消失了。
if CASES.map(&:first).uniq.size < 12
  warn "::error::CASES 只覆蓋 #{CASES.map(&:first).uniq.size} 個 fixture（下限 12）——條數夠但種類被砍了。"
  exit 1
end
unless CASES.map { |c| c[1] }.uniq.sort == [ 0, 1, 2, 3 ]
  warn "::error::CASES 的期望退出碼只剩 #{CASES.map { |c| c[1] }.uniq.sort.inspect}——"        "四種碼（0 通過／1 違規／2 跑不了／3 沒生效）必須各有至少一條 case 在守。"
  exit 1
end

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
    failures << "#{dir}：期望 exit #{want_status}，實得 #{status}（#{why}）\n      完整輸出：\n#{indent.call(output)}"
    next
  end

  next if output.include?(want_output)

  failures << "#{dir}：exit code 對，但輸出不含 `#{want_output}`（#{why}）\n      完整輸出：\n#{indent.call(output)}"
end

if failures.empty?
  puts "OK：limits 鍵型別檢查器的回歸測試通過（#{CASES.size} 條 / #{CASES.map(&:first).uniq.size} 個 fixture）"
  # 🔴 印出 needle：同一個 fixture 現在有多條斷言（行號一條、型別一條），
  #    只印 fixture 名的話兩行長得一模一樣，看不出是哪一條在守什麼。
  CASES.each { |dir, want_status, needle, why| puts "  - #{dir} → exit #{want_status}，含 `#{needle}`：#{why}" }
  exit 0
end

warn "::error::limits 鍵型別檢查器的回歸測試失敗（#{failures.size}/#{CASES.size}）："
failures.each { |f| warn "  - #{f}" }
warn "  🔴 這代表 scripts/check-limits-keys.rb 的判定邏輯壞了，或 fixture 被改動。"
exit 1
