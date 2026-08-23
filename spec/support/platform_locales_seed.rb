# frozen_string_literal: true

# 平台語言字典在測試庫的種子（schema load 不跑 migration 的種子段；正典＝PlatformLocale::LAUNCH_SEED）。
# before(:suite) 寫一次；transactional tests 不會回滾它，整個 suite 共用。
RSpec.configure do |config|
  config.before(:suite) do
    PlatformLocale.seed!
  end
end
