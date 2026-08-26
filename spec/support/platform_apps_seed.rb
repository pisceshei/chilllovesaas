# frozen_string_literal: true

# 平台 app 字典在測試庫的種子（正典＝`PlatformApp::CATALOG_SEED`）。
#
# 🔴 **為什麼需要這一支**：`db:schema:load` **不跑 migration 的種子段**，而
# `Shop#after_create` 會建 `app_installations`，那一列有指向 `platform_apps.handle`
# 的外鍵 ⇒ 字典空的測試庫上**每一次 `create(:shop)` 都會失敗**，
# 錯誤訊息是 `Validation failed: Platform app must exist`，看起來完全不像
# 「測試庫少了種子」。實測：schema load 之後整份 suite 有大量無關的 spec 一起紅。
#
# 同型先例＝`spec/support/platform_locales_seed.rb`（同一個坑，早三天踩過）。
#
# `before(:suite)` 寫一次；transactional tests 不會回滾它，整個 suite 共用。
RSpec.configure do |config|
  config.before(:suite) do
    PlatformApp.seed!
  end
end
