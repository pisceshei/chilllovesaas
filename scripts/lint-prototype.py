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
    """髮絲線不得硬寫 1px。

    為什麼：47 §C 實測 Shopify 的分隔線是 **1 個裝置像素**（dpr 1.5 → 0.667px、
    dpr 2 → 0.5px），硬寫 1px 在 Retina 上會粗一倍，是「看起來就是不對」的主因之一。
    """
    out = []
    for m in re.finditer(r"border[^:;{}]*:\s*1px\s+(?:solid|dashed)", src):
        out.append((ERROR, "硬寫 1px 邊框 — 應用 var(--hairline)（47 §C：髮絲線＝1 裝置像素）",
                    _lineno(src, m.start())))
    if "--hairline" in style and "dppx" not in style:
        out.append((WARN, "有 --hairline 但無 min-resolution/dppx 媒體查詢 — 高 dpr 不會變細", None))
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


RULES = [r_dup_functions, r_dangling_onclick, r_hairline, r_naked_zindex, r_px_breakpoint,
         r_transition_all, r_disabled_opacity, r_brace_balance, r_single_script,
         r_docs_coverage, r_fake_affordance, r_dead_css]


def lint(path: Path):
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
