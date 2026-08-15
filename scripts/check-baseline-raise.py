#!/usr/bin/env python3
"""把「基準線只准因為量表變準而調高」從**紀律**變成**機制**。

為什麼要這支（Claude 在 PR #28 第二輪 review 點名）：
`DEAD_CONTROL_BASELINE` 的註釋寫著「調高必須同時有量表本身的修正，否則就是把新增的
死控件就地合法」——但那條規則自己**只靠 review 肉眼看 diff 方向**。
🔴 而 89 §7 這一節的標題就叫「把死控件從紀律變成機制」，它自己卻停在紀律層。

判準（刻意保守，只擋最容易發生的那一種）：
  **任一檔的基準線調高，而掃描邏輯一行沒改 ⇒ fail。**
  - 調降永遠放行（清了存量是好事，本來就該順手調降）。
  - 量表變準造成的調高，必然連帶改到掃描邏輯 ⇒ 自然通過。
  - 只把數字往上改、什麼都沒修的 PR ⇒ 硬失敗，不需要有人記得看 diff 方向。

🔴 **這支擋不住什麼**（寫出來以免它被誤讀成保證）：
  「改了掃描邏輯，又順手多調幾個」它分不出來——那仍然要 review 判斷。
  機制的目的是把**不需要判斷的那一半**變成硬失敗，不是取代 review。

用法：`python scripts/check-baseline-raise.py [base-ref]`（預設 `origin/main`）
      退出碼 0=通過（含「無法取得 base ⇒ 略過」），1=違規。
CI：掛在 quality job，與 lint-prototype／test-lint-rules 同一組。
"""
import ast
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TARGET = "scripts/lint-prototype.py"

# 🔴 這幾個就是「量表」——死控件掃描結果由它們決定。
# 改名或新增請一起改這裡，否則機制會靜默失效（它只會少擋，不會誤擋）。
SCANNER_FNS = ("_strip_comments", "_iter_control_tags", "r_dead_control")


def _baseline(text: str) -> dict:
    """從原始碼文字取出 DEAD_CONTROL_BASELINE 的字面值（不 import，避免執行舊版程式）。"""
    m = re.search(r"^DEAD_CONTROL_BASELINE\s*=\s*(\{.*?^\})", text, re.S | re.M)
    return ast.literal_eval(m.group(1)) if m else {}


def _scanner_src(text: str) -> str:
    """把掃描邏輯那幾個函式的原始碼串起來，作為「量表有沒有動過」的指紋。

    用 AST 取函式區段而不是整檔比對：整檔比對會讓「改了別的規則」也算「量表變了」，
    那就等於沒擋。
    """
    try:
        tree = ast.parse(text)
    except SyntaxError:
        return text                      # 舊版語法不合就退回整檔，寧可少擋不要誤擋
    lines = text.splitlines()
    out = []
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name in SCANNER_FNS:
            out.append("\n".join(lines[node.lineno - 1:node.end_lineno]))
    return "\n".join(sorted(out))


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "origin/main"
    try:
        old = subprocess.run(["git", "show", f"{base}:{TARGET}"], cwd=ROOT,
                             capture_output=True, text=True, encoding="utf-8", check=True).stdout
    except (subprocess.CalledProcessError, FileNotFoundError):
        # base ref 不存在（首次建倉、shallow clone、或該檔是本次新增）⇒ 沒有可比對的基準，略過。
        print(f"OK：取不到 {base}:{TARGET}，無基準可比 — 略過")
        return 0

    new = (ROOT / TARGET).read_text(encoding="utf-8")
    old_bl, new_bl = _baseline(old), _baseline(new)
    raised = {k: (old_bl[k], v) for k, v in new_bl.items()
              if k in old_bl and v > old_bl[k]}

    if not raised:
        low = {k: (old_bl[k], v) for k, v in new_bl.items() if k in old_bl and v < old_bl[k]}
        print(f"OK：基準線無調高{('（調降 ' + str(low) + '，放行）') if low else ''}")
        return 0

    if _scanner_src(old) != _scanner_src(new):
        print(f"OK：基準線調高 {raised}，且掃描邏輯（{'／'.join(SCANNER_FNS)}）有對應修正")
        return 0

    print("::error::基準線被調高，但掃描邏輯一行沒改 — 這是把新增的死控件就地合法（89 §7.4）")
    for k, (o, n) in raised.items():
        print(f"  - {k}: {o} → {n}")
    print("  修法：修掉新增的死控件；若確實是量表變準，該次修正必須出現在"
          f" {TARGET} 的 {'／'.join(SCANNER_FNS)} 裡。")
    return 1


if __name__ == "__main__":
    sys.exit(main())
