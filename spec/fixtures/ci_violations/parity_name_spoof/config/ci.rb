def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "Invariants: CI parity rules regression", "ruby scripts/test-ci-parity-rules.rb"
  step "TODO: 之後要加 ruby scripts/check-limits-keys.rb", "true"
end
