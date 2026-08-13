# tenant context 缺失時必須 fail loudly，不能默默執行 unscoped query；這是
# application layer 的主要隔離防線。見 docs/specs/12 F4。
ActsAsTenant.configure do |config|
  config.require_tenant = true
end
