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
#   INTERVAL 預設 900，且只接受 900–1500 秒（鐵律 17.1 的 15–25 分鐘窗）；MAX_POLLS 預設 8（約 2 小時）。
#   HEAD_SHA 接受 9–40 位十六進位（大小寫皆可）：**內部一律正規化成完整 40 位小寫**
#   ——大寫或短前綴會與 API 回的 `commit_id`（完整小寫）比不中，那會表現成「白等到
#   逾時」而非明顯錯誤。短前綴解析不出完整值時 exit 2，不進輪詢。
#
# ## 退出碼
#   0＝兩側都已**對該 head** 完成：①`review` check-run `conclusion == success`
#     **∧ 該 run 時間窗內**（started_at ≤ created_at ≤ completed_at+5min）存在一則
#     合法判詞留言（允許清單作者＋首行合法形＋理由非空白）②存在 `commit_id` 等於
#     該 head 的 Codex review。⚠️ 只有 completed 不夠——no-verdict 診斷路徑也是
#     job success（r6 修正，詳見 fetch_state 內註釋）
#   2＝參數錯誤／API 持續不可用（檢查跑不了）——含非數字的 INTERVAL/MAX_POLLS、
#     非十六進位或過短過長的 HEAD_SHA（Codex #59 r1：爛參數不得滑進輪詢循環變 exit 4）；
#     🔴 **限流原則上不走這裡**——它會等到額度重置再續（見紀律 ③）。
#     ⚠️ **但限流有自己的上限，逾界仍走 exit 2**（r12 引入、r13 補正契約）：
#     起跑路徑兩個獨立計數＝`BASE_FAILS`（暫時性 API 失敗，上限 4）與 `RATE_WAITS`
#     （限流等待，上限 6）；**限流不消耗失敗預算**，但連續 6 次撞限額仍 exit 2
#     （否則「等完仍被限流」會無限打轉——r12 首版即如此）。
#     ⇒ 呼叫端看到 exit 2 時，**訊息會指明是哪一種**（「連續 N 次抓取失敗」vs
#     「連續 N 次撞限額」），不要一律當成 API 持續不可用。
#   4＝逾時升級（等滿 MAX_POLLS 輪仍缺至少一方）
#   5＝**達總時鐘上限**（`DEADLINE_S`，預設 MAX_POLLS×INTERVAL×2，可由第 5 參數覆寫）
#     🔴 自 2026-08-19 起，預算**自腳本啟動起算**（涵蓋起跑重試與限流等待）⇒
#     「起跑連撞限額」可能先撞 5 而不是 2。牆鐘用盡本來就該是 5，這是刻意的行為變更。
#     ——與 4 的差別：4 是「輪次用完」，5 是「**牆鐘用完**」，後者涵蓋限流等待。
#     🔴 **限流仍然不消耗輪次**（軟界不變），但整體由本上限保證有界終止：
#     官方對 primary 限流**沒有**任何放棄門檻（只說等到 reset），對 secondary 才說
#     「throw an error after a specific number of retries」——**次數而非時間**，
#     且不覆蓋本案主要形態（匿名 60/hr 的 primary）⇒ 缺口須自行補，形狀取自
#     gRPC A6 的 deadline「applies across all attempts」。取證 2026-08-19。
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
#     額度估算曾只要求 INTERVAL≥300；現依鐵律 17.1 收緊為 900–1500 秒並由參數驗證硬擋。
#     **撞限時等到 `X-RateLimit-Reset` 再續**，
#     不計入**失敗**預算、也不消耗輪詢輪次（但限流自身有上限，見退出碼 2 的說明）
#     （2026-08-18 實測：同日的診斷查詢把匿名額度用光，
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
# 先比十進位位數，避免超出 shell 整數範圍的輸入讓 `[ -gt ]` 報錯後 fail-open。
_decimal_gt() {
  [ "${#1}" -gt "${#2}" ] && return 0
  [ "${#1}" -lt "${#2}" ] && return 1
  [ "$1" -gt "$2" ]
}
if _decimal_gt "$INTERVAL" 1500 || [ "$INTERVAL" -lt 900 ]; then
  echo "🔴 INTERVAL=$INTERVAL 不在鐵律 17.1 的 900–1500 秒（15–25 分鐘）範圍內" >&2
  exit 2
fi
# 🔴 **總時鐘上限＝有界終止的唯一保證**（Codex #59 r14③；依使用者要求先上網研究後採用）。
#   問題：限流分支用 `i=$((i - 1))` 表達「限流不消耗輪次」，但那只是**軟界**——GitHub
#   若持續更新限流，這個迴圈既到不了 MAX_POLLS/exit 4，也到不了起跑路徑那個 RATE_WAITS
#   上限（那個上限**只存在於起跑**，主迴圈從來沒有）⇒ 實際是無界等待。
#   🔴 **根因是用錯維度，不是漏寫計數器**：gRPC 官方 retry 設計（proposal A6）把三件事
#   拆開——retryThrottling（准不准重試）／maxAttempts（最多幾次）／**deadline（整件事
#   何時必須結束，"applies across all attempts"）**。「不消耗輪次」屬前兩者那一側，
#   「有界」只能由 deadline 表達。
#   🔴 **為什麼不用「限流次數上限」**：一次限流等待可以是 5 秒，也可以撞到
#   RATE_WAIT_MAX（本檔上限）；同一個「N 次」在真實時間上差兩三個數量級 ⇒ 次數當界
#   等於界的長度不可預測。而人工掛起這支腳本的人，真實約束是**時間**。
#   deadline 還是唯一**可組合**的界：限流等待、INTERVAL 睡眠、API 慢回應，全部自動
#   吃同一個預算，日後新增任何等待都不必再補計數器。
#   ⚠️ 官方對本形態的首選建議其實是「Avoid polling／subscribe to webhook events instead」
#   （docs.github.com/rest/guides/best-practices-for-using-the-rest-api，取證 2026-08-19）
#   ——本腳本是人工掛起的本機工具、收不到 webhook，屬**已登記的合法偏離**，不是漏讀。
#   ⚠️ 另一句官方警語是這條上限的立法理由：「Continuing to make requests while you are
#   rate limited may result in the banning of your integration.」
#   預設＝ MAX_POLLS × INTERVAL 的兩倍（給限流等待留一倍餘裕），可由第 5 個參數覆寫。
DEADLINE_S="${5:-$(( MAX_POLLS * INTERVAL * 2 ))}"
case "$DEADLINE_S" in ''|0|*[!0-9]*) echo "🔴 DEADLINE_S 必須是正整數：$DEADLINE_S" >&2; exit 2;; esac
STARTED_AT=$(date -u +%s)
deadline_left() { echo $(( STARTED_AT + DEADLINE_S - $(date -u +%s) )); }
# 🔴 **位置就是語義（2026-08-19 補審第二輪點名）**：這四行原本寫在主輪詢迴圈正上方，
#   於是**起跑階段的等待完全在預算之外**——SHA 正規化的 API 呼叫、起跑抓取的 4 次失敗重試
#   （每次 sleep 10）、以及最多 6 次限流等待（每次可達 RATE_WAIT_MAX=3900）合計上界
#   約 23440 秒，全部不計時。宣稱「總時鐘上限」卻從第一次等待之後才開始計時，那不是上限。
#   ⇒ 預算必須宣告在**第一個可能等待的動作之前**，即本處。
# 🔴 **行為變更（明寫，不得靜默）**：搬到這裡之後，「起跑連撞 6 次限流」原本一定走 exit 2
#   （API 持續不可用），現在可能先撞 exit 5（牆鐘用盡）。這是刻意的——牆鐘用盡本來就該是 5。
#   ⚠️ **已知殘留（未修，本輪未被點名）**：單次 fetch_state 自己不受預算約束
#   （3 支分頁端點 × HARD_PAGE_CAP=100 頁），nap() 夾不到已經發出的同步呼叫 ⇒ 誤差上界
#   ＝「一次進行中的網路呼叫」。要收緊需 per-attempt timeout（AWS SDK 的三層規則：
#   apiCallTimeout ≥ apiCallAttemptTimeout ≥ HTTP client timeout）——已登記，未實作。
# 🔴 **所有等待一律走 nap()，不得再出現裸 sleep**。語義取自 Go 的 context.WithDeadline
#   （「has the deadline adjusted to be **no later than** d」）：把想睡的秒數夾到
#   min(想睡, 剩餘預算)。回 1 ＝預算已盡 ⇒ 呼叫端一律 deadline_exit。
#   🔴 **只把檢查點加密是修不好的**：原本「只在每輪開始時檢查」的寫法，就算前後各加一次
#   檢查，那一次 sleep 還是會睡滿 INTERVAL（生產預設 900 秒）⇒ 超收上界不變。
#   根因不是檢查次數不夠，是**睡眠時長沒有被剩餘預算約束**。
# 🔴 **夾斷之後絕不可以繼續發請求**：夾斷代表還沒等到 rate-limit reset，此時再打 API 正是
#   官方明文警告的那件事（見上方引文）⇒ 夾斷一律 deadline_exit，不是 continue。
nap() {
  _want=$1
  _left=$(deadline_left)
  [ "$_left" -le 0 ] && return 1
  [ "$_want" -gt "$_left" ] && _want=$_left
  [ "$_want" -gt 0 ] && sleep "$_want"
  [ "$(deadline_left)" -le 0 ] && return 1
  return 0
}
deadline_exit() {
  echo "🔴 已達總時鐘上限 ${DEADLINE_S}s（自腳本啟動起算，涵蓋起跑重試、INTERVAL 睡眠與所有限流等待）" >&2
  echo "   請人工看 PR #$PR：若持續撞限額，考慮改用已認證的 gh（5000/hr）或加大 DEADLINE_S（第 5 參數）。" >&2
  exit 5
}

# 🔴 SHA 正規化（Codex #59 r3／r4 兩條同根）：GitHub 回的 `commit_id` 一律是
#    **完整 40 位小寫**，而本腳本改用精確相等比對之後——①傳大寫（規格允許 A–F）
#    或②傳短前綴（規格允許 9–39 位）都會**永遠比不中**，於是整個輪詢窗白等、最後
#    以 exit 4 收場，看起來像「審查方沒回應」而其實是格式問題。
#    處置：先轉小寫（零成本），再把短前綴用 API 解析成完整 SHA；解析不到就 exit 2
#    （寧可當場說不知道，也不要拿一個註定比不中的值去等 90 分鐘）。
HEAD_SHA=$(printf '%s' "$HEAD_SHA" | tr 'ABCDEF' 'abcdef')
HEAD_SHORT=$(printf '%.9s' "$HEAD_SHA")

# 🔴 直譯器偵測（Codex #59 r7）：Debian/Ubuntu 與 macOS 常只有 `python3` 沒有 `python`
#    ——寫死 `python` 會在發出任何 API 請求之前就 command-not-found，然後被重試邏輯
#    誤報成「API 持續不可用」。順序：python3 → python（且驗證是 Python 3）→ 都沒有
#    就 exit 2 講明缺什麼。內嵌程式用的是 Python 3 語法，倉庫其他腳本也一律 python3。
PY_BIN=""
for _py in python3 python; do
  if command -v "$_py" >/dev/null 2>&1 && "$_py" -c 'import sys; sys.exit(0 if sys.version_info[0] == 3 else 1)' >/dev/null 2>&1; then
    PY_BIN="$_py"
    break
  fi
done
if [ -z "$PY_BIN" ]; then
  echo "🔴 找不到 Python 3 直譯器（python3／python 皆不可用）——本腳本的 API 解析需要它" >&2
  exit 2
fi

# 回傳「判詞就緒 codex已審」兩個 0/1；限流回 `RATELIMITED <reset_epoch>`、
# 其他不可解析回 `APIERR`（兩者由呼叫端分開處置）。
fetch_state() {
  "$PY_BIN" - "$API" "$PR" "$HEAD_SHA" "$REVIEW_CHECK_NAME" "$CODEX_LOGIN" <<'PYEOF'
import io, json, os, subprocess, sys, time, urllib.error, urllib.request
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

def secondary_retry_after(rel):
    # secondary rate limit 的冷卻只存在於**被拒回應的 `Retry-After` 標頭**裡：
    # 它不在 /rate_limit（那支報的是 primary core 窗），也不在 gh 的 stderr 訊息。
    # ⇒ 重發一次同一請求並帶 `--include` 取標頭；重發同樣會被拒，那正是我們要的回應。
    # 拿不到就回 None，由呼叫端用固定退避兜底（拿不到時間也不能不等）。
    if not GH_BIN:
        return None
    try:
        out = subprocess.run([GH_BIN, "api", "--include", rel],
                             capture_output=True, timeout=45)
        for line in out.stdout.decode("utf-8", errors="replace").splitlines():
            if not line.strip():
                break  # 空行＝標頭區結束，後面是 body
            key, sep, val = line.partition(":")
            if sep and key.strip().lower() == "retry-after":
                val = val.strip()
                # 只收秒數形（GitHub 對 secondary limit 回的是秒數，非 HTTP-date）
                if val.isdigit():
                    return int(val)
    except Exception:
        pass
    return None


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
            # 🔴 primary 與 secondary 分開（Codex #59 r8）：secondary（abuse／突發）的冷卻
            #    與 core 窗的 reset 無關——拿 .resources.core.reset 充數會睡到不相干的整點，
            #    或五秒後重試四次就 exit 2 而 secondary 還在生效。
            # 🔴 冷卻時間讀**被拒回應的 `Retry-After` 標頭**（Codex #59 r9）：固定 120s 在
            #    GitHub 要求更長冷卻時仍會被連續拒絕、耗盡重試預算。
            #    做法＝**只在失敗路徑**重發一次同一請求並帶 `--include`（成功路徑絕不加，
            #    那會把標頭混進 stdout 汙染 JSON 流）。
            #    ✅ 可行性已實測（2026-08-19，gh 2.97.0）：失敗回應（404）同樣把狀態行與
            #    標頭印到 stdout、錯誤訊息走 stderr、exit 1 ⇒ 標頭拿得到。
            #    複驗：`gh api --include repos/<owner>/<不存在的名字>` 看 stdout 首行是否為
            #    `HTTP/2.0 404 Not Found` 且其後為標頭區。
            if "secondary rate" in err:
                wait = secondary_retry_after(rel)
                print(f"{RATE_LIMITED} {int(time.time()) + (wait if wait is not None else 120)}")
                raise SystemExit
            if ("rate limit" in err) or ("403" in err and "limit" in err):
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
        # 🔴 匿名路徑同樣要分 primary／secondary（Codex #59 r11）：舊版只認
        #    「403/429 ∧ X-RateLimit-Remaining == 0」，那是 **primary** 額度耗盡的簽名。
        #    **secondary（突發／abuse）限制下 Remaining 可能還是正數**，冷卻時間在
        #    `Retry-After` 標頭裡 ⇒ 舊版對這種回應回 None、被上游記成 APIERR，
        #    重試預算耗盡就 exit 2，與檔頭契約「限流一律等到可用再續」相反。
        #    ⇒ 先看 `Retry-After`（秒數形），沒有才退回 `X-RateLimit-Reset` 的 primary 判準。
        if e.code in (403, 429):
            ra = (e.headers.get("Retry-After") or "").strip()
            if ra.isdigit():
                print(f"{RATE_LIMITED} {int(time.time()) + int(ra)}")
                raise SystemExit
            if e.headers.get("X-RateLimit-Remaining") == "0":
                reset = e.headers.get("X-RateLimit-Reset") or "0"
                print(f"{RATE_LIMITED} {reset}")
                raise SystemExit
        return None
    except Exception:
        return None

# 🔴 分頁硬上限的**具名調整點**（Codex #59 r8：docs/dev 曾指向一個已被移除的
#    PAGES_MAX——常數要嘛存在要嘛別在文檔裡指它；現在它存在且兩個 pager 共用）。
#    語義＝「跟到短頁為止」之上的理智上限：觸頂回 None（APIERR、大聲失敗），
#    不是裝作讀完。100 頁＝一萬則。
HARD_PAGE_CAP = 100

def pages(url):
    # 🔴 跟到 API 說沒有下一頁為止（Codex #59 r6）：原本固定 5 頁上限，破 500 則的
    #    PR 會把新判詞留在第 6 頁而**靜默看不到**（白等到逾時）。
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
        if page > HARD_PAGE_CAP:
            return None

# ①判詞就緒＝該 head 的 review check-run 已 completed（掛在 commit 上，天然綁 head；
#   且 completed 才出現 ⇒ 不會讀到還在串流編輯中的半截判詞）。
# 🔴 check-runs 也要分頁（Codex #59 r7）：回應是物件、清單在 .check_runs 裡，
#    破百時 `review` run 可能落在後頁 ⇒ 只看第一頁會白等到逾時。與 pages() 同紀律：
#    跟到短頁為止、理智上限觸頂＝APIERR。
def check_run_pages(url):
    out = []
    page = 1
    while True:
        d = get(f"{url}&page={page}")
        if not isinstance(d, dict) or "check_runs" not in d:
            return None
        out.extend(d["check_runs"])
        if len(d["check_runs"]) < 100:
            return out
        page += 1
        if page > HARD_PAGE_CAP:
            return None

all_runs = check_run_pages(f"{api}/commits/{head_sha}/check-runs?per_page=100")
if all_runs is None:
    print("APIERR")
    raise SystemExit
checks = {"check_runs": all_runs}
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
  # 🔴 再夾一層剩餘預算：RATE_WAIT_MAX 兜的是「reset 值異常」，兜不到「總牆鐘」。
  _l=$(deadline_left)
  [ "$WAIT" -gt "$_l" ] && WAIT=$_l
  echo "⏳ 未認證 API 限額用盡（60/小時/IP、跨工具共用）——等待 ${WAIT} 秒到額度重置後續查（剩餘預算 ${_l}s）"
  nap "$WAIT" || deadline_exit
}

# 🔴 起跑也要有重試預算（Codex #59 r4）：單次暫時性故障（網路抖動、GitHub 5xx、
#    回應被截斷）不該直接 exit 2——契約說 exit 2 是「**持續**不可用」，而輪詢路徑本身
#    就容忍連續三次失敗。起跑比它更脆弱是說不過去的。
BASELINE_LINE=""
BASE_FAILS=0
# 🔴 限流不得消耗**失敗**預算（Codex #59 r10）：舊版是 `for _try in 1 2 3 4`，限流分支的
#    `continue` 照樣推進計數 ⇒ 連續四次限流就走到下面 exit 2，而檔頭契約明寫
#    「限流是可恢復狀態，等到重置再續，**不計入失敗**」。
# 🔴 但**限流必須有自己的上限**，否則就成了無界等待：只把限流排除在 BASE_FAILS 之外、
#    不另設界，`continue` 會在「等完仍被限流」時無限打轉（本輪首版即如此，自檢時發現）。
#    ⇒ 兩個獨立計數：`BASE_FAILS`（暫時性 API 失敗，上限 4）與 `RATE_WAITS`（限流等待，
#    上限 6）。兩者任一耗盡就離開迴圈，由下方 case 分別報出正確原因。
BASE_RATE_WAITS_MAX=6
RATE_WAITS=0
while [ "$BASE_FAILS" -lt 4 ] && [ "$RATE_WAITS" -lt "$BASE_RATE_WAITS_MAX" ]; do
  BASELINE_LINE=$(fetch_state) || BASELINE_LINE="APIERR"
  case "$BASELINE_LINE" in
    RATELIMITED*)
      RATE_WAITS=$((RATE_WAITS + 1))
      echo "起跑撞限額（第 $RATE_WAITS/$BASE_RATE_WAITS_MAX 次；**不計入失敗預算**）——等到重置再續"
      wait_for_reset "${BASELINE_LINE#* }"
      continue;;
    APIERR*)
      BASE_FAILS=$((BASE_FAILS + 1))
      echo "起跑抓取失敗（暫時性，累計 $BASE_FAILS）——10 秒後重試"
      nap 10 || deadline_exit
      continue;;
  esac
  break
done
case "$BASELINE_LINE" in
  RATELIMITED*) echo "🔴 起跑階段連續 $RATE_WAITS 次撞限額（上限 $BASE_RATE_WAITS_MAX），放棄" >&2; exit 2;;
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
  [ "$(deadline_left)" -le 0 ] && deadline_exit
  i=$((i + 1))
  nap "$INTERVAL" || deadline_exit
  LINE=$(fetch_state) || { FAILS=$((FAILS + 1)); echo "poll#$i 抓取失敗（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && { echo "🔴 連續失敗達 3 次，檢查跑不了" >&2; exit 2; }; continue; }
  case "$LINE" in
    RATELIMITED*) i=$((i - 1)); echo "poll#$i 撞限額（不消耗輪次；總時鐘剩 $(deadline_left)s）"; wait_for_reset "${LINE#* }"; continue;;
    APIERR*) FAILS=$((FAILS + 1)); echo "poll#$i 回應非預期格式（累計 $FAILS）"; [ "$FAILS" -ge 3 ] && exit 2; continue;;
  esac
  FAILS=0
  V=${LINE% *}
  CX=${LINE#* }
  echo "poll#$i 判詞就緒=$V；codex已審該 head=$CX"
  if [ "$V" = "1" ] && [ "$CX" = "1" ]; then
    echo "✅ 兩側皆已對 head $HEAD_SHORT 完成：review check success 且該輪時間窗內有合法判詞、Codex review 的 commit_id 相符"
    exit 0
  fi
done

echo "⏰ 逾時升級（鐵律 17）：等滿 $MAX_POLLS 輪（$((MAX_POLLS * INTERVAL / 60)) 分鐘）仍缺至少一方——請人工看 PR #$PR：可能是 workflow 沒觸發、審查方積壓、或本輪 workflow 因反竄改（PR 動到 .github/workflows/）被整個跳過。"
exit 4
