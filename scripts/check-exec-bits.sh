#!/usr/bin/env bash
# 執行位元閘門——`bin/` 全部、`scripts/` 帶 shebang 者，git mode 必須是 100755。
#
# ## 為什麼存在
#
# Windows 上 git 預設 `core.filemode=false`，新增檔案會以 `100644` 提交，
# 本機完全正常，到 Linux runner 上執行就是 `exit 126: Permission denied`——
# 錯誤訊息完全看不出根因。2026-08-14 的 CI 全紅就是這個原因。
#
# 判準是「**帶 shebang 就必須可執行**」：帶 shebang 是檔案自己宣告「我可以直接跑」，
# 宣告了卻沒有執行位元就是自相矛盾。無 shebang 的資料檔／fixture 不受約束。
#
# ## 為什麼從 ci.yml 抽成獨立腳本（2026-08-15）
#
# 原本這段是直接寫在 `.github/workflows/ci.yml` 裡的 inline shell，**兩個 job 各一份**。
# 三個後果，全部實測過：
#   1. `bin/ci` 跑不到它 ⇒ 本機全綠但 CI 會紅（`config/ci.rb` 的同步條款管不到 inline shell，
#      `scripts/check-ci-parity.rb` 也看不到它——那是它誠實聲明裡登記的已知缺口）。
#   2. **沒有辦法寫回歸測試**（65 §K.7：檢查本身也要被測試）——它是全 ci.yml 唯一
#      判準被大改卻沒有反向自測的檢查。抽出來之後才有 `scripts/test-exec-bits-rules.sh`。
#   3. 兩份 inline 複製容易分岔（改一份忘了另一份）。現在兩個 job 都呼叫同一支。
#
# ## 🔴 三個實測踩過的坑（不要改回去）
#
# **① `-z`（NUL 分隔）不是可有可無。**
#    `git ls-files -s` 預設 `core.quotePath=true` ⇒ 含非 ASCII 的路徑會被**加引號並跳脫**
#    成 `"scripts/\346\252\242\346\237\245.rb"`。用一般讀法拿到的是那串跳脫字串，
#    `head` 開檔失敗 ⇒ 條件為假 ⇒ **該檔靜默漏掉**，而閘門還會印「OK：全部可執行」。
#    實測：`scripts/檢查.rb`（100644 ＋ shebang）在舊寫法下完全不會被抓到。
#    `-z` 輸出的是**原始未跳脫路徑**，這是唯一對任何檔名都正確的讀法
#    （含空白的檔名舊寫法用 `-F'\t'` 已修好，但非 ASCII 那一類沒有）。
#
# **② 掃到 0 個檔必須 fail，不能印 OK——而且要「逐 pathspec」判，不是判總和。**
#    若 pathspec 匹配不到任何東西（跑錯目錄、不是 git repo、目錄改名），
#    `bad` 會是空的 ⇒ 舊寫法印「OK：全部可執行」且 exit 0。
#    **那是「空值長得像資料」**：一個什麼都沒掃的檢查，看起來與全部通過一模一樣。
#    🔴 **初版的 canary 只判總和，所以只擋住「兩邊同時為 0」這一個特例**
#       （PR #41 的 Claude 驗收指出，已實測重現）：只要 `bin/` 有檔，
#       `scripts/` 掃到 0 個也不會響，而成功訊息照樣逐字宣告「scripts/ 帶 shebang 者
#       全部可執行」——它一個 scripts/ 檔都沒看過。把 `scripts/` 改名或搬走，
#       這道閘門對那十幾支腳本靜默失效，輸出與全綠一模一樣。
#       ⇒ 現在**兩個 pathspec 各自計數、任一為 0 即 fail**，並指出是哪一個。
#
# **③ shebang 要從 index 讀，不是從工作區讀。**
#    本檢查判的是 `git ls-files -s` 的 mode——那是 **index** 的狀態。
#    shebang 若從工作區讀，`git add x && git update-index --chmod=-x x`
#    再把工作區的 shebang 刪掉，就會騙過它（PR #41 的 Codex review 指出）。
#    ⇒ 用 `git show ":$path"` 讀 index 的內容，與 mode 同源。
#
# 用法：scripts/check-exec-bits.sh [ROOT]
#   ROOT 省略時＝本倉庫根目錄。傳入時檢查該目錄——給 test-exec-bits-rules.sh 用。
# 退出碼：0=通過，1=有違規或掃不到東西
#
# 相關：AGENTS.md「Windows 開發者必讀：檔案執行位元」節（規則須與本檔同步）。

set -uo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "::error::進不去 $ROOT"; exit 1; }

bad=""
# 🔴 **逐 pathspec 計數，不得合併成一個 `scanned`**（見檔頭坑②）。
#    合成總和之後，「只有一邊掃到 0」就不會被發現，而成功訊息照樣宣告兩邊都通過。
bin_scanned=0
scripts_scanned=0

# bin/：該目錄下**所有**檔案都必須可執行（裡面本來就只放可執行檔，維持較嚴的判準）。
while IFS= read -r -d '' rec; do
  bin_scanned=$((bin_scanned + 1))
  mode="${rec%% *}"
  path="${rec#*$'\t'}"
  [ "$mode" = "100755" ] || bad="${bad}${path}"$'\n'
done < <(git ls-files -sz bin/ 2>/dev/null)

# scripts/：只有**帶 shebang** 的檔案受約束。
while IFS= read -r -d '' rec; do
  scripts_scanned=$((scripts_scanned + 1))
  mode="${rec%% *}"
  path="${rec#*$'\t'}"
  [ "$mode" = "100755" ] && continue
  # 🔴 **從 index 讀，不是從工作區讀**（PR #41 的 Codex review 指出，已實測）。
  #    本檢查判的是 `git ls-files -s` 的 mode——那是 **index** 的狀態；
  #    若 shebang 也從 index 讀才前後一致。從工作區讀會被**部分暫存**騙過：
  #      git add scripts/x.sh          # index：有 shebang
  #      git update-index --chmod=-x … # index：100644
  #      （接著把工作區的 shebang 刪掉）
  #    ⇒ 工作區沒 shebang ⇒ 條件為假 ⇒ 印「OK」exit 0，
  #      而**即將提交的內容**是一支帶 shebang 的 100644 腳本。實測重現過。
  #    `git show :"$path"` 取的就是 index 版本，且對含空白／非 ASCII 的路徑同樣正確。
  if [ "$(git show ":$path" 2>/dev/null | head -c 2)" = '#!' ]; then
    bad="${bad}${path}"$'\n'
  fi
done < <(git ls-files -sz scripts/ 2>/dev/null)

# 🔴 canary：見檔頭坑②。**逐 pathspec 判**——任一邊掃到 0 個，
#    就代表下面那句「⋯全部可執行」對那一半是空話，必須說出來。
empty_specs=""
[ "$bin_scanned" -eq 0 ] && empty_specs="${empty_specs}bin/ "
[ "$scripts_scanned" -eq 0 ] && empty_specs="${empty_specs}scripts/ "
if [ -n "$empty_specs" ]; then
  echo "::error::執行位元閘門有 pathspec **一個檔都沒掃到**：${empty_specs}"
  echo "  這不是「通過」，是檢查對那一半沒有生效——常見原因：跑錯目錄、不是 git repo、目錄被改名。"
  echo "  實得：bin/ ${bin_scanned} 個、scripts/ ${scripts_scanned} 個"
  echo "  ROOT=$ROOT"
  exit 1
fi

if [ -n "$bad" ]; then
  echo "::error::以下檔案缺少執行位元（git mode 應為 100755）："
  printf '%s' "$bad" | sed 's/^/  /'
  echo "  修法：git update-index --chmod=+x <上列檔案>"
  exit 1
fi

# 🔴 成功訊息**逐 pathspec 報數**：宣告「全部可執行」的同時要說出各自看了幾個檔，
#    否則「掃了 0 個」與「全部通過」在訊息上分不出來（那正是坑②的形態）。
echo "OK：執行位元閘門通過（bin/ ${bin_scanned} 個、scripts/ ${scripts_scanned} 個）"
echo "  - bin/ 全部可執行；scripts/ 帶 shebang 者全部可執行"
echo "  - 用 git ls-files -z 讀路徑，含空白與非 ASCII 的檔名都不會被跳過"
exit 0
