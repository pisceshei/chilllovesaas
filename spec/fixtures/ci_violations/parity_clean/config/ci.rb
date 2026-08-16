def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "Invariants: CI parity rules regression", "ruby scripts/test-ci-parity-rules.rb"
  step "Style: Ruby", "bin/rubocop"
  step "Security: Frontend audit", "pnpm audit --audit-level high"
end
