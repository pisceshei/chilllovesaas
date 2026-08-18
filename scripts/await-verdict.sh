#!/usr/bin/env bash
# 倒計時判詞輪詢——鐵律 17.1 的機制面（P-8 引入；條文見 CLAUDE.md 鐵律 17，
# 於 PR #58 立法、尚未進 main 時本行以功能描述為準）。
#
# ## 做什麼
# push 之後掛上這支，它每隔 INTERVAL 秒查一次 GitHub 公開 API：
#   ①Claude bot 判詞數是否比起跑時多（= 本輪判詞已出）
#   ②Codex 是否已對指定 head SHA 發 review（Reviewed commit 錨定）
# 兩者都到 ⇒ exit 0。超過 MAX_POLLS 輪 ⇒ 印升級訊息、exit 4（逾時升級——
# 依鐵律 17 的「逾時升級」語義：不是錯誤，是「該去人工看一眼」的信號）。
#
# ## 用法
#   bash scripts/await-verdict.sh <PR號> <HEAD_SHA> [INTERVAL秒] [MAX_POLLS]
#   INTERVAL 預設 900（15 分鐘，鐵律 17.1 的 15–25 分鐘窗下緣）；MAX_POLLS 預設 8（約 2 小時）。
#   HEAD_SHA 給完整或 ≥9 位短 SHA 皆可（Codex 錨定比對用前 9 位）。
#
# ## 退出碼
#   0＝雙方都已回應（判詞數增加 ∧ Codex 錨定 head）
#   2＝參數錯誤／API 持續失敗（檢查跑不了）
#   4＝逾時升級（等滿 MAX_POLLS 輪仍缺至少一方）
#
# ## 🔴 實作紀律（兩條都是本倉庫實測換來的，動這支前先讀）
#   ①**JSON 一律落檔後用 python 以 UTF-8 顯式解析**，不走 shell 管道直讀——
#     Windows 主控台 cp950 下，管道內含 CJK 的 JSON 會靜默解不出（同日兩次實測：
#     判詞計數顯示 0 而實際有 10 則、label 查詢誤報不存在）。
#   ②**未認證 API 限額 60 次/小時/IP、跨工具共用**——本腳本每輪 2 次請求，
#     預設節奏（15 分鐘/輪）每小時 8 次，留足其餘工具的餘裕；不得把 INTERVAL
#     調到 300 秒以下（那會單腳本吃掉 24 次/小時）。
set -u

PR="${1:-}"
HEAD_SHA="${2:-}"
INTERVAL="${3:-900}"
MAX_POLLS="${4:-8}"
REPO="pisceshei/chilllovesaas"
API="https://api.github.com/repos/$REPO"

if [ -z "$PR" ] || [ -z "$HEAD_SHA" ]; then
  echo "用法：bash scripts/await-verdict.sh <PR號> <HEAD_SHA> [INTERVAL秒=900] [MAX_POLLS=8]" >&2
  exit 2
fi
if [ "$INTERVAL" -lt 300 ] 2>/dev/null; then
  echo "🔴 INTERVAL=$INTERVAL 低於下限 300 秒（未認證 API 限額 60 次/小時/IP、跨工具共用）" >&2
  exit 2
fi

HEAD_SHORT=$(printf '%.9s' "$HEAD_SHA")
TMPDIR_SAFE="${TMPDIR:-${TEMP:-/tmp}}"
CJSON="$TMPDIR_SAFE/await_verdict_c_$PR.json"
RJSON="$TMPDIR_SAFE/await_verdict_r_$PR.json"

# 起跑基準：現有判詞數（之後「變多」才算本輪判詞出了——判詞是累積的，
# 比對絕對數會把上一輪的誤認成這一輪）。
fetch_counts() {
  curl -sf "$API/issues/$PR/comments?per_page=100" -o "$CJSON" || return 1
  curl -sf "$API/pulls/$PR/reviews?per_page=100" -o "$RJSON" || return 1
  python - "$CJSON" "$RJSON" "$HEAD_SHORT" <<'PYEOF'
import io, json, sys
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
comments = json.load(open(sys.argv[1], encoding="utf-8"))
reviews = json.load(open(sys.argv[2], encoding="utf-8"))
head_short = sys.argv[3]
if not isinstance(comments, list) or not isinstance(reviews, list):
    print("APIERR")
    raise SystemExit
verdicts = sum(1 for c in comments if "【驗收結論】" in c.get("body", ""))
codex = any(
    "codex" in (r.get("user", {}).get("login", "").lower())
    and head_short in r.get("body", "")
    for r in reviews
)
print(f"{verdicts} {1 if codex else 0}")
PYEOF
}

BASELINE_LINE=$(fetch_counts) || { echo "🔴 起跑抓取失敗（API 不可達或限額耗盡）" >&2; exit 2; }
case "$BASELINE_LINE" in APIERR*) echo "🔴 起跑回應非清單（可能被限流）" >&2; exit 2;; esac
BASE_VERDICTS=${BASELINE_LINE% *}
echo "起跑：既有判詞 $BASE_VERDICTS 則；等待①判詞數增加 ②Codex 錨定 $HEAD_SHORT；每 $INTERVAL 秒查一次、上限 $MAX_POLLS 輪"

i=0
FAILS=0
while [ "$i" -lt "$MAX_POLLS" ]; do
  i=$((i + 1))
  sleep "$INTERVAL"
  LINE=$(fetch_counts) || { FAILS=$((FAILS + 1)); echo "poll#$i 抓取失敗（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && { echo "🔴 連續失敗達 3 次，檢查跑不了" >&2; exit 2; }; continue; }
  case "$LINE" in APIERR*) FAILS=$((FAILS + 1)); echo "poll#$i 回應非清單（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && exit 2; continue;; esac
  FAILS=0
  V=${LINE% *}
  CX=${LINE#* }
  echo "poll#$i 判詞 $V/$BASE_VERDICTS 起跑值；codex錨定=$CX"
  if [ "$V" -gt "$BASE_VERDICTS" ] && [ "$CX" = "1" ]; then
    echo "✅ 雙方已回應：判詞 +$((V - BASE_VERDICTS))、Codex 已錨定 $HEAD_SHORT"
    exit 0
  fi
done

echo "⏰ 逾時升級（鐵律 17）：等滿 $MAX_POLLS 輪（$((MAX_POLLS * INTERVAL / 60)) 分鐘）仍缺至少一方——請人工看 PR #$PR：可能是 workflow 沒觸發、審查方積壓、或熔斷 label 在掛。"
exit 4
