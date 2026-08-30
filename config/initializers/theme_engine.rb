# frozen_string_literal: true

# 包 30（D77）：主題引擎的 Zeitwerk 例外。
#
# `app/liquid/theme_engine/drops.rb` 是 **多類單檔**（PoC 移植保持一檔 ≈25 個 drop 類，
# 拆檔會把彼此緊耦合的 drop 家族打散）——Zeitwerk 慣例要求該檔只定義
# `ThemeEngine::Drops`，故將其排除於 autoload 並顯式 require。
# ⚠️ 代價：dev 模式改 drops.rb 需重啟（引擎檔穩定，可接受；登記 91 §3.48）。
Rails.autoloaders.main.ignore(Rails.root.join("app/liquid/theme_engine/drops.rb"))

Rails.application.config.to_prepare do
  require Rails.root.join("app/liquid/theme_engine/drops.rb").to_s
end
