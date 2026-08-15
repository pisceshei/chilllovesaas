def run
  step "Invariants: CI parity", "ruby scripts/check-ci-parity.rb"
  step "TODO: 之後要加 ruby scripts/check-limits-keys.rb", "true"
end
