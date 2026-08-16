def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "Style: Ruby", "bin/rubocop"
end
