# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
Rails.application.config.assets.version = "1.0"

# `tokens.css` 的規格路徑固定在 app/assets 根目錄，因此明確加入
# Propshaft load path，讓登入頁與 Admin shell 都能以 logical path 載入。
# 見 docs/design/23-interaction-css-spec.md §1。
Rails.application.config.assets.paths << Rails.root.join("app/assets")
