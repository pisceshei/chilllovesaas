def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "Invariants: CI parity rules regression", "ruby scripts/test-ci-parity-rules.rb"
  # 🔴 刻意**不**放 scripts/ci/check.rb（第 7 輪驗收指出）：SCRIPT_REF 是兩側共用的，
  # 兩側都有的話，砍掉「子目錄」支援時它會**同時**從兩側消失 ⇒ 差集不變 ⇒ 零承重。
  # 只有讓它成為「缺項」，砍掉子目錄支援才會讓本 fixture 由紅轉綠而被抓。
end
