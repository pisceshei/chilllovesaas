# frozen_string_literal: true

module Types
  # 顧客（G6-7；契約＝docs/research/28 §7 的欄位面最小集＋74 §1 列表五欄所需）。
  #
  # - 統計三欄（ordersCount／amountSpent／lastOrderAt）＝customers 表的 rollup
  #   快取欄直讀（鐵律 7：與列表、詳情 KPI、報表同一來源；寫入端唯一＝
  #   Customers::UpsertFromCheckout）。
  # - `amountSpent` 走 MoneyV2 序列化（鐵律 3：cents 不裸出 API）。
  # - consent 欄＝boolean 快取＋最後變更中繼（六值狀態機隨顧客模組全量包，
  #   屆時本型別擴 emailMarketingConsent object——先出 boolean 是刻意最小面）。
  class CustomerType < BaseObject
    graphql_name "Customer"
    description "顧客 profile（訂單成立自動建檔或後台建立）"

    implements Interfaces::Node

    field :legacy_resource_id, ID, null: false, method: :id
    field :email, String, null: true
    field :first_name, String, null: true
    field :last_name, String, null: true
    field :display_name, String, null: false, description: "姓名；缺項回落 email"
    field :phone, String, null: true
    field :state, String, null: false, description: "enabled/disabled/invited/declined"
    field :note, String, null: true
    field :tags, [ String ], null: false
    field :tax_exempt, Boolean, null: false
    field :email_marketing_consent, Boolean, null: false,
          description: "email 行銷同意（boolean 快取；狀態機隨顧客模組全量包）"
    field :email_marketing_consent_updated_at, GraphQL::Types::ISO8601DateTime, null: true
    field :email_marketing_consent_source, String, null: true, description: "如 checkout"
    field :sms_marketing_consent, Boolean, null: false
    # 步 8a：官方狀態機投影（enum 值上行大寫化；事件表＝事實來源）。
    field :email_marketing_state, String, null: false,
          description: "NOT_SUBSCRIBED/PENDING/SUBSCRIBED/UNSUBSCRIBED/REDACTED/INVALID（官方六值）"
    field :sms_marketing_state, String, null: false,
          description: "官方五值（無 INVALID）"
    field :redaction_scheduled_at, GraphQL::Types::ISO8601DateTime, null: true,
          description: "個資抹除排程時點（null＝無待執行請求）"
    field :anonymized_at, GraphQL::Types::ISO8601DateTime, null: true
    field :addresses, [ CustomerAddressType ], null: false, description: "地址簿（預設在前）"
    field :orders_count, Integer, null: false
    field :amount_spent, MoneyV2Type, null: false, description: "消費總額（rollup 快取）"
    field :last_order_at, GraphQL::Types::ISO8601DateTime, null: true
    field :default_address, CustomerAddressType, null: true
    field :last_order, OrderType, null: true,
          description: "最新一張訂單（G6-6a；詳情頁「最近訂單」卡的來源）"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false

    def email_marketing_state = object.email_marketing_state.upcase

    def sms_marketing_state = object.sms_marketing_state.upcase

    def addresses
      CustomerAddress.where(shop_id: object.shop_id, customer_id: object.id)
                     .order(default_address: :desc, id: :asc)
    end

    def id
      "gid://chilllove/Customer/#{object.id}"
    end

    def tags
      Array(object.tags)
    end

    def amount_spent
      { cents: object.total_spent_cents, currency: object.currency }
    end

    def last_order
      object.orders.order(processed_at: :desc, id: :desc).first
    end
  end
end
