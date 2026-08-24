# frozen_string_literal: true

module MediaPipeline
  # `media.uploaded` 的消費者（第 26 包；`Events::Consumers::REGISTRY` 的第一個真實住戶
  # ——63 §L-4 門檻已於第 25 包結清）。
  #
  # ①契約（Events::Consumers 檔頭）：`name`（進 event_deliveries.consumer，改名＝重放）
  #   ＋`call(event)`（冪等——at-least-once 下同一事件可能重叫）。
  # ②租戶：relay 已在 `with_tenant` 內呼叫（A 案），本消費者直接查即可。
  # ③🔴 失敗語義分兩類（見 ProcessFile ②）：檔案壞＝ProcessFile 內部標 failed 並正常
  #   返回（delivery done、不重試）；環境缺件／IO＝例外上拋（relay 退避重試）。
  # ④檔案已被刪除（事件比檔案活得久）＝視為已完成，不重試。
  module ProcessConsumer
    module_function

    def name = "media.process"

    # @param event [EventOutbox]
    def call(event)
      file_id = event.payload["file_id"]
      file = StoredFile.find_by(id: file_id)
      return if file.nil? # 檔案已刪：事件無主，不是錯誤

      MediaPipeline::ProcessFile.call(file)
    end
  end
end
