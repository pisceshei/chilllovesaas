# frozen_string_literal: true

module Tags
  # 標籤正規化的**唯一**實作（docs/specs/13 §F4.4；limits `collection.tag_normalize_*`）。
  #
  # ①這是什麼：把商家輸入的標籤字串折算成比對鍵 `tag_key`。寫入端（`product_tags` 落列）
  #   與查詢端（tag 條件的 EXISTS 求值）**共用這一支**——兩邊各寫一次必然漂移
  #   （13 §F4.3 配套 1 明文）。
  #
  # ②具體功能（六步，每步的依據）：
  #   | # | 步驟 | 依據 |
  #   |---|---|---|
  #   | 1 | Unicode NFKC（全形轉半形） | ours（V-136；與 13 §F6 CSV 全形清洗同族） |
  #   | 2 | 去前後空白；內部連續空白壓成單一 `-` | ours（V-136） |
  #   | 3 | `_`、`+`、`&` → `-` | ✅ 官方明載（help P9：四者視為等價） |
  #   | 4 | 連續 `-` 壓成單一；去前後 `-` | ours（V-136） |
  #   | 5 | casefold（大小寫摺疊，Ruby `downcase(:fold)`） | ours（V-136——官方未載明是否分大小寫） |
  #   | 6 | 長度校驗交呼叫端（`limits.product.tag_max_chars`；超過＝TOO_LONG 不截斷） | ✅ 官方值 |
  #
  #   例：`Red_New`／`red+new`／`RED & NEW`／`ｒｅｄ－ｎｅｗ` → 全部 `red-new`。
  #
  # ③🔴 配套約束（改這裡前先讀）：
  #   - `product_tags.tag_key` 的 collation＝`utf8mb4_bin`（migration 明文）——DB 不得
  #     用 ai_ci 疊自己的等價規則，等價**只有這六步一套**。
  #   - 步驟 2/4 的壓縮意味著 key 可能為**空**（輸入全是分隔符）⇒ 呼叫端遇空 key 跳過該標籤。
  #
  # ④跨功能影響：`Catalog::SaveProduct`（tags 變更同 tx 維護 product_tags）、
  #   `Collections::RuleCompiler`（tag 條件把商家輸入的條件值折成 key 再綁參數）、
  #   migration 20260826058000 的回填。訂單標籤上限是 40 不是 255
  #   （`limits.order.tag_max_chars`）——共用本函式但**不共用長度常數**。
  module Normalize
    module_function

    # @param raw [String, nil]
    # @return [String] 比對鍵；可能為空字串（輸入全是分隔符時）——呼叫端跳過
    def key(raw)
      value = raw.to_s.unicode_normalize(:nfkc)
      value = value.strip.gsub(/\s+/, "-")
      value = value.tr("_+&", "---")
      value = value.gsub(/-{2,}/, "-").delete_prefix("-").delete_suffix("-")
      value.downcase(:fold)
    end
  end
end
