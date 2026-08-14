#!/usr/bin/env python3
"""
原型不變量檢查（三份 HTML 高保真原型）

把這幾輪人工稽核（49/51/53 號）確立的不變量固化成可重跑的檢查。
每條規則都標明「為什麼」與「哪一號文件／哪一次事故」，避免日後被當成無意義的潔癖而拿掉。

用法:
    python3 scripts/lint-prototype.py                 # 檢查全部原型
    python3 scripts/lint-prototype.py --file <path>   # 只檢查一份
    python3 scripts/lint-prototype.py --json          # 機器可讀輸出（進 CI 用）

退出碼: 0=全過, 1=有 ERROR, 0=只有 WARN（WARN 不擋 CI）
"""
from __future__ import annotations
import argparse, collections, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [
    "docs/design/chilllove-admin-v2.html",
    "docs/design/chilllove-platform-admin.html",
    "docs/design/chilllove-storefront-v2.html",
]

ERROR, WARN = "ERROR", "WARN"
_CURRENT_FILE = [""]   # lint(path) 會填入檔名，供 r_dead_control 查基準線


def _style(src: str) -> str:
    return "".join(re.findall(r"<style[^>]*>(.*?)</style>", src, re.S))


def _script(src: str) -> str:
    m = re.findall(r"<script>(.*?)</script>", src, re.S)
    return m[0] if m else ""


def _lineno(src: str, idx: int) -> int:
    return src.count("\n", 0, idx) + 1


# ── 規則 ───────────────────────────────────────────────────────────────────

def r_dup_functions(src, style, script):
    """同檔頂層函式不得重名。

    為什麼：JS 函式宣告提升會讓「後定義者勝出」，且**完全靜默**——沒有錯誤、沒有警告，
    只是前一個函式從此永遠不會被呼叫到。
    事故：53 號 N-01。`billingPage` 被設定分頁的同名函式蓋掉，導致「財務·帳單」的
    發票紀錄頁整頁消失，而且卡片內的「查看發票紀錄 ›」會 go('m-billing') 回到自己形成
    死循環。這是本專案目前唯一一次「功能靜默消失」，靜態掃一次就能擋。
    """
    out = []
    names = collections.Counter()
    pos = {}
    for m in re.finditer(r"^function ([A-Za-z0-9_$]+)\s*\(", script, re.M):
        n = m.group(1)
        names[n] += 1
        pos.setdefault(n, []).append(m.start())
    for n, c in names.items():
        if c > 1:
            base = src.index(script)
            lines = [_lineno(src, base + p) for p in pos[n]]
            out.append((ERROR, f"頂層函式重名 `{n}` × {c}（行 {lines}）— 後者會靜默覆蓋前者", lines[0]))
    return out


def r_dangling_onclick(src, style, script):
    """onclick 引用的函式必須存在。

    為什麼：懸空引用只在使用者真的點下去時才炸，原型 demo 時很容易漏掉。
    只檢查「裸識別字呼叫」——方法呼叫（前面有 `.`）與 JS 內建／關鍵字不算。
    """
    BUILTIN = {
        "if", "for", "while", "return", "typeof", "new", "delete", "void", "in", "of",
        "function", "switch", "catch", "throw", "await", "this", "true", "false", "null",
        "parseInt", "parseFloat", "Number", "String", "Boolean", "Array", "Object", "JSON",
        "Math", "Date", "RegExp", "Set", "Map", "Promise", "encodeURIComponent",
        "decodeURIComponent", "isNaN", "alert", "confirm", "prompt", "setTimeout",
        "setInterval", "requestAnimationFrame", "console", "window", "document", "event",
    }
    out = []
    defined = set(re.findall(r"function ([A-Za-z0-9_$]+)\s*\(", script))
    defined |= set(re.findall(r"(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:function|\()", script))
    defined |= set(re.findall(r"(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*[A-Za-z0-9_$]*\s*=>", script))
    called = collections.Counter()
    for m in re.finditer(r'on(?:click|change|input|submit|keydown)\s*=\s*"([^"]*)"', src):
        body = m.group(1)
        # 去掉 JS 字串拼接出來的片段（'+expr+'、${expr}）——那是執行期組出來的，
        # 靜態解析不到；保留其餘字面量部分繼續檢查。
        body = re.sub(r"'\s*\+.*?\+\s*'", "", body)
        body = re.sub(r"\$\{.*?\}", "", body)
        # (?<![.\w$]) 排除 foo.bar() 的 bar 與 abc123( 之類黏字
        for fn in re.findall(r"(?<![.\w$])([A-Za-z_$][A-Za-z0-9_$]*)\s*\(", body):
            if fn not in BUILTIN:
                called[fn] += 1
    for f, c in sorted(((f, c) for f, c in called.items() if f not in defined), key=lambda x: -x[1]):
        out.append((ERROR, f"onclick 引用未定義的函式 `{f}`（{c} 處）", None))
    return out


def r_hairline(src, style, script):
    """髮絲線不得硬寫 1px；且 --hairline 必須是固定次像素值，不得是 dpr 算式。

    為什麼（依據已更新）：47 §C 原本判定髮絲線＝「1 個裝置像素」，並要求配
    min-resolution/dppx 媒體查詢。**64 號用 getComputedStyle 直接量到值是
    `0.66px`，而且是在 dpr=1 的螢幕上** —— 所以它是寫死的次像素常數，與 dpr 無關。
    47 §C 的解釋已被推翻，本規則隨之反向：有 dppx 媒體查詢反而是錯的。

    事故：這條規則舊版用 `"dppx" not in style` 做子字串比對，於是**任何在註釋裡
    提到 dppx 的檔案都會讓 WARN 靜默消失**——2026-08-12 有人在刪除媒體查詢時
    於註釋裡寫了「已刪除 dppx 媒體查詢」，WARN 就再也不響了。子字串比對整份
    樣式表（含註釋）是假陽性與假陰性的雙向來源，已改為只看真正的 at-rule。
    """
    out = []
    for m in re.finditer(r"border[^:;{}]*:\s*1px\s+(?:solid|dashed)", src):
        out.append((ERROR, "硬寫 1px 邊框 — 應用 var(--hairline)（64 §4：實測 0.66px）",
                    _lineno(src, m.start())))
    # 只認真正的 @media at-rule，不掃註釋（舊版用子字串比對，被註釋裡的 dppx 騙過）
    style_nc = re.sub(r"/\*.*?\*/", " ", style, flags=re.S)
    if re.search(r"@media[^{]*(?:min-resolution|-webkit-min-device-pixel-ratio|dppx)", style_nc):
        out.append((ERROR, "--hairline 綁 dpr 媒體查詢 — 64 §4 實測是固定 0.66px，與 dpr 無關", None))
    m = re.search(r"--hairline\s*:\s*([^;]+);", style_nc)
    if m and re.search(r"calc|/\s*var|dpr", m.group(1)):
        out.append((ERROR, f"--hairline 用算式定義（`{m.group(1).strip()}`）— 應為固定次像素常數（64 §4）", None))
    return out


def r_naked_zindex(src, style, script):
    """z-index 不得寫裸數字。

    為什麼：47 §G 實測實站的浮層全部擠在 510–520 這 11 個數字內，靠 DOM 順序決勝。
    事故：53 號稽核前，admin 的 popover z:10 < modal z:80，導致 modal 內的下拉選單
    被對話框蓋住——這是「猜錯就是肉眼可見 bug」的典型。
    """
    out = []
    for m in re.finditer(r"z-index:\s*(\d+)", src):
        v = int(m.group(1))
        # 1–9：元件內部的區域堆疊（例如圖片疊在漸層上），屬合理用法，只提醒不擋
        sev = WARN if v < 10 else ERROR
        out.append((sev, f"裸 z-index: {v} — 浮層應用 var(--z-*)（47 §G：實站浮層集中 510–520）",
                    _lineno(src, m.start())))
    return out


def r_px_breakpoint(src, style, script):
    """斷點必須用 em。

    為什麼：47 §F 從樣式表抽出的權威值顯示 Shopify 斷點一律以 em 撰寫。這是無障礙設計——
    使用者調大瀏覽器預設字型時版面會提早切換到寬鬆佈局。本專案量測初期「1024px 視窗卻拿到
    極窄版」正是此機制（root 24px 時 48em = 1152px）。
    """
    return [(ERROR, "px 寬度斷點 — 應改 em（47 §F）", _lineno(src, m.start()))
            for m in re.finditer(r"@media[^{]*(?:min|max)-width:\s*\d+px", src)]


def r_transition_all(src, style, script):
    """禁止 transition: all。

    為什麼：47 §5 實測實站真正生效的只有 9 條具名 transition，收斂成 5 時長 × 3 曲線。
    `all` 會連帶動畫非預期屬性，且無法對應 M1–M7 動效規則。
    """
    return [(ERROR, "transition: all — 應改具名屬性（47 §5 M1–M7）", _lineno(src, m.start()))
            for m in re.finditer(r"transition:\s*all", src)]


def r_disabled_opacity(src, style, script):
    """disabled 不得用降 opacity 實作。

    為什麼：47 §E 實測 disabled 的做法是「只降文字色到 #B5B5B5、底色不動」。
    降 opacity 會讓元素在深色底上發灰、淺色底上發白，跨情境不穩定。
    """
    out = []
    for m in re.finditer(r"(?:\[disabled\]|:disabled|\.is-dim|\.disabled)[^{]*\{[^}]*opacity\s*:\s*0?\.\d", style):
        out.append((ERROR, "disabled 用 opacity 實作 — 應只降文字色（47 §E）", None))
    return out


def r_brace_balance(src, style, script):
    return [] if style.count("{") == style.count("}") else \
        [(ERROR, f"<style> 大括號不平衡：{{={style.count('{')} }}={style.count('}')}", None)]


def r_single_script(src, style, script):
    n = src.count("<script")
    return [] if n == 1 else [(ERROR, f"<script> 區塊數 = {n}（原型約定為單一區塊）", None)]


def r_docs_coverage(src, style, script):
    """每個 data-doc 都要有 DOCS 條目，且四欄齊全。

    為什麼：CLAUDE.md 驗收基準——「註釋即開發文檔」，缺註釋一律打回。
    """
    out = []
    raw = set(re.findall(r'data-doc="([^"]+)"', src))
    # 含 ${...} 或 '+x+' 的是執行期組出來的 key，靜態無法解析；
    # 但若是三元運算，兩個字面量分支仍可抽出來檢查。
    keys, dynamic = set(), 0
    for k in raw:
        if "${" in k or "'+" in k or '"+' in k:
            dynamic += 1
            # 只取「結果分支」的字面量：三元的 ? : 兩側、以及 || 的預設值。
            # 不能無差別抓所有引號字串——三元的比較運算元（x==='carrier'）不是 DOCS key。
            for a, b in re.findall(r"\?\s*'([A-Za-z0-9_\-]*)'\s*:\s*'([A-Za-z0-9_\-]*)'", k):
                keys |= {v for v in (a, b) if v}
            keys |= {v for v in re.findall(r"\|\|\s*'([A-Za-z0-9_\-]+)'", k) if v}
        else:
            keys.add(k)
    docs = {}
    m = re.search(r"const DOCS\s*=\s*\{", script)
    if not m:
        return [(WARN, "找不到 DOCS 物件，跳過覆蓋率檢查", None)] if keys else []
    for dm in re.finditer(r'["\']?([A-Za-z0-9_\-]+)["\']?\s*:\s*\{\s*t\s*:', script):
        seg = script[dm.start():dm.start() + 1200]
        docs[dm.group(1)] = seg
    for k in sorted(keys - set(docs)):
        out.append((ERROR, f"data-doc=\"{k}\" 無對應 DOCS 條目", None))
    if dynamic:
        out.append((WARN, f"{dynamic} 個 data-doc 為執行期組成，已抽出其中的字面量分支檢查", None))
    for k, seg in docs.items():
        if k not in keys:
            continue
        miss = [f for f in ("t", "f", "l", "i") if not re.search(rf"[,{{]\s*{f}\s*:", seg)]
        if miss:
            out.append((ERROR, f"DOCS['{k}'] 缺欄位 {miss}", None))
    return out


def r_fake_affordance(src, style, script):
    """帶 › 的列必須可點。

    為什麼：53 號 X-03。設定區有 16 條帶 chevron 卻沒有任何 handler 的假可點列——
    這比原本的 setRow 佔位更誤導，因為 setRow 至少會掛「唯讀」chip 明示。
    """
    out = []
    for m in re.finditer(r'<div[^>]*class="[^"]*set-row[^"]*"[^>]*>(?:(?!</div>).){0,900}?chev', src, re.S):
        seg = m.group(0)
        if "onclick" in seg or "唯讀" in seg or "readonly" in seg.lower():
            continue
        out.append((WARN, "set-row 帶 › 但無 onclick 也未標唯讀 — 假可點列（53 號 X-03）",
                    _lineno(src, m.start())))
    return out


# 🔴 死控件的**存量基準線**（2026-08-14 建立）。
# 為什麼要基準線：規則一上線就抓到 73 條存量，全部只報 WARN 的話，
# lint 輸出會從 13 個警告暴增到 86 個——**沒有人會讀 86 個警告**，
# 規則就等於白做（這正是「加了規則卻被忽略」的典型死法）。
# ⇒ 存量報 WARN（可見、可逐輪清），**超過基準線一律 ERROR**（擋新增）。
#   機制要咬得住的是「不要再長出新的」，不是「一次還清歷史債」。
# 🔴 清掉存量之後**要順手把數字調降**，否則基準線會變成新的容忍額度。
# 🔴🔴 2026-08-14 調高（14/12/47 → 44/25/55）——**這是「量表變準」不是「就地合法」**。
#   本檔的交接文件寫著「看到基準線被調高要當紅旗」，所以這次調高必須說清楚差別：
#   規則首版有兩個**會漏看**的 bug，修掉之後同一份原型量出來的數字自然變大。
#     ① `_strip_comments` 把 `accept="image/*"` 當成 JS 註釋開頭，一路吞到下一個 `*/`
#        ——storefront 實測吞掉 86 行。🔴 這個 helper **同時被 `r_hardcoded_currency`
#        （鐵律 10、ERROR 級）使用**，那 86 行等於從沒被掃過，而 CI 一直是綠的。
#     ② 泛型 tag 選擇器變成免死金牌：admin 的 focus-trap 用了
#        `'input,select,textarea,button'`，於是全站 `class="input"` 的控件因為 blob 裡
#        有裸字 `input` 而全部放行（admin 14 → 44 的主因）。
#   ⇒ **原型一行沒改，數字從 73 變成 124**。這不是新增了死控件，是先前少數了 51 個。
# 🔴 判別方法留給下一個人：調高時**必須同時有量表本身的修正**（本檔或規則的 diff），
#   只改這三個數字而沒動掃描邏輯的調高，就是把新增的死控件就地合法。
DEAD_CONTROL_BASELINE = {
    "chilllove-admin-v2.html": 44,
    "chilllove-platform-admin.html": 25,
    "chilllove-storefront-v2.html": 55,
}


def r_dead_control(src, style, script):
    """互動元素必須有人讀得到——handler、data-f 綁定，或**真的被選擇器用到的把手**。

    為什麼：89 號那一輪查出 25 條「控件畫出來卻沒接行為」，**全部 lint 綠燈**。
    最糟的形態不是「沒反應」，是**回報成功但什麼都沒讀**——例如目錄的 5 個發布開關
    全部關掉，照樣 toast「已儲存目錄價格」，使用者以為設定生效了。

    🔴 **本規則不是「必須有 onclick」**。89 那一輪修好的控件多數**沒有 inline handler**：
    `marketNewRun()` 讀 `querySelectorAll('.mkt-country')`、`rfSubmit()` 讀
    `getElementById('rfOverOK')`、`repExportRun()` 讀 `input[name="expfmt"]:checked`；
    設定側欄的 36 顆鈕靠 `data-set` 走事件委派。天真規則會把這些全部誤報，
    然後被人關掉——比沒有規則更糟。判準是「**有沒有一個真的被選擇器用到的把手**」。

    🔴 **把手只認 DOM API 上下文，不是「有在 script 出現過」**。
    本原型的 markup 寫在 `<script>` 的模板字面量裡，所以任何屬性值**本來就**出現在
    script 字串中——用「有沒有出現」判斷是**自我滿足**的，永遠成立。
    （負面測試實證：把 Cookie 橫幅 radio 退回舊寫法，`name="cbColor"` 只存在於那行
    markup，寬鬆版規則照樣放行。）

    放行條件（任一即可）：
      1. inline handler（onclick/onchange/oninput/onsubmit/onkeydown）
      2. `data-f`（走 formRead 髒狀態追蹤）或 `data-val`（走驗證器）
      3. `disabled`（明示不可用）
      4. id / name / class / `data-*` 之中，至少一個 token 出現在**選擇器上下文**：
         `getElementById(...)`／`getElementsByName(...)`／`querySelector(All)(...)`／
         `closest(...)`／`matches(...)` 的字串引數，或 `dataset.<name>`
    """
    out = []
    HANDLER = re.compile(r"\bon(?:click|change|input|submit|keydown)\s*=")
    SKIP = re.compile(r"\bdata-f\s*=|\bdata-val\s*=|\bdisabled\b")
    # 🔴 逃生口 `data-read="<函式名>"`：把手是**動態產生**時用（例：
    #    `<input type="radio" name="${nm}">` 由 repExportRun() 以 `input[name="expfmt"]`
    #    讀取，靜態比對看不到 `${nm}` 展開後的值）。
    #    🔴 刻意設計成「**會自我說明**」而不是單純靜音：它要寫出**誰**讀這個控件，
    #    而且那個函式必須真的存在（否則本規則照樣報）。純靜音的逃生口會被拿來搪塞。
    defined_fns = set(re.findall(r"function\s+([A-Za-z0-9_$]+)\s*\(", script))


    # 選擇器上下文裡出現過的 token 集合 —— 這才是「有人讀得到」的證據
    # 🔴 id 查找與選擇器字串要**分開收**，判準不同（2026-08-14 修正）。
    #    原本混在一起用「token 有沒有出現在任一 blob」判斷，於是 admin 的 focus-trap
    #    選擇器 `'input,select,textarea,button'` 變成**免死金牌**——
    #    全站 89 個 `class="input"` 的控件因為 blob 裡有裸字 `input` 而全部放行。
    #    ⇒ 裸 tag 名不是把手；class 必須以 `.` 出現、id 以 `#` 或 getElementById 出現。
    exact_ids = set(re.findall(
        r"(?:getElementById|getElementsByName)\(\s*[`'\"]([^`'\"]+)[`'\"]", script))
    sel_blobs = re.findall(
        r"(?:querySelectorAll|querySelector|closest|matches)"
        r"\(\s*[`'\"]([^`'\"]*)[`'\"]",
        script)
    dataset_keys = set(re.findall(r"\bdataset\.([A-Za-z0-9_$]+)", script))

    def _blob_hit(tok, prefix, attrs):
        """token 以 `prefix` 的形態出現在某個選擇器裡，**且該選擇器有機會命中這個控件**。

        🔴 只比對 token 出現與否不夠：`querySelectorAll('.tgl[role="switch"]')` 用到了
        `tgl`，但它同時要求 `role` 屬性。一個只有 `class="tgl"`、沒有 `role` 的開關
        **不會被那句選中**，卻會因為「tgl 有出現」而被放行。
        ⇒ 選擇器帶 `[attr]` 條件時，控件必須也有那些屬性才算被命中。
        """
        for blob in sel_blobs:
            if prefix + tok not in blob:
                continue
            need = re.findall(r"\[([a-zA-Z-]+)", blob)
            if all(re.search(r"\b" + re.escape(a) + r"\s*=", attrs) for a in need):
                return True
        return False

    # ① 剝掉註釋：本檔的防回退註釋會逐字引用壞掉的 markup，不剝會抓到自己的說明文字。
    #    `_strip_comments` 以等長空白替換，行號不受影響。
    # ② 標籤比對不跨行，且 `${...}` 內的 `>` 不算結束——模板運算式常含 `>=`／`=>`。
    #    🔴 交替順序要緊：`${...}` 必須排在 `[^>\n]` 前面，否則 `[^>\n]` 會先逐字吞掉
    #    `$`、`{`…，等走到 `>=` 才失敗，`${...}` 分支永遠輪不到。
    body = _strip_comments(src)
    for m in re.finditer(r"<(button|select|textarea|input)\b((?:\$\{[^}\n]*\}|[^>\n])*)>", body):
        tag, attrs = m.group(1), m.group(2)
        if HANDLER.search(attrs) or SKIP.search(attrs):
            continue
        dr = re.search(r'\bdata-read="([A-Za-z0-9_$]+)"', attrs)
        if dr and dr.group(1) in defined_fns:
            continue
        ok = False
        for i in re.findall(r'\bid="([^"${}\s]+)"', attrs):
            if i in exact_ids or _blob_hit(i, "#", attrs):
                ok = True
        for n in re.findall(r'\bname="([^"${}\s]+)"', attrs):
            if n in exact_ids or _blob_hit(n, '[name="', attrs) or _blob_hit(n, "[name=", attrs):
                ok = True
        for cls in re.findall(r'\bclass="([^"]*)"', attrs):
            for tok in re.split(r"\s+", re.sub(r"\$\{[^}]*\}", " ", cls)):
                if len(tok) > 2 and _blob_hit(tok.rstrip("-"), ".", attrs):
                    ok = True
        for a in re.findall(r"\bdata-([a-z][a-z-]*)=", attrs):
            if a in ("f", "val", "doc"):
                continue
            camel = re.sub(r"-([a-z])", lambda m: m.group(1).upper(), a)
            if camel in dataset_keys or a in dataset_keys or _blob_hit(a, "[data-", attrs):
                ok = True
        if ok:
            continue
        out.append((WARN,
                    f"<{tag}> 無 handler、無 data-f/data-val，也沒有任何被選擇器用到的把手"
                    " — 死控件（89 §2）。接上行為、加 disabled，或在把手是動態產生時標 data-read=\"<讀它的函式名>\"",
                    _lineno(body, m.start())))
    # 超過基準線 ⇒ 這一輪**新增**了死控件，升級為 ERROR 擋下
    cap = DEAD_CONTROL_BASELINE.get(_CURRENT_FILE[0])
    if cap is not None and len(out) > cap:
        out.append((ERROR,
                    f"死控件 {len(out)} 個，超過 `{_CURRENT_FILE[0]}` 的基準線 {cap} 個"
                    " — 本次**新增**了死控件。修掉它；若是清了存量，"
                    "請把 scripts/lint-prototype.py 的 DEAD_CONTROL_BASELINE 調降",
                    None))
    return out


def r_dead_css(src, style, script):
    """CSS 定義了但 markup 從未套用的 class（死碼）。

    為什麼：51 號曾誤報 .card-stack「已實作」，53 號 X-09 查出那 5 次全在 <style> 區、
    markup 零套用。定義而不用會讓後續稽核誤判為已完成。
    """
    out = []
    body = re.sub(r"<style[^>]*>.*?</style>", "", src, flags=re.S)
    watch = ["card-stack", "m-hover", "m-text", "m-focus", "m-accordion", "m-pop", "m-drawer", "m-sidebar"]
    for c in watch:
        if re.search(rf"\.{re.escape(c)}\b", style) and not re.search(rf"\b{re.escape(c)}\b", body):
            out.append((WARN, f"`.{c}` 已定義但 markup 零套用（死碼）", None))
    return out


def r_hardcoded_currency(src, style, script):
    """不得硬編幣別符號。

    為什麼：CLAUDE.md 鐵律 10 ——「實際符號與小數位由市場的 locale 決定，不得硬編」。
    這條規則刻意**不是**「把 NT$ 換成 HK$」。56 號 §513 講得很清楚：換成 HK$ 只是把
    同一個錯誤搬到另一個國家。我們要做全球市場，硬編任何符號都是同一個 bug。

    事故：2026-08-12 盤點發現三份原型共 211 處硬編 `NT$`，其中包含一支集中式格式化
    函式 `const NT=n=>'NT$'+…`。有集中式函式卻仍硬編符號，是最容易被誤判為「已經
    抽象化了」的形態——函式在，但符號長在函式裡。

    允許的例外：`/* TW-PACK */ … /* /TW-PACK */` 等 pack 標記區段內（鐵律 11：既有
    台灣內容不刪、降級為 jurisdiction/tw pack 素材），以及註釋——註釋不會被渲染，
    而在註釋裡引用一個法規值（「台灣超商代收上限 NT$20,000」）是**正確且必要的溯源
    資訊**。2026-08-12 首版沒有排除註釋，逼得執行者把出處註釋改寫成「台幣兩萬元」，
    等於規則在誘導後人刪掉溯源——這是規則自身的傷害，已修正。
    """
    out, seen = [], set()   # 同一處會同時命中「字面量」與「格式化函式」兩條 pattern，去重
    # locale 表是**唯一**允許出現幣別符號字面量的地方——符號總得有個源頭。
    # 但這個豁免必須是「宣告的」不是「推斷的」，而且刻意限定每檔只准一個：
    # 允許多個等於允許把逃生口撒得到處都是，規則就名存實亡了。
    # 順序要緊：標記本身是 JS 區塊註釋，必須在 _strip_comments 之前處理，否則會被
    # 當成註釋抹掉，豁免就永遠不會生效（第一版就是這樣，全站 locale 表全被誤報）。
    body = _strip_pack_regions(src)
    n_tables = len(re.findall(r"/\*\s*CURRENCY-TABLE\s*\*/", body))
    if n_tables > 1:
        out.append((ERROR, f"CURRENCY-TABLE 標記出現 {n_tables} 次 — 每檔只准一份 locale 表", None))
    body = _strip_comments(
        re.sub(r"/\*\s*CURRENCY-TABLE\s*\*/.*?/\*\s*/CURRENCY-TABLE\s*\*/", _blank, body, flags=re.S))
    # 多字元符號（含 $）本身無歧義，後面接什麼都算硬編——首版要求後接數字，
    # 於是漏掉 `placeholder="NT$ 最低"` 這種真硬編（兩位執行者各自獨立回報）。
    for m in re.finditer(r"(?<![A-Za-z])(NT\$|HK\$|US\$|S\$|RM\$|A\$|C\$)", body):
        if m.start() in seen: continue
        seen.add(m.start())
        out.append((ERROR, f"硬編幣別符號 `{m.group(1)}` — 鐵律 10：符號與小數位由市場 locale 決定",
                    _lineno(body, m.start())))
    # 單字元／裸字母符號有歧義（RM 會命中 FORM 2／ROOM 3），必須要詞界 + 後接數字
    for m in re.finditer(r"(?<![A-Za-z0-9])(RM|¥|₩|€|£|฿|₫)\s?[0-9]", body):
        if m.start() in seen: continue
        seen.add(m.start())
        out.append((ERROR, f"硬編幣別符號 `{m.group(1)}` — 鐵律 10：符號與小數位由市場 locale 決定",
                    _lineno(body, m.start())))
    # 格式化函式把符號寫死，最容易被誤判為「已經抽象化了」——函式在，但符號長在函式裡。
    # 三種變體都要抓：前綴 'X$'+n、後綴 n+'X$'、樣板 `X${n}`。首版只抓第一種。
    sym = r"NT\$|HK\$|US\$|S\$|¥|€|£|₩|RM"
    for pat, why in [
        (rf"""["'](?:{sym})["']\s*\+""", "前綴串接"),
        (rf"""\+\s*["'](?:{sym})["']""", "後綴串接"),
        (rf"""`[^`\n]{{0,20}}(?:{sym})\s*\$\{{""", "樣板字面量"),
    ]:
        for m in re.finditer(pat, body):
            span = set(range(m.start(), m.end()))
            if span & seen: continue      # 同一處已被字面量規則報過
            seen |= span
            out.append((ERROR, f"格式化函式硬編幣別符號（{why}）— 符號必須來自 market locale 表",
                        _lineno(body, m.start())))
    return _cap(out, "硬編幣別符號")


def r_tw_outside_pack(src, style, script):
    """台灣法域專屬詞彙不得出現在未標記為 pack 的區段。

    為什麼：CLAUDE.md 鐵律 11 ——「核心規格不得再直接引用 統一發票／字軌／折讓／
    超商取貨／統編／電支條例，要引就引 pack 介面」。基準法域是香港，香港沒有政府
    發票、沒有超商取貨網路。

    這條規則的重點是「不刪、只標」：把台灣內容包進 `data-pack="tw"`（markup）或
    `/* TW-PACK */ … /* /TW-PACK */`（JS/CSS）就通過。目的是讓「這是某個法域的素材」
    這件事在程式碼裡看得見，而不是靠讀者記得。

    事故：2026-08-12 盤點發現 storefront 從頭到尾是一份台灣店（超商取貨／電子發票／
    統編／ECPay 電子地圖／COD 上限），platform-admin 有整個「電子發票管線」模組，
    但沒有任何一處標明這是法域專屬。56 號把法域做成可插拔架構之後，這些內容
    在核心層仍然是無標記的，等於架構只做在文件裡、沒做進程式碼。
    """
    terms = ["統一發票", "統一編號", "統編", "字軌", "超商取貨", "超商代收", "超商代碼",
             "電子支付機構管理條例", "電支條例", "雲端發票", "發票載具", "統一發票購票證"]
    body = _strip_cites(_strip_pack_regions(src))
    out, seen = [], set()
    for t in sorted(terms, key=len, reverse=True):      # 長詞先比，統一發票購票證 不再拆成三筆
        for m in re.finditer(re.escape(t), body):
            span = set(range(m.start(), m.end()))
            if span & seen: continue
            seen |= span
            out.append((ERROR, f"`{t}` 出現在未標記 pack 的區段 — 鐵律 11：要引就引 pack 介面",
                        _lineno(body, m.start())))
    return _cap(out, "台灣法域詞彙未標 pack")


def _blank(m):
    """替換成等長空白，行號才不會位移。"""
    return re.sub(r"[^\n]", " ", m.group(0))


def _strip_pack_regions(src: str) -> str:
    """挖掉 pack 標記區段。

    注意 `data-pack="tw"` 的巢狀問題：首版用 `<(\\w+)[^>]*data-pack="tw"[^>]*>.*?</\\1>`
    非貪婪匹配，遇到巢狀同名標籤（`<div data-pack="tw">` 裡有任何 `<div>`，幾乎必然）
    只會吃到第一個 `</div>`，後半仍判 ERROR——三種標記法裡宣稱可用的那一種，對真實
    markup 幾乎都失效。兩位執行者各自獨立踩到並回報。改為配對計數。
    """
    src = re.sub(r"/\*\s*TW-PACK\s*\*/.*?/\*\s*/TW-PACK\s*\*/", _blank, src, flags=re.S)
    src = re.sub(r"<!--\s*TW-PACK\s*-->.*?<!--\s*/TW-PACK\s*-->", _blank, src, flags=re.S)
    return _strip_nested_attr(src, 'data-pack="tw"')


def _strip_nested_attr(src: str, attr: str) -> str:
    """挖掉帶指定屬性的元素，用配對計數正確處理巢狀同名標籤。"""
    while True:
        m = re.search(rf'<([a-z]+)[^>]*{re.escape(attr)}', src)
        if not m:
            return src
        tag, i = m.group(1), m.start()
        depth, pos = 0, i
        pat = re.compile(rf"</?{tag}\b", re.I)
        while True:
            t = pat.search(src, pos)
            if not t:                       # 沒有結束標籤：吃到檔尾，寧可誤放不要誤報
                end = len(src)
                break
            depth += -1 if src[t.start():t.start() + 2] == "</" else 1
            pos = t.end()
            if depth == 0:
                end = src.index(">", t.start()) + 1
                break
        src = src[:i] + re.sub(r"[^\n]", " ", src[i:end]) + src[end:]


def _strip_comments(src: str) -> str:
    """挖掉 JS 區塊註釋與 HTML 註釋。註釋不會被渲染，因此不是「硬編」。

    🔴 `/*` 前面**不得是識別字元**（2026-08-14 事故）。原本的 `/\*.*?\*/` 會把
    `accept="image/*"` 裡的 `/*` 當成註釋開頭，一路吞到下一個 `*/`——
    storefront 實測**吞掉 75 行**。
    後果不只是漏看死控件：`r_hardcoded_currency`（鐵律 10、**ERROR 級**）用的是同一個
    helper，那 75 行等於**從沒被掃過**，而 CI 一直是綠的。
    真註釋的 `/*` 前面是空白、`;`、`{`、`)` 或行首，不會是字母數字。
    """
    src = re.sub(r"(?<![A-Za-z0-9_])/\*.*?\*/", _blank, src, flags=re.S)
    src = re.sub(r"<!--.*?-->", _blank, src, flags=re.S)
    return src


def _strip_cites(src: str) -> str:
    """挖掉 `/* CITE */ … /* /CITE */` 與 `<!-- CITE --> … <!-- /CITE -->`。

    為什麼需要這個逃生口：規則會抓到自己的引用——任何解釋「鐵律 11 禁用哪些詞」的
    DOCS 或註釋，本身就含有那些詞。把 meta 文件硬包成 TW-PACK 在語意上是錯的
    （它是規則說明，不是某個法域的素材）。CITE 專門標記這種「引述而非使用」。
    """
    src = re.sub(r"/\*\s*CITE\s*\*/.*?/\*\s*/CITE\s*\*/", _blank, src, flags=re.S)
    src = re.sub(r"<!--\s*CITE\s*-->.*?<!--\s*/CITE\s*-->", _blank, src, flags=re.S)
    return src


def _cap(out, label, n=6):
    """同類命中太多時只列前 n 條，其餘折疊成一行——否則一條規則就能淹掉整個報告。"""
    if len(out) <= n:
        return out
    rest = len(out) - n
    return out[:n] + [(out[0][0], f"（另有 {rest} 處{label}，同型不再逐條列出）", None)]


RULES = [r_dup_functions, r_dangling_onclick, r_hairline, r_naked_zindex, r_px_breakpoint,
         r_transition_all, r_disabled_opacity, r_brace_balance, r_single_script,
         r_docs_coverage, r_fake_affordance, r_dead_control, r_dead_css,
         r_hardcoded_currency, r_tw_outside_pack]


def lint(path: Path):
    _CURRENT_FILE[0] = path.name
    src = path.read_text(encoding="utf-8")
    style, script = _style(src), _script(src)
    found = []
    for rule in RULES:
        try:
            for sev, msg, line in rule(src, style, script):
                found.append({"rule": rule.__name__, "sev": sev, "msg": msg, "line": line})
        except Exception as e:  # 規則本身壞掉不該讓整個 lint 靜默通過
            found.append({"rule": rule.__name__, "sev": ERROR, "msg": f"規則執行失敗: {e}", "line": None})
    return found


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", action="append")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    files = [Path(f) for f in a.file] if a.file else [ROOT / t for t in TARGETS]

    report, n_err, n_warn = {}, 0, 0
    for f in files:
        if not f.exists():
            print(f"跳過（不存在）: {f}");  continue
        res = lint(f)
        report[str(f.relative_to(ROOT) if f.is_absolute() else f)] = res
        n_err += sum(1 for r in res if r["sev"] == ERROR)
        n_warn += sum(1 for r in res if r["sev"] == WARN)

    if a.json:
        print(json.dumps(report, ensure_ascii=False, indent=1))
    else:
        for fname, res in report.items():
            errs = [r for r in res if r["sev"] == ERROR]
            warns = [r for r in res if r["sev"] == WARN]
            mark = "✅" if not errs else "❌"
            print(f"\n{mark} {fname}   ERROR {len(errs)} / WARN {len(warns)}")
            for r in errs + warns:
                loc = f"L{r['line']}" if r["line"] else "—"
                print(f"   [{r['sev']:<5}] {loc:>7}  {r['msg']}")
        print(f"\n總計: ERROR {n_err} / WARN {n_warn}")
    return 1 if n_err else 0


if __name__ == "__main__":
    sys.exit(main())
