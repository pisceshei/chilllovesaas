#!/usr/bin/env bash
# 倒計時判詞輪詢——鐵律 17.1 的機制面（P-8 引入；條文見 CLAUDE.md 鐵律 17，
# 於 PR #58 立法（2026-08-18）、尚未進 main 時本行以功能描述為準）。
#
# ## 做什麼
# push 之後掛上這支，它每隔 INTERVAL 秒查一次 GitHub 公開 API，**兩側都綁定同一個
# head SHA**（Codex #59 r2：兩側原本都只是「PR 全域」條件，任何延遲的舊輪產物都能
# 讓它提前 exit 0，而那正好是「以為驗收完成、其實驗的是別的 commit」）：
#   ①**Claude bot 判詞已就緒**＝該 head 的 `review` check-run `conclusion == success`
#     **∧ 該輪真的貼出了一則合法判詞**（作者在允許清單 ∧ 首行整行匹配合法結論形
#     ∧ 留言時間不早於該 check-run 的 `started_at`）。
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
#   HEAD_SHA 接受 9–40 位十六進位（大小寫皆可）：**內部一律正規化成完整 40 位小寫**
#   ——大寫或短前綴會與 API 回的 `commit_id`（完整小寫）比不中，那會表現成「白等到
#   逾時」而非明顯錯誤。短前綴解析不出完整值時 exit 2，不進輪詢。
#
# ## 退出碼
#   0＝兩側都已**對該 head** 完成（review check-run completed ∧ Codex review 的
#     `commit_id` 等於該 head）
#   2＝參數錯誤／API 持續不可用（檢查跑不了）——含非數字的 INTERVAL/MAX_POLLS、
#     非十六進位或過短過長的 HEAD_SHA（Codex #59 r1：爛參數不得滑進輪詢循環變 exit 4）；
#     🔴 **限流不走這裡**——它會等到額度重置再續（見紀律 ③）
#   4＝逾時升級（等滿 MAX_POLLS 輪仍缺至少一方）
#
# ## 🔴 實作紀律（每一條都是本倉庫實測換來的，動這支前先讀）
#   ①**JSON 一律由 python 直接抓取＋UTF-8 顯式解析，輸出只回 ASCII 計數**——
#     Windows 主控台 cp950 下，shell 管道裡含 CJK 的 JSON 會靜默解錯（同日兩次實測：
#     判詞計數顯示 0 而實際有 10 則、label 查詢誤報不存在）。
#   ②**分頁**（Codex #59 r1）：未認證 API 一頁最多 100 則；留言破百的 PR（本倉庫
#     實際發生過、claude-review.yml 為此上了 --paginate）只看第一頁會永遠等不到新判詞。
#     逐頁跟到 API 回短頁為止（理智上限 100 頁，觸頂＝APIERR 大聲失敗，不靜默截斷）。
#   ③**額度**：有 `gh` 且已認證時走**認證路徑（5000 次/小時）**；否則回退匿名
#     （**60 次/小時/IP、跨工具共用**）。每輪請求數＝實際頁數×2（單頁常態＝2 次），
#     INTERVAL 下限 300 秒由參數驗證硬擋。**撞限時等到 `X-RateLimit-Reset` 再續**，
#     不計入失敗也不消耗輪次（2026-08-18 實測：同日的診斷查詢把匿名額度用光，
#     舊版起跑即 exit 2 報「回應非清單」——把可恢復狀態當成故障）。
#     🔴 回退分支**必須留著**：本腳本是本機操作工具，不保證每台機器都裝了 `gh`。
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
# 🔴 前導零要擋（Codex #59 r5）：純數字檢查放行 `00` 與 `08` 兩種壞值——`00` 通過非零檢查
#    卻讓迴圈一次都不跑、報成逾時（假 exit 4）；`08` 會在算術展開時被 bash 當**八進位**
#    而報錯。兩者都該是參數錯誤（exit 2），不是逾時也不是 shell 錯誤。
for _pair in "INTERVAL:$INTERVAL" "MAX_POLLS:$MAX_POLLS"; do
  _name=${_pair%%:*}; _val=${_pair#*:}
  case "$_val" in
    0|[1-9]*) ;;
    *) echo "🔴 $_name 不得有前導零（八進位歧義／假逾時）：$_val" >&2; exit 2;;
  esac
done
if [ "$INTERVAL" -lt 300 ]; then
  echo "🔴 INTERVAL=$INTERVAL 低於下限 300 秒（未認證 API 限額 60 次/小時/IP、跨工具共用）" >&2
  exit 2
fi

# 🔴 SHA 正規化（Codex #59 r3／r4 兩條同根）：GitHub 回的 `commit_id` 一律是
#    **完整 40 位小寫**，而本腳本改用精確相等比對之後——①傳大寫（規格允許 A–F）
#    或②傳短前綴（規格允許 9–39 位）都會**永遠比不中**，於是整個輪詢窗白等、最後
#    以 exit 4 收場，看起來像「審查方沒回應」而其實是格式問題。
#    處置：先轉小寫（零成本），再把短前綴用 API 解析成完整 SHA；解析不到就 exit 2
#    （寧可當場說不知道，也不要拿一個註定比不中的值去等 90 分鐘）。
HEAD_SHA=$(printf '%s' "$HEAD_SHA" | tr 'ABCDEF' 'abcdef')
HEAD_SHORT=$(printf '%.9s' "$HEAD_SHA")

# 回傳「判詞就緒 codex已審」兩個 0/1；限流回 `RATELIMITED <reset_epoch>`、
# 其他不可解析回 `APIERR`（兩者由呼叫端分開處置）。
fetch_state() {
  python - "$API" "$PR" "$HEAD_SHA" "$REVIEW_CHECK_NAME" "$CODEX_LOGIN" <<'PYEOF'
import io, json, os, subprocess, sys, urllib.error, urllib.request
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
api, pr, head_sha, check_name, codex_login = (
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
)
# `GH_BIN` 由呼叫端在偵測到「gh 存在且已認證」時傳入；空字串＝走匿名路徑。
GH_BIN = os.environ.get("GH_BIN", "")
API_PREFIX = "https://api.github.com/"  # gh api 收的是不含這段的相對路徑

# 🔴 限流要與「真的壞掉」分開（2026-08-18 實測：診斷查詢把 60/hr 的未認證額度用光，
#    本腳本起跑即 exit 2 報「回應非清單」——訊息沒錯但處置錯了。限流是**可恢復**狀態，
#    正確處置是等到 reset 再續，不是當成故障退出）。偵測法＝HTTP 403/429 且
#    `X-RateLimit-Remaining: 0`；reset 時點讀 `X-RateLimit-Reset`（epoch 秒）。
RATE_LIMITED = "RATELIMITED"

def get(url):
    # 🔴 有 gh 就走認證路徑（5000/hr）；gh 失敗時**不當成錯誤**，靜靜回退匿名——
    #    兩條路拿到的是同一份 JSON，判定邏輯完全不變。
    if GH_BIN:
        rel = url[len(API_PREFIX):] if url.startswith(API_PREFIX) else url
        try:
            out = subprocess.run([GH_BIN, "api", rel], capture_output=True, timeout=45)
            if out.returncode == 0:
                return json.loads(out.stdout.decode("utf-8", errors="replace"))
            # 🔴 認證路徑被限流時**不得靜默回退匿名**（Codex #59 r5）：匿名額度只有 60，
            #    回退等於把一個「等一下就好」的狀態變成連續失敗；而且認證請求的
            #    reset 資訊在回退時整個丟掉。偵測到限流就查 reset 並上報，讓呼叫端等。
            err = out.stderr.decode("utf-8", errors="replace").lower()
            if ("rate limit" in err) or ("secondary rate" in err) or ("403" in err and "limit" in err):
                reset = "0"
                try:
                    rl = subprocess.run([GH_BIN, "api", "rate_limit",
                                         "--jq", ".resources.core.reset"],
                                        capture_output=True, timeout=30)
                    if rl.returncode == 0:
                        reset = rl.stdout.decode("utf-8", errors="replace").strip() or "0"
                except Exception:
                    pass
                print(f"{RATE_LIMITED} {reset}")
                raise SystemExit
        except SystemExit:
            raise
        except Exception:
            pass
    try:
        with urllib.request.urlopen(url, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (403, 429) and (e.headers.get("X-RateLimit-Remaining") == "0"):
            reset = e.headers.get("X-RateLimit-Reset") or "0"
            print(f"{RATE_LIMITED} {reset}")
            raise SystemExit
        return None
    except Exception:
        return None

def pages(url):
    # 🔴 跟到 API 說沒有下一頁為止（Codex #59 r6）：原本固定 5 頁上限，破 500 則的
    #    PR 會把新判詞留在第 6 頁而**靜默看不到**（白等到逾時）。仍留一個很高的
    #    理智上限（100 頁＝一萬則），但觸頂時回 None（APIERR、大聲失敗），
    #    不是裝作讀完了。
    out = []
    page = 1
    while True:
        d = get(f"{url}&page={page}")
        if not isinstance(d, list):
            return None
        out.extend(d)
        if len(d) < 100:
            return out
        page += 1
        if page > 100:
            return None

# ①判詞就緒＝該 head 的 review check-run 已 completed（掛在 commit 上，天然綁 head；
#   且 completed 才出現 ⇒ 不會讀到還在串流編輯中的半截判詞）。
checks = get(f"{api}/commits/{head_sha}/check-runs?per_page=100")
if not isinstance(checks, dict) or "check_runs" not in checks:
    print("APIERR")
    raise SystemExit
# 🔴 判詞就緒＝**job 成功 ∧ 該輪真的產出了合法判詞**（Codex #59 r3 起、r5 補完）：
#    ①`completed` 不等於通過——格式驗證失敗會 `exit 1`、conclusion 是 failure；
#    ②但 `conclusion == success` **仍然不夠**：workflow 在「Claude 沒貼結論」「作者不在
#      允許清單」等路徑上是**貼診斷留言後 exit 0**（claude-review.yml 自己的註釋逐字寫著
#      「失敗被下游 exit 0 吞掉」）⇒ job 照樣 success 而根本沒有判詞。只看 conclusion 的話，
#      Codex 一審完本腳本就會宣告「兩側完成」，而 bot 那側其實什麼判詞都沒有。
#    ⇒ 追加一條：存在一則**該輪的**合法判詞留言——作者在允許清單 ∧ 第一行整行匹配合法形
#      ∧ `created_at >= 該 check-run 的 started_at`（用 check-run 的起跑時刻綁定「該輪」，
#      留言本身沒有 commit 關聯，這是唯一可靠的關聯鍵）。
ALLOWED_VERDICT_AUTHORS = {"claude[bot]", "github-actions[bot]"}
MARKER = "【驗收結論】"

def first_line_ok(body):
    first = (body or "").splitlines()[0].rstrip() if (body or "").strip() else ""
    if not first.startswith(MARKER):
        return False
    rest = first[len(MARKER):]
    if rest == "通過":
        return True
    # 🔴 理由不得全空白（Codex #59 r6，與 claude-review.yml 的格式判準同步收緊）：
    #    「需修改：　」這種只有空白的理由要判不合法。
    return rest.startswith("需修改：") and rest[len("需修改："):].strip() != ""


review_run = next(
    (c for c in checks["check_runs"]
     if c.get("name") == check_name
     and c.get("status") == "completed"
     and c.get("conclusion") == "success"),
    None,
)
verdict_ready = False
if review_run is not None:
    # 🔴 綁**本輪 run 的時間窗**（Codex #59 r6）：只設下界 `>= started` 的話，
    #    舊 commit 的 workflow 事後人工 rerun 貼出的判詞（時間更晚）照樣通過檢查。
    #    本 head 的判詞必然貼在**該 run 執行期間** ⇒ 上界用 completed_at（加 5 分鐘
    #    餘裕吸收貼文與收尾的時差）。留言本身沒有 commit 關聯欄位，run 時間窗是
    #    唯一可用的關聯鍵；真正的根治（判詞契約帶 SHA）屬 workflow 側，另列待辦。
    started = review_run.get("started_at") or ""
    completed = review_run.get("completed_at") or "9999-12-31T00:00:00Z"
    import datetime as _dt
    try:
        _c = _dt.datetime.fromisoformat(completed.replace("Z", "+00:00"))
        upper = (_c + _dt.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception:
        upper = completed
    comments = pages(f"{api}/issues/{pr}/comments?per_page=100")
    if comments is None:
        print("APIERR")
        raise SystemExit
    verdict_ready = any(
        c.get("user", {}).get("login") in ALLOWED_VERDICT_AUTHORS
        and first_line_ok(c.get("body", ""))
        and started <= (c.get("created_at") or "") <= upper
        for c in comments
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

# 🔴 偵測 gh：**存在且已認證**才用（`auth status` 非零＝未登入，此時用它反而每次多花一次
#    失敗的子行程）。PATH 沒有時試 Windows 預設安裝路徑——MSI 裝的 gh 只進系統 PATH，
#    **既有 shell 讀不到**（2026-08-18 實測）。
GH_BIN=""
# 🔴 `${PROGRAMFILES:-}`（Codex #59 r5）：`set -u` 下，Linux／macOS 沒有這個變數，
#    直接展開會讓腳本在**偵測階段就 unbound variable 退出**——認證與匿名兩條路都還沒跑到，
#    等於本工具在標準 Unix 環境完全不可用。空值展開後 candidate 變成無效路徑、自然略過。
for _cand in gh "/c/Program Files/GitHub CLI/gh.exe" "${PROGRAMFILES:-}/GitHub CLI/gh.exe"; do
  command -v "$_cand" >/dev/null 2>&1 || [ -x "$_cand" ] || continue
  if "$_cand" auth status >/dev/null 2>&1; then GH_BIN="$_cand"; break; fi
done
export GH_BIN
if [ -n "$GH_BIN" ]; then
  echo "🔐 走 gh 認證路徑（額度 5000/小時）：$GH_BIN"
else
  echo "🔓 走匿名路徑（額度 60/小時/IP）——未偵測到已認證的 gh；撞限時會自動等待重置"
fi

# 短前綴解析成完整 40 位（承上「SHA 正規化」註釋的第二半）。
if [ "${#HEAD_SHA}" -ne 40 ]; then
  RESOLVED=""
  if [ -n "$GH_BIN" ]; then
    RESOLVED=$("$GH_BIN" api "repos/$REPO/commits/$HEAD_SHA" --jq .sha 2>/dev/null || true)
  fi
  if [ -z "$RESOLVED" ]; then
    RESOLVED=$(git rev-parse "$HEAD_SHA" 2>/dev/null || true)
  fi
  case "$RESOLVED" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
      if [ "${#RESOLVED}" -eq 40 ]; then
        echo "ℹ️ 短 SHA $HEAD_SHA 已解析為完整值 ${RESOLVED}"
        HEAD_SHA="$RESOLVED"
      fi;;
  esac
  if [ "${#HEAD_SHA}" -ne 40 ]; then
    echo "🔴 無法把 $HEAD_SHA 解析成完整 40 位 SHA——API 回的 commit_id 是完整值，" >&2
    echo "   拿短前綴去精確比對必然比不中（會白等整個輪詢窗）。請改傳完整 SHA。" >&2
    exit 2
  fi
fi

# 🔴 限流時**等到 reset 再續**，不算失敗也不消耗輪次（實測教訓見 get() 上方註釋）。
#    等待上限用 RATE_WAIT_MAX 兜底，免得 reset 值異常時無限睡。
RATE_WAIT_MAX=3900
wait_for_reset() {
  RESET_EPOCH=${1:-0}
  NOW=$(date +%s)
  WAIT=$((RESET_EPOCH - NOW + 5))
  [ "$WAIT" -lt 5 ] && WAIT=5
  [ "$WAIT" -gt "$RATE_WAIT_MAX" ] && WAIT=$RATE_WAIT_MAX
  echo "⏳ 未認證 API 限額用盡（60/小時/IP、跨工具共用）——等待 ${WAIT} 秒到額度重置後續查"
  sleep "$WAIT"
}

# 🔴 起跑也要有重試預算（Codex #59 r4）：單次暫時性故障（網路抖動、GitHub 5xx、
#    回應被截斷）不該直接 exit 2——契約說 exit 2 是「**持續**不可用」，而輪詢路徑本身
#    就容忍連續三次失敗。起跑比它更脆弱是說不過去的。
BASELINE_LINE=""
BASE_FAILS=0
for _try in 1 2 3 4; do
  BASELINE_LINE=$(fetch_state) || BASELINE_LINE="APIERR"
  case "$BASELINE_LINE" in
    RATELIMITED*) wait_for_reset "${BASELINE_LINE#* }"; continue;;
    APIERR*)
      BASE_FAILS=$((BASE_FAILS + 1))
      echo "起跑抓取失敗（暫時性，累計 $BASE_FAILS）——10 秒後重試"
      sleep 10
      continue;;
  esac
  break
done
case "$BASELINE_LINE" in
  RATELIMITED*) echo "🔴 起跑階段反覆撞限額，放棄" >&2; exit 2;;
  APIERR*|"") echo "🔴 起跑連續 $BASE_FAILS 次抓取失敗，API 持續不可用" >&2; exit 2;;
esac
echo "起跑（head $HEAD_SHORT）：判詞就緒=${BASELINE_LINE% *}／codex已審=${BASELINE_LINE#* }；" \
     "等待兩者皆為 1（判詞就緒＝\`$REVIEW_CHECK_NAME\` check-run success ∧ 該輪貼出合法判詞）；" \
     "每 $INTERVAL 秒查一次、上限 $MAX_POLLS 輪"

# 🔴 起跑就已齊備時**立刻成功**（Codex #59 r3）：主循環第一件事是 sleep，
#    舊版會讓「掛上去時兩側早就完成」的情形白等一個 INTERVAL（預設 15 分鐘）。
if [ "${BASELINE_LINE% *}" = "1" ] && [ "${BASELINE_LINE#* }" = "1" ]; then
  echo "✅ 起跑即齊備：兩側皆已對 head $HEAD_SHORT 完成，無需等待"
  exit 0
fi

i=0
FAILS=0
while [ "$i" -lt "$MAX_POLLS" ]; do
  i=$((i + 1))
  sleep "$INTERVAL"
  LINE=$(fetch_state) || { FAILS=$((FAILS + 1)); echo "poll#$i 抓取失敗（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && { echo "🔴 連續失敗達 3 次，檢查跑不了" >&2; exit 2; }; continue; }
  case "$LINE" in
    RATELIMITED*) i=$((i - 1)); wait_for_reset "${LINE#* }"; continue;;
    APIERR*) FAILS=$((FAILS + 1)); echo "poll#$i 回應非預期格式（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && exit 2; continue;;
  esac
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
