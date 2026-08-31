# frozen_string_literal: true

module Mutations
  # 請款模式更新（G6-3 步 2；86 §2 modal 實測——radio 恰三值，說明句逐字
  # 「Payments are authorized when an order is placed. Select how to capture payments:」）。
  #
  # 值域正典＝limits capture.modes（四值）；automatic_per_fulfillment 官方標
  # 🔴 僅 Shopify Plus——我方無方案分層 ⇒ 該值回 FEATURE_NOT_ENABLED（誠實拒絕，
  # 不靜默收下一個沒有行為的設定值）。
  #
  # ⚠️ 消費端誠實登記：G6-1 的 Airwallex 流是即時 capture（無 authorization 流）
  # ⇒ 本欄目前是設定面完整、行為面待 authorization 流（capture.modes 的行為消費者
  # 隨 orderCapture 完整版落地）。dev doc 同記。
  class PaymentCaptureMethodUpdate < BaseMutation
    graphql_name "PaymentCaptureMethodUpdate"
    description "更新付款請款模式（automatic_at_checkout／automatic_after_fulfilled／manual）。"

    user_errors_type Types::Errors::PaymentCaptureMethodUserErrorType

    argument :capture_method, String, required: true

    field :payment_capture_method, String, null: true

    def resolve(capture_method:)
      enforce_idempotency_contract!(nil)
      shop = authorized_shop!

      modes = Limits.enum(:capture, :modes).map(&:downcase)
      plus_only = Limits.enum(:capture, :plus_only_modes).map(&:downcase)
      unless modes.include?(capture_method)
        return { payment_capture_method: nil,
                 user_errors: [ { field: [ "captureMethod" ],
                                  message: "請款模式不在允許值域內。", code: "INCLUSION" } ] }
      end
      if plus_only.include?(capture_method)
        return { payment_capture_method: nil,
                 user_errors: [ { field: [ "captureMethod" ],
                                  message: "此請款模式尚未開放（本尊為 Plus 專屬）。",
                                  code: "FEATURE_NOT_ENABLED" } ] }
      end

      shop.update!(payment_capture_method: capture_method)
      { payment_capture_method: capture_method, user_errors: [] }
    end

    private

    # 登入態即可（與 shopPaymentProviderSet 同門檻：settings 細粒度權限隨 M5 RBAC
    # 展開——「settings.edit」尚不存在於 RBAC 種子，先驗會鎖死全部非 owner 員工）。
    def authorized_shop!
      unless context[:current_staff]
        raise GraphQL::ExecutionError.new("需要登入。", extensions: { "code" => "ACCESS_DENIED" })
      end

      context.fetch(:current_shop)
    end
  end
end
