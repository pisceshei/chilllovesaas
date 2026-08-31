# frozen_string_literal: true

module Types
  module Inputs
    # 追蹤資訊輸入（G6-8；對位本尊 FulfillmentTrackingInput——官方五欄
    # company/number/numbers/url/urls，取證 2026-09-01。numbers/urls 平行陣列
    # 「matched … correspondingly their positions in the arrays」逐字）。
    #
    # 我方形＝company＋單複數兩形擇一（服務層合併成物件陣列儲存）。
    class FulfillmentTrackingInput < GraphQL::Schema::InputObject
      graphql_name "FulfillmentTrackingInput"
      description "出貨追蹤資訊（number/url 單數形與 numbers/urls 複數形擇一）"

      argument :company, String, required: false, description: "物流商名稱"
      argument :number, String, required: false, description: "單一追蹤號"
      argument :url, String, required: false, description: "單一追蹤連結"
      argument :numbers, [ String ], required: false, description: "多追蹤號（與 urls 按位對應）"
      argument :urls, [ String ], required: false, description: "多追蹤連結"
    end
  end
end
