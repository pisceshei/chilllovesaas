#!/usr/bin/env bash
# 倒計時判詞輪詢——鐵律 17.1 的機制面（P-8 引入；條文見 CLAUDE.md 鐵律 17，
# 於 PR #58 立法（2026-08-18）、尚未進 main 時本行以功能描述為準）。
#
# ## 做什麼
# push 之後掛上這支，它每隔 INTERVAL 秒查一次 GitHub 公開 API，**兩側都綁定同一個
# head SHA**（Codex #59 r2：兩側原本都只是「PR 全域」條件，任何延遲的舊輪產物都能
# 讓它提前 exit 0，而那正好是「以為驗收完成、其實驗的是別的 commit」）：
#   ①**Claude bot 判詞已就緒**＝該 head 的 `review` check-run 已 `completed`。
#     🔴 為什麼不數判詞留言：留言計數是 PR 全域的，舊 commit 的延遲判詞會讓它 +1；
#     而且**判詞留言是邊跑邊編輯的**——2026-08-18 實測，留言建立後 API 仍會回半截
#     內容（8532 字元的判詞只讀到 2933 字元、🟡 段整段不在裡面），照樣被當成「判詞已出」。
#     check-run 掛在 commit 上、且 `completed` 才出現 ⇒ 一次解決「綁 head」與「判詞完整」。
#   ②**Codex 已審該 head**＝存在一則 review，其 `user.login` 精確等於 connector 身分
#     ∧ 其 `commit_id` 精確等於該 head（原本比對「login 含 codex」＋「內文含 9 位 SHA」，
#     前者可被任何含該字串的帳號滿足，後者會被引述舊 SHA 的散文騙過）。
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
fetch_state() {
  python - "$API" "$PR" "$HEAD_SHA" "$PAGES_MAX" "$REVIEW_CHECK_NAME" "$CODEX_LOGIN" <<'PYEOF'
import io, json, sys, urllib.request
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
api, pr, head_sha, pages_max, check_name, codex_login = (
    sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5], sys.argv[6]
)

def get(url):
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.load(r)
    except Exception:
        return None

def pages(url):
    out = []
    for p in range(1, pages_max + 1):
        d = get(f"{url}&page={p}")
        if not isinstance(d, list):
            return None
        out.extend(d)
        if len(d) < 100:
            break
    return out

# ①判詞就緒＝該 head 的 review check-run 已 completed（掛在 commit 上，天然綁 head；
#   且 completed 才出現 ⇒ 不會讀到還在串流編輯中的半截判詞）。
checks = get(f"{api}/commits/{head_sha}/check-runs?per_page=100")
if not isinstance(checks, dict) or "check_runs" not in checks:
    print("APIERR")
    raise SystemExit
verdict_ready = any(
    c.get("name") == check_name and c.get("status") == "completed"
    for c in checks["check_runs"]
)

# ②Codex 已審該 head＝身分精確相等 ∧ commit_id 精確相等（兩者都用權威欄位，
#   不用 login 子串或內文 SHA 子串）。
reviews = pages(f"{api}/pulls/{pr}/reviews?per_page=100")
if reviews is None:
    print("APIERR")
    raise SystemExit
codex_done = any(
    r.get("user", {}).get("login") == codex_login and r.get("commit_id") == head_sha
    for r in reviews
)
print(f"{1 if verdict_ready else 0} {1 if codex_done else 0}")
PYEOF
}

REVIEW_CHECK_NAME="review"
CODEX_LOGIN="chatgpt-codex-connector[bot]"

BASELINE_LINE=$(fetch_state) || { echo "🔴 起跑抓取失敗（API 不可達或限額耗盡）" >&2; exit 2; }
case "$BASELINE_LINE" in APIERR*) echo "🔴 起跑回應非清單（可能被限流）" >&2; exit 2;; esac
echo "起跑（head $HEAD_SHORT）：判詞就緒=${BASELINE_LINE% *}／codex已審=${BASELINE_LINE#* }；" \
     "等待兩者皆為 1（判詞就緒＝該 head 的 \`$REVIEW_CHECK_NAME\` check-run completed）；" \
     "每 $INTERVAL 秒查一次、上限 $MAX_POLLS 輪"

i=0
FAILS=0
while [ "$i" -lt "$MAX_POLLS" ]; do
  i=$((i + 1))
  sleep "$INTERVAL"
  LINE=$(fetch_state) || { FAILS=$((FAILS + 1)); echo "poll#$i 抓取失敗（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && { echo "🔴 連續失敗達 3 次，檢查跑不了" >&2; exit 2; }; continue; }
  case "$LINE" in APIERR*) FAILS=$((FAILS + 1)); echo "poll#$i 回應非清單（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && exit 2; continue;; esac
  FAILS=0
  V=${LINE% *}
  CX=${LINE#* }
  echo "poll#$i 判詞就緒=$V；codex已審該 head=$CX"
  if [ "$V" = "1" ] && [ "$CX" = "1" ]; then
    echo "✅ 兩側皆已對 head $HEAD_SHORT 完成：判詞 check-run completed、Codex review 的 commit_id 相符"
    exit 0
  fi
done

echo "⏰ 逾時升級（鐵律 17）：等滿 $MAX_POLLS 輪（$((MAX_POLLS * INTERVAL / 60)) 分鐘）仍缺至少一方——請人工看 PR #$PR：可能是 workflow 沒觸發、審查方積壓、或熔斷 label 在掛。"
exit 4
