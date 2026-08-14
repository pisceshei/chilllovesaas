#!/usr/bin/env python3
"""`r_dead_control` 的回歸測試（fixture 驅動）。

為什麼要這支：PR #28 的四項自測**全是手動一次性驗證**，而這條規則在四輪內
踩了四種不同的「漏看」形態，每一種 CI 都是綠的：
  ① `_strip_comments` 把 `accept="image/*"` 當註釋開頭，吞掉整段
  ② 泛型 tag 選擇器 `'input,select,textarea,button'` 讓所有 `class="input"` 免死
  ③ 選擇器來源沒剝註釋 —— JS 註釋裡一句 `getElementById('x')` 就讓真死控件隱形
  ④ `[^>\\n]` 讓跨行標籤整個掃不到
🔴 手動驗證抓不住這種東西：每次改正則都可能讓上一次的修正靜默失效。
   Claude 在 #28 的 review 直接點名這件事，本檔就是它的落地。

用法：`python scripts/test-lint-rules.py`（退出碼 0=全過，1=有失敗）
CI：掛在 quality job，與 lint-prototype 同一步之後。
"""
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("lp", ROOT / "scripts" / "lint-prototype.py")
lp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lp)


def scan(markup: str, script: str = "") -> int:
    """回傳這段 fixture 被判定的死控件數（不含基準線那條 ERROR）。"""
    lp._CURRENT_FILE[0] = "__fixture__"          # 不在基準線表裡 ⇒ 不會加 ERROR
    src = f"<style></style>{markup}<script>{script}</script>"
    return len([r for r in lp.r_dead_control(src, "", script) if r[0] == lp.WARN])


# (名稱, markup, script, 期望死控件數, 這條在防哪一種回歸)
CASES = [
    # ── 應該被抓到（漏看形態）──────────────────────────────────────────
    ("裸 button 無 handler",
     '<button class="zz-none">x</button>', "", 1,
     "最基本的死控件"),

    ("🔴 跨行標籤（漏看形態 ④）",
     '<button\n   class="zz-multiline"\n   aria-label="a">x</button>', "", 1,
     "`[^>\\n]` 版本會整個掃不到，不產生 WARN、不超基準線、CI 照過"),

    ("🔴 選擇器只出現在 JS 註釋裡（漏看形態 ③）",
     '<button id="zzGhost">x</button>',
     "/* 舊 TODO: document.getElementById('zzGhost') */", 1,
     "選擇器來源沒剝註釋的話，這個真死控件會永遠隱形"),

    ("🔴 id 前綴撞名（結尾邊界）",
     '<button id="rf">x</button>',
     "document.querySelector('#rfOverOK')", 1,
     "`#rf` 不得命中 `#rfOverOK`——純子字串比對會放行"),

    ("🔴 屬性值不符（attr value）",
     '<input type="checkbox" class="tgl" role="button">',
     "document.querySelectorAll('.tgl[role=\"switch\"]')", 1,
     "只驗屬性存在會放行；實際 DOM 查詢選不中 role=button"),

    ("🔴 泛型 tag 選擇器不算把手（漏看形態 ②）",
     '<input class="input" type="text">',
     "el.querySelectorAll('input,select,textarea,button')", 1,
     "focus-trap 的裸 tag 清單曾讓全站 class=input 免死"),

    ("逃生口指向不存在的函式",
     '<input type="radio" name="${nm}" data-read="notARealFn">', "", 1,
     "逃生口必須會自我說明——亂寫函式名不得放行"),

    ("屬性值裡含 `>` 不得提前截斷",
     '<button title="a>b" class="zz-gt">x</button>', "", 1,
     "引號內的 `>` 若當成標籤結束，onclick 之類的屬性會落在比對範圍外"),

    # ── 不該被抓到（正面：89 §2 修好的那些寫法）────────────────────────
    ("inline handler", '<button onclick="go()">x</button>', "", 0, "最常見的正常寫法"),
    ("disabled", '<button disabled>x</button>', "", 0, "明示不可用"),
    ("data-f 走 formRead", '<input class="cb" data-f="foo">', "", 0, "髒狀態追蹤"),
    ("data-val 走驗證器", '<input class="input" data-val="req">', "", 0, "表單驗證"),

    ("class 把手真的被 querySelectorAll 用到",
     '<input type="checkbox" class="cb mkt-country" value="JP">',
     "[...document.querySelectorAll('.mkt-country')].filter(x=>x.checked)", 0,
     "89 §2 #10 的修法——沒有 inline handler 但確實被讀"),

    ("id 把手被 getElementById 用到",
     '<input type="checkbox" id="rfOverOK">',
     "document.getElementById('rfOverOK').checked", 0,
     "89 §2 的 rfSubmit() 修法"),

    ("name 把手被屬性選擇器用到",
     '<input type="radio" name="expfmt" value="csv">',
     "document.querySelector('input[name=\"expfmt\"]:checked')", 0,
     "89 §2 #12 的 repExportRun() 修法"),

    ("data-* 走事件委派",
     '<button data-set="general">x</button>',
     "if(e.target.dataset.set){openSettings(e.target.dataset.set);}", 0,
     "設定側欄 36 顆鈕的形態"),

    ("逃生口指向存在的函式",
     '<input type="radio" name="${nm}" data-read="realReader">',
     "function realReader(){return 1;}", 0,
     "把手是動態產生時的正當用法"),

    ("屬性值相符的選擇器",
     '<input type="checkbox" class="tgl" role="switch">',
     "document.querySelectorAll('.tgl[role=\"switch\"]')", 0,
     "attr value 相符就該放行——不得因為加了值比對而誤報"),

    ("🔴 `accept=\"image/*\"` 不得讓掃描失明（漏看形態 ①）",
     '<input type="file" accept="image/*" class="zz-file">\n<button class="zz-after">x</button>', "", 2,
     "`/*` 曾被當註釋開頭吞掉後續 86 行；兩個控件都必須被看到"),
]


def main() -> int:
    bad = []
    for name, markup, script, want, why in CASES:
        got = scan(markup, script)
        ok = got == want
        print(f"  {'PASS' if ok else 'FAIL'}  {name}  期望 {want} 實得 {got}")
        if not ok:
            bad.append(f"{name}（期望 {want}、實得 {got}）— 防的是：{why}")
    print()
    if bad:
        print(f"::error::r_dead_control 回歸測試失敗（{len(bad)} 項）：")
        for b in bad:
            print(f"  - {b}")
        return 1
    print(f"OK：r_dead_control 回歸測試 {len(CASES)} 項全過")
    return 0


if __name__ == "__main__":
    sys.exit(main())
