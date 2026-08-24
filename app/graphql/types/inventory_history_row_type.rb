# frozen_string_literal: true

module Types
  # 調整記錄頁的一列＝一次調整（一個 group 對某個 level 的子行）。
  #
  # 實測欄集（94 §2.5，7 欄）：Date｜Activity｜Created by｜Unavailable｜Committed｜Available｜On hand。
  # `activity` 是 reason 的顯示標籤（對照表＝總裁定 §四b），**由前端 i18n 化**——
  # 本欄回識別字，不回已翻譯字串（本尊的 displayName 是已本地化的，我方刻意不照抄那個形態：
  # 拿 API 回的英文當顯示值等於把翻譯權交給後端，五語就對不齊了）。
  class InventoryHistoryRowType < BaseObject
    graphql_name "InventoryHistoryRow"
    description "庫存調整歷程的一列。"

    field :id, ID, null: false
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :reason, String, null: false, description: "reason 識別字；顯示標籤由前端對照 i18n。"
    field :mutation_kind, String, null: false, description: "adjust／set／move／activate（稽核）。"
    field :created_by, String, null: true,
      description: "員工姓名；系統／app 事件回 client_source（admin_web／api／import…）。"
    field :reference_document_uri, String, null: true, description: "答「為什麼動」（純稽核，不去重）。"
    field :ledger_document_uri, String, null: true, description: "該筆分錄文件（available 以外必有）。"
    field :changes, [ Types::InventoryHistoryChangeType ], null: false,
      description: "有變動的數量欄各一筆（delta 非零者）；每筆帶 quantityAfterChange。"

    def id = "gid://chilllove/InventoryHistoryRow/#{object.id}"

    # 員工優先；系統／app 事件回 client_source——實測「Created by」欄同時承載
    # 員工（KEN LEE）與 app（Fecify）兩種身分（94 §2.5）。
    # 🔴 我方 `staff_members` **沒有 name 欄**（只有 email），所以顯示的是 email；
    #    要顯示姓名得先加欄，屬 M5 RBAC 展開時一併做（本包登記不做）。
    #    該表依鐵律 2 白名單不帶 shop_id，故查詢無需 tenant 包裹。
    # 🔴 一次查完整頁的 email，不逐列查。
    # 逐列 `pick(:email)` 在滿頁時是 N 次額外 SELECT——本包才剛在列表端用
    # 一個 JOIN 把 N+1 擋掉（`Inventory::ItemsQuery`），歷程端不該自己再開一個。
    # 用 `context` 當請求級快取：同一次 GraphQL 執行只查一次 staff_members。
    def created_by
      staff_id = object.staff_member_id
      if staff_id
        email = staff_emails[staff_id]
        return email if email.present?
      end
      object.client_source
    end

    def changes
      Inventory::HistoryQuery::QUANTITY_NAMES.filter_map do |name|
        delta = object.deltas.fetch(name)
        next if delta.zero?

        { name:, delta:, after: object.after.fetch(name) }
      end
    end

    private

    # 該次請求所有歷程列的 staff_member_id → email。
    # 🔴 `private` 一定要在所有 **GraphQL field 解析方法之後**——
    # 放在 `changes` 之前會讓 graphql-ruby 找不到它（"which did not exist"），
    # 整個 changes 欄位在執行期炸掉。這次就是這樣紅了三條 spec。
    # `staff_members` 依鐵律 2 白名單不帶 shop_id，故查詢無需 tenant 包裹。
    def staff_emails
      context[:inventory_history_staff_emails] ||= begin
        ids = Array(context[:inventory_history_staff_ids]).compact.uniq
        ids.empty? ? {} : StaffMember.where(id: ids).pluck(:id, :email).to_h
      end
    end
  end
end
