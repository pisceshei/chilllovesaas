# frozen_string_literal: true

# Liquid 相容主題引擎（包 30／D77；PoC → 生產化）。
#
# 沿革：`poc/liquid-engine/` 以 Ella 7.2.0 真實檔案實證（三渲染目標 0 Liquid errors，
# 詳其 README）。本命名空間是該 PoC 的生產移植，**三個反例已改掉**
# （第 20-37 包整合執行規格 §8-6）：
#   ①`LocalizationDrop` 不再硬編 en——語言資料由呼叫端（shop_locales）供給；
#   ②`RoutesDrop` 帶 `prefix:`——B11 的 /{lang}-{region}/ 前綴由渲染脈絡注入；
#   ③`RequestDrop` 的 `locale` 是真值參數，不再 `=> nil`。
# 架構＝docs/research/25 §6；drops 白名單暴露（安全邊界同節③）。
module ThemeEngine
  # 相容性遙測：未實作屬性的命中計數（25 §7）。跨執行緒 ⇒ 上鎖。
  MISS_MUTEX = Mutex.new
  MISSES = Hash.new(0)

  def self.count_miss(key)
    MISS_MUTEX.synchronize { MISSES[key] += 1 }
  end

  def self.miss_report(top: 40)
    MISS_MUTEX.synchronize { MISSES.sort_by { |_, c| -c }.first(top).to_h }
  end
end
