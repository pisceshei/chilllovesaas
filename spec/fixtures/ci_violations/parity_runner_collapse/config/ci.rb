def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "Security: Frontend audit", "pnpm audit --audit-level high"
end
