#!/usr/bin/env bash
# 倒計時判詞輪詢——鐵律 17.1 的機制面（P-8 引入；條文見 CLAUDE.md 鐵律 17，
# 於 PR #58 立法（2026-08-18）、尚未進 main 時本行以功能描述為準）。
#
# ## 做什麼
# push 之後掛上這支，它每隔 INTERVAL 秒查一次 GitHub 公開 API：
#   ①Claude bot 判詞數是否比起跑時多（= 本輪判詞已出）——判詞的認定與
#     claude-review.yml 同一套收斂條件：作者在允許清單內 ∧ 第一行以結論標記開頭
#     （Codex #59 r1：不限作者、不限首行的話，任何人引述標記就能讓本腳本提前 exit 0）
#   ②Codex 是否已對指定 head SHA 發 review（Reviewed commit 錨定）
# 兩者都到 ⇒ exit 0。超過 MAX_POLLS 輪 ⇒ 印升級訊息、exit 4（逾時升級——
# 依鐵律 17 的「逾時升級」語義：不是錯誤，是「該去人工看一眼」的信號）。
#
# ## 用法
#   bash scripts/await-verdict.sh <PR號> <HEAD_SHA> [INTERVAL秒] [MAX_POLLS]
#   INTERVAL 預設 900（15 分鐘，鐵律 17.1 的 15–25 分鐘窗下緣）；MAX_POLLS 預設 8（約 2 小時）。
#   HEAD_SHA 必須是 9–40 位十六進位前綴（Codex 錨定比對用前 9 位；短於 9 位會在
#   舊 review 內文誤中子串——參數驗證直接擋，Codex #59 r1）。
#
# ## 退出碼
#   0＝雙方都已回應（判詞數增加 ∧ Codex 錨定 head）
#   2＝參數錯誤／API 持續失敗（檢查跑不了）——含非數字的 INTERVAL/MAX_POLLS、
#     非十六進位或過短過長的 HEAD_SHA（Codex #59 r1：爛參數不得滑進輪詢循環變 exit 4）
#   4＝逾時升級（等滿 MAX_POLLS 輪仍缺至少一方）
#
# ## 🔴 實作紀律（每一條都是本倉庫實測換來的，動這支前先讀）
#   ①**JSON 一律由 python 直接抓取＋UTF-8 顯式解析，輸出只回 ASCII 計數**——
#     Windows 主控台 cp950 下，shell 管道裡含 CJK 的 JSON 會靜默解錯（同日兩次實測：
#     判詞計數顯示 0 而實際有 10 則、label 查詢誤報不存在）。
#   ②**分頁**（Codex #59 r1）：未認證 API 一頁最多 100 則；留言破百的 PR（本倉庫
#     實際發生過、claude-review.yml 為此上了 --paginate）只看第一頁會永遠等不到新判詞。
#     逐頁抓到不足 100 則為止、上限 PAGES_MAX 頁。
#   ③**未認證 API 限額 60 次/小時/IP、跨工具共用**——每輪請求數＝實際頁數×2（單頁
#     常態＝2 次），INTERVAL 下限 300 秒由參數驗證硬擋。
set -u

PR="${1:-}"
HEAD_SHA="${2:-}"
INTERVAL="${3:-900}"
MAX_POLLS="${4:-8}"
REPO="pisceshei/chilllovesaas"
API="https://api.github.com/repos/$REPO"
PAGES_MAX=5

if [ -z "$PR" ] || [ -z "$HEAD_SHA" ]; then
  echo "用法：bash scripts/await-verdict.sh <PR號> <HEAD_SHA> [INTERVAL秒=900] [MAX_POLLS=8]" >&2
  exit 2
fi
# 🔴 參數驗證一律 exit 2（Codex #59 r1 兩條）：非數字 INTERVAL 在 [ -lt ] 只會吐個被吞的
#    錯再照跑（sleep 連環失敗、瞬間燒光限額）、爛 MAX_POLLS 讓逾時語義失真、短 SHA 誤中
#    舊 review——三種都不准進循環。
case "$PR" in ''|*[!0-9]*) echo "🔴 PR 號必須是十進位整數：$PR" >&2; exit 2;; esac
case "$HEAD_SHA" in *[!0-9a-fA-F]*) echo "🔴 HEAD_SHA 含非十六進位字元：$HEAD_SHA" >&2; exit 2;; esac
if [ "${#HEAD_SHA}" -lt 9 ] || [ "${#HEAD_SHA}" -gt 40 ]; then
  echo "🔴 HEAD_SHA 長度須 9–40 位（實得 ${#HEAD_SHA}）" >&2
  exit 2
fi
case "$INTERVAL" in ''|*[!0-9]*) echo "🔴 INTERVAL 必須是十進位整數：$INTERVAL" >&2; exit 2;; esac
case "$MAX_POLLS" in ''|0|*[!0-9]*) echo "🔴 MAX_POLLS 必須是正整數：$MAX_POLLS" >&2; exit 2;; esac
if [ "$INTERVAL" -lt 300 ]; then
  echo "🔴 INTERVAL=$INTERVAL 低於下限 300 秒（未認證 API 限額 60 次/小時/IP、跨工具共用）" >&2
  exit 2
fi

HEAD_SHORT=$(printf '%.9s' "$HEAD_SHA")

# 起跑基準：現有判詞數（之後「變多」才算本輪判詞出了——判詞是累積的，
# 比對絕對數會把上一輪的誤認成這一輪）。
fetch_counts() {
  python - "$API" "$PR" "$HEAD_SHORT" "$PAGES_MAX" <<'PYEOF'
import io, json, sys, urllib.request
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
api, pr, head_short, pages_max = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
# 允許清單與「第一行以標記開頭」皆鏡射 claude-review.yml 的收斂條件；
# 清單變更時兩處要一起改（該檔 REVIEWERS 註釋有同樣的提醒）。
ALLOWED = {"claude[bot]", "github-actions[bot]"}
MARKER = "【驗收結論】"

def pages(url):
    out = []
    for p in range(1, pages_max + 1):
        try:
            with urllib.request.urlopen(f"{url}&page={p}", timeout=30) as r:
                d = json.load(r)
        except Exception:
            print("APIERR")
            raise SystemExit
        if not isinstance(d, list):
            print("APIERR")
            raise SystemExit
        out.extend(d)
        if len(d) < 100:
            break
    return out

comments = pages(f"{api}/issues/{pr}/comments?per_page=100")
reviews = pages(f"{api}/pulls/{pr}/reviews?per_page=100")
verdicts = sum(
    1 for c in comments
    if c.get("user", {}).get("login") in ALLOWED
    and c.get("body", "").split("\n", 1)[0].startswith(MARKER)
)
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
