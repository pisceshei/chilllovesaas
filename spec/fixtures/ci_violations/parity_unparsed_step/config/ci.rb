CHECKS = { parity: "ruby scripts/check-ci-parity.rb" }.freeze

def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step CHECKS[:parity]
end
