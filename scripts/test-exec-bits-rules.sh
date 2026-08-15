#!/usr/bin/env bash
# `scripts/check-exec-bits.sh` 的回歸測試（fixture 驅動）。
#
# 65 §K.7 逐字：「**檢查本身也要被測試**——一條永遠不會紅的 CI 規則等於沒有」。
#
# ## 為什麼 fixture 是「跑時現建」而不是版控裡的目錄
#
# 這個檢查讀的是 **git index 的 mode**（`git ls-files -s`），不是檔案系統權限
# ⇒ fixture 必須是**真的 git repo**。巢狀 `.git` 沒辦法提交進本倉庫，
# 所以每個 case 在 `$TMPDIR` 現場建一個小 repo。代價是慢一點（六個 repo），
# 好處是 fixture 與判準永遠不會不同步。
#
# ## 這六條各自守什麼
#
# 前三條是判準本身；**後三條全部是實測抓到的漏洞**，不是想像出來的：
#   - 含空白檔名：PR #35 的 Codex review 指出（`awk '{print $4}'` 以空白切欄會截斷）
#   - 非 ASCII 檔名：本輪驗收 Y4（`core.quotePath` 加引號跳脫 ⇒ head 開不了 ⇒ 靜默漏掉）
#   - 零掃描：本輪驗收 Y5（pathspec 無匹配時舊寫法印 OK 且 exit 0）
#
# 用法：scripts/test-exec-bits-rules.sh
# 退出碼：0=全過，1=有失敗

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT/scripts/check-exec-bits.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

failures=0
passes=0

# 建一個小 git repo。$1=名稱，其餘由 caller 在 $repo 裡佈置。
make_repo() {
  local name="$1"
  local repo="$WORK/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t.test
  git -C "$repo" config user.name t
  printf '%s' "$repo"
}

# $1=名稱 $2=期望 exit $3=輸出須含 $4=在防什麼
assert_case() {
  local name="$1" want="$2" want_out="$3" why="$4" repo="$WORK/$1"
  local out status
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
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/ok.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x scripts/ok.sh
assert_case clean 0 "OK" "🔴 反向斷言：乾淨 repo 必須 exit 0，否則一個永遠 fail 的檢查器會讓每條都『通過』"

# ── 2. ASCII 檔名 644 ＋ shebang ⇒ 必須抓到 ────────────────────
repo="$(make_repo ascii)"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/bad.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/bad.sh
assert_case ascii 1 "bad.sh" "基本判準：帶 shebang 卻是 100644"

# ── 3. 無 shebang 的 644 ⇒ 不該被抓（避免誤傷資料檔）──────────────
repo="$(make_repo no_shebang)"
mkdir -p "$repo/scripts"
printf 'just: data\n' > "$repo/scripts/data.yml"
printf '#!/bin/sh\n' > "$repo/scripts/ok.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/data.yml
git -C "$repo" update-index --chmod=+x scripts/ok.sh
assert_case no_shebang 0 "OK" "無 shebang 的資料檔不受約束——判準若寫成『scripts/ 下全部』會誤傷"

# ── 4. 含空白的檔名 ⇒ 必須抓到（PR #35 Codex review）─────────────
repo="$(make_repo spaced)"
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/a script.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x "scripts/a script.sh"
assert_case spaced 1 "a script.sh" "含空白的檔名：以空白切欄會截斷成 scripts/a ⇒ head 開不了 ⇒ 靜默漏掉"

# ── 5. 🔴 非 ASCII 檔名 ⇒ 必須抓到（本輪驗收 Y4）────────────────
repo="$(make_repo non_ascii)"
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
mkdir -p "$repo/scripts"
printf '#!/bin/sh\necho x\n' > "$repo/scripts/staged.sh"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x scripts/staged.sh
printf 'shebang removed from worktree\n' > "$repo/scripts/staged.sh"
assert_case staged_only 1 "staged.sh" "🔴 部分暫存：index 有 shebang 但工作區沒有——從工作區讀 shebang 會放行即將提交的違規內容"

# ── 7. 🔴 bin/ 規則：該目錄下的檔一律必須 755 ────────────────────
#    （PR #41 的 Codex review）前六條 fixture 全部只佈置 scripts/，
#    ⇒ 把 checker 裡處理 bin/ 的那段整個刪掉，這支回歸測試**仍然全綠**。
#    契約的另一半完全沒被測到。
repo="$(make_repo bin_bad)"
mkdir -p "$repo/bin"
printf '#!/usr/bin/env ruby\nputs 1\n' > "$repo/bin/rails"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=-x bin/rails
assert_case bin_bad 1 "bin/rails" "🔴 bin/ 的檔缺執行位元——2026-08-14 CI 全紅就是這個原因（bin/rails 等 10 個檔）"

# ── 8. bin/ 正向：全部 755 ⇒ 通過（避免把 bin/ 規則寫成永遠紅）──
repo="$(make_repo bin_ok)"
mkdir -p "$repo/bin"
printf '#!/usr/bin/env ruby\nputs 1\n' > "$repo/bin/rails"
git -C "$repo" add -A
git -C "$repo" update-index --chmod=+x bin/rails
assert_case bin_ok 0 "OK" "bin/ 全部可執行時必須通過——否則 bin/ 規則會變成永遠紅"

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
