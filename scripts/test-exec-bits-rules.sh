#!/usr/bin/env bash
# `scripts/check-exec-bits.sh` 的回歸測試（fixture 驅動）。
#
# 65 §K.7 逐字：「**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有」。
#
# ## 為什麼 fixture 是「跑時現建」而不是版控裡的目錄
#
# 這個檢查讀的是 **git index 的 mode**（`git ls-files -s`），不是檔案系統權限
# ⇒ fixture 必須是**真的 git repo**。巢狀 `.git` 沒辦法提交進本倉庫，
# 所以每個 case 在 `$TMPDIR` 現場建一個小 repo。代價是慢一點（**11 個 repo**），
# 好處是 fixture 與判準永遠不會不同步。
#
# ## 🔴 這 11 條各自守什麼（改條數時**這裡、ci.yml、AGENTS.md、docs/dev 四處要一起改**）
#
# **判準本身（正反向）**
#   1. `clean`        全部 755 ⇒ exit 0（🔴 反向斷言，沒它的話一個「永遠 fail」的檢查器會讓每條都「通過」）
#   2. `ascii`        帶 shebang 卻 100644 ⇒ exit 1
#   3. `no_shebang`   無 shebang 的資料檔不受約束 ⇒ exit 0（判準寫成「scripts/ 下全部」會誤傷）
#
# **實測抓到的漏洞（不是想像出來的）**
#   4. `spaced`       含空白檔名：PR #35 的 Codex review（`awk '{print $4}'` 以空白切欄會截斷）
#   5. `non_ascii`    非 ASCII 檔名：Y4（`core.quotePath` 加引號跳脫 ⇒ head 開不了 ⇒ 靜默漏掉）
#   6. `staged_only`  部分暫存：PR #41 的 Codex review（shebang 從工作區讀會放行即將提交的違規）
#
# **`bin/` 那一半的契約**（PR #41 的 Codex review：初版完全沒測）
#   7. `bin_bad`      bin/ 的檔缺執行位元 ⇒ exit 1
#   8. `bin_ok`       bin/ 全部 755 ⇒ exit 0（避免把 bin/ 規則寫成永遠紅）
#
# **「什麼都沒掃到」的三種形態**（Y5 及其補完）
#   9. `only_bin`     🔴 scripts/ 掃到 0 個 ⇒ exit 1（PR #41 的 Claude 驗收：canary 判總和時的盲區）
#  10. `only_scripts` 🔴 反方向：bin/ 掃到 0 個 ⇒ exit 1
#  11. `empty`        兩邊都掃不到 ⇒ exit 1（Y5 原形態）
#
# 用法：scripts/test-exec-bits-rules.sh
# 退出碼：0=全過，1=有失敗

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT/scripts/check-exec-bits.sh"
WORK="$(mktemp -d)"
# 🔴 mktemp 失敗時 WORK 是空字串（set -u 攔不住「有設但空」）⇒ 後面的
#    mkdir -p "$WORK/$name" 會在檔案系統根建目錄、trap 清理對空字串也無效。
[ -n "$WORK" ] && [ -d "$WORK" ] || { echo "mktemp -d 失敗" >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

failures=0
passes=0

# 建一個小 git repo。$1=名稱，其餘由 caller 在 $repo 裡佈置。
#
# 🔴 **預設兩個目錄各放一支合規的基線檔**（2026-08-15 新增）。
#    理由：check-exec-bits.sh 的 canary 已改成**逐 pathspec** 判——
#    任一邊掃到 0 個檔就 failm。若 fixture 只佈置其中一邊，
#    每一條都會因為 canary 而紅，而不是因為它要測的那件事。
#    ⇒ 基線一律兩邊都有，各 case 再在上面疊自己的違規。
#    ⚠️ `empty`、`only_bin`、`only_scripts` 三條**刻意不呼叫** seed_repo——
#       它們要測的就是「掃不到東西」本身。
make_repo() {
  local name="$1"
  local repo="$WORK/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t.test
  git -C "$repo" config user.name t
  # fixture repo 關掉 autocrlf：否則每個檔都印一行 LF→CRLF 警告，把測試輸出淹掉。
  git -C "$repo" config core.autocrlf false
  # 🔴 **強制 core.filemode=true**（2026-08-15，PR #41 第二輪驗收）。
  #    Linux runner 上 git 會自動偵測成 true，Windows 上是 false。
  #    兩者差別很大：filemode=true 時，`git add -A` 會**重新以磁碟 mode 覆蓋 index**，
  #    把先前 `update-index --chmod=+x` 設好的 100755 打回 100644。
  #    ⇒ 不固定這個設定的話，**本機全綠但 CI 會紅**——
  #      而那正是這支閘門本身要防的落差，在它自己的測試裡復發。
  git -C "$repo" config core.filemode true
  printf '%s' "$repo"
}

# 在 $1 裡佈置 bin/ 與 scripts/ 各一支**合規**的基線檔（都是 100755）。
seed_repo() {
  local repo="$1"
  mkdir -p "$repo/bin" "$repo/scripts"
  printf '#!/usr/bin/env ruby
puts 0
' > "$repo/bin/baseline"
  printf '#!/bin/sh
echo baseline
' > "$repo/scripts/baseline.sh"
  git -C "$repo" add -A
  git -C "$repo" update-index --chmod=+x bin/baseline
  git -C "$repo" update-index --chmod=+x scripts/baseline.sh
}

# $1=名稱 $2=期望 exit $3=輸出須含 $4=在防什麼
assert_case() {
  local name="$1" want="$2" want_out="$3" why="$4" repo="$WORK/$1"
  local out status f
  # 🔴 **基線檔的 mode 在這裡「最後一次」設定**，不是在 seed_repo 里。
  #    理由：`core.filemode=true`（Linux CI）時，**各 case 自己的 `git add -A`
  #    會以磁碟 mode 覆蓋 index**，把 seed_repo 設好的 100755 打回 100644
  #    ⇒ clean／no_shebang／bin_ok 三條正向斷言在 CI 上會紅（實測重現過）。
  #    ⚠️ `chmod +x` 救不了：Windows 的檔案系統沒有真的執行位元。
  #    🔴 **放在 assert_case 而不是各 case 末尾，是刻意的**：
  #       這是唯一保證在「所有佈置都做完之後」跑的地方，
  #       新增 case 的人不可能忘記。（機制 > 紀律，同本 PR 的主旨。）
  for f in bin/baseline scripts/baseline.sh; do
    if git -C "$repo" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git -C "$repo" update-index --chmod=+x "$f"
    fi
  done
  out="$(bash "$CHECKER" "$repo" 2>&1)"
  status=$?
  if [ "$status" -ne "$want" ]; then
    echo "  FAIL $name：期望 exit $want，實得 $status（$why）"
    echo "       輸出：$(printf '%s' "$out" | head -1)"
    failures=$((failures + 1))
    return
  fi
  if ! printf '%s' "$out" | grep -q "$want_out"; then
    echo "  FAIL $name：exit code 對，但輸出不含「$want_out」（$why）"
    echo "       輸出：$(printf '%s' "$out" | head -1)"
    failures=$((failures + 1))
    return
  fi
  echo "  PASS $name → exit $want：$why"
  passes=$((passes + 1))
}

# ── 1. 乾淨：全部 755 ⇒ 必須通過（反向斷言）──────────────────────
repo="$(make_repo clean)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/ok.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x scripts/ok.sh
assert_case clean 0 "OK" "🔴 反向斷言：乾淨 repo 必須 exit 0，否則一個永遠 fail 的檢查器會讓每條都『通過』"

# ── 2. ASCII 檔名 644 ＋ shebang ⇒ 必須抓到 ────────────────────
repo="$(make_repo ascii)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/bad.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/bad.sh
assert_case ascii 1 "bad.sh" "基本判準：帶 shebang 卻是 100644"

# ── 3. 無 shebang 的 644 ⇒ 不該被抓（避免誤傷資料檔）──────────────
repo="$(make_repo no_shebang)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf 'just: data\n' > "$repo/scripts/data.yml"
printf '#!/bin/sh\n' > "$repo/scripts/ok.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/data.yml
git -C "$repo" update-index --chmod=+x scripts/ok.sh
assert_case no_shebang 0 "OK" "無 shebang 的資料檔不受約束——判準若寫成『scripts/ 下全部』會誤傷"

# ── 4. 含空白的檔名 ⇒ 必須抓到（PR #35 Codex review）─────────────
repo="$(make_repo spaced)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/a script.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x "scripts/a script.sh"
assert_case spaced 1 "a script.sh" "含空白的檔名：以空白切欄會截斷成 scripts/a ⇒ head 開不了 ⇒ 靜默漏掉"

# ── 5. 🔴 非 ASCII 檔名 ⇒ 必須抓到（本輪驗收 Y4）────────────────
repo="$(make_repo non_ascii)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/檢查.rb"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x "scripts/檢查.rb"
assert_case non_ascii 1 "檢查.rb" "🔴 core.quotePath 會把非 ASCII 路徑加引號跳脫 ⇒ 舊寫法完全抓不到"

# ── 6. 🔴 部分暫存：index 有 shebang、工作區沒有 ⇒ 必須抓到 ──────
#    （PR #41 的 Codex review）本檢查判的是 index 的 mode，
#    shebang 若從工作區讀就前後不一致，會被這個流程騙過：
#      git add x && git update-index --chmod=-x x && 把工作區的 shebang 刪掉
#    ⇒ 舊寫法印 OK exit 0，而即將提交的是一支帶 shebang 的 100644 腳本。
repo="$(make_repo staged_only)"
seed_repo "$repo"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/staged.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/staged.sh
printf 'shebang removed from worktree\n' > "$repo/scripts/staged.sh"
assert_case staged_only 1 "staged.sh" "🔴 部分暫存：index 有 shebang 但工作區沒有——從工作區讀 shebang 會放行即將提交的違規內容"

# ── 7. 🔴 bin/ 規則：該目錄下的檔一律必須 755 ────────────────────
#    （PR #41 的 Codex review）初版的六條 fixture 全部只佈置 scripts/，
#    ⇒ 把 checker 裡處理 bin/ 的那段整個刪掉，這支回歸測試**仍然全綠**。
#    契約的另一半完全沒被測到。
repo="$(make_repo bin_bad)"
seed_repo "$repo"
mkdir -p "$repo/bin"
printf '#!/usr/bin/env ruby\nputs 1\n' > "$repo/bin/rails"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x bin/rails
assert_case bin_bad 1 "bin/rails" "🔴 bin/ 的檔缺執行位元——2026-08-14 CI 全紅就是這個原因（bin/rails 等 10 個檔）"

# ── 8. bin/ 正向：全部 755 ⇒ 通過（避免把 bin/ 規則寫成永遠紅）──
repo="$(make_repo bin_ok)"
seed_repo "$repo"
mkdir -p "$repo/bin"
printf '#!/usr/bin/env ruby\nputs 1\n' > "$repo/bin/rails"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x bin/rails
assert_case bin_ok 0 "OK" "bin/ 全部可執行時必須通過——否則 bin/ 規則會變成永遠紅"

# ── 10. 🔴 只有 bin/、scripts/ 掃到 0 個 ⇒ 必須 fail────────────
#    （PR #41 的 Claude 驗收指出）初版 canary 只判**總和**，
#    所以只擋住「兩邊同時為 0」這一個特例。實測重現過：
#      只有 bin/rails（755）的 repo → 印「OK（掃描 1 個檔）」、
#      並逐字宣告「scripts/ 帶 shebang 者全部可執行」——它一個 scripts/ 檔都沒看過。
#    🔴 這一條與下一條就是那個修正的承重斷言：
#       把 canary 改回單一 `scanned`，這兩條會紅。
repo="$(make_repo only_bin)"
mkdir -p "$repo/bin"
printf '#!/usr/bin/env ruby
puts 1
' > "$repo/bin/rails"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x bin/rails
assert_case only_bin 1 "scripts/" "🔴 scripts/ 掃到 0 個卻印 OK——canary 判總和時的盲區"

# ── 11. 🔴 只有 scripts/、bin/ 掃到 0 個 ⇒ 必須 fail──────────
repo="$(make_repo only_scripts)"
mkdir -p "$repo/scripts"
printf '#!/bin/sh
echo x
' > "$repo/scripts/ok.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x scripts/ok.sh
assert_case only_scripts 1 "bin/" "🔴 反方向：bin/ 掃到 0 個同樣不得印 OK"

# ── 9. 🔴 零掃描 ⇒ 必須 fail，不能印 OK（本輪驗收 Y5）────────────
repo="$(make_repo empty)"
printf 'x\n' > "$repo/README"
git -C "$repo" add -A
assert_case empty 1 "一個檔都沒掃到" "🔴 pathspec 無匹配時，舊寫法印『OK：全部可執行』且 exit 0＝空值長得像資料"

echo
if [ "$failures" -eq 0 ]; then
  echo "OK：執行位元閘門回歸測試通過（$passes 條）"
  exit 0
fi
echo "::error::執行位元閘門回歸測試失敗（$failures 條）"
echo "  🔴 這代表 scripts/check-exec-bits.sh 的判定壞了，或 fixture 的前提變了。"
exit 1
