# production 密碼 hash 依 docs/specs/12 F2 使用 cost 12；test 刻意沿用
# ActiveModel 的 BCrypt::Engine::MIN_COST，避免測試被 bcrypt 拖慢。
BCrypt::Engine.cost = 12 unless Rails.env.test?
