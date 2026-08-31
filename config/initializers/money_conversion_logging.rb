# frozen_string_literal: true

# 65 §K.8–9 的日誌落點（G6-1a）：金額 PSP 轉換的結構化 JSON 日誌＋P1 失敗記錄。
#
# ①K.8：每次 X7／X8 轉換一行 JSON（欄位＝§K.8 逐項；事件源在 `Money.instrument_conversion`）。
# ②K.9：四類轉換例外＝**P1**（上游算錯或 pack 沒宣告）——記 error 級＋`"severity":"P1"`
#   欄；日後接告警管道時以此欄位路由，**本檔不發明告警基建**（尚無外部告警通道）。
# ③🔴 祕密永不入日誌：payload 只有金額與宣告參數，無任何憑證欄。
ActiveSupport::Notifications.subscribe("money.psp_conversion") do |event|
  Rails.logger.info({ event: "money.psp_conversion" }.merge(event.payload).to_json)
end

ActiveSupport::Notifications.subscribe("money.psp_conversion_failure") do |event|
  Rails.logger.error({ event: "money.psp_conversion_failure" }.merge(event.payload).to_json)
end
