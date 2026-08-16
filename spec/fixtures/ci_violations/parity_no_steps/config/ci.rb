def run
  # 全部改成別的寫法，一行 `step` 都不剩
  execute "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  execute "Regression", "ruby scripts/test-ci-parity-rules.rb"
end
