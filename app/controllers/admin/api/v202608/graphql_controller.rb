# 商家後台 controller 使用的 namespace。
module Admin
  # Admin API controller 使用的 namespace。
  module Api
    # 2026-08 Admin API 實作的 namespace。
    module V202608
      # 執行正式的 2026-08、session-authenticated Admin GraphQL API。
      #
      # controller 統一加版本 header，維持 GraphQL top-level error 為
      # HTTP 200，並由 server-side Pundit 驗證 API boundary。見
      # docs/research/28 §0.1–0.4、docs/specs/12 F3。
      class GraphqlController < Admin::BaseController
        API_VERSION = "2026-08"

        # `variables` 不是合法 JSON 物件。
        #
        # 🔴 **為什麼要專屬例外，不能沿用 `TypeError`**（2026-08-15 收窄）：
        # 原本 `execute` 的 rescue 子句是 `rescue JSON::ParserError, TypeError`，
        # 而它是**方法層 rescue**——它包住整個方法體，`ChillloveSchema.execute` 就在裡面。
        # ⇒ **任何 resolver 內部拋出的 `TypeError` 都會被渲染成 `BAD_USER_INPUT`**。
        # 這不是假設：鐵律 3 的金額型別閘門（65 §C L3）就是靠 `raise TypeError` 擋住
        # 「把儲存值直接送 PSP」——那是 P1 級送款事故，卻會被這裡渲染成
        # 「variables 必須是有效的 JSON 物件」，前端顯示一個與事實無關的訊息，
        # 而真正的事故訊息**一個字都不會出現在 log 以外的地方**。
        # ⇒ 只 rescue 我方自己在 `normalized_variables` 裡拋出的這一個型別。
        InvalidVariables = Class.new(StandardError)

        rescue_from ActionController::InvalidAuthenticityToken, with: :render_access_denied

        prepend_before_action :set_api_version_header
        after_action :set_api_version_header

        # 在 tenant/staff context 中執行一份 GraphQL document。
        #
        # @note 副作用：執行 Pundit、可能查詢資料庫，並 render HTTP 200 JSON；
        #   每個 payload 都附 `extensions.cost` 與 API version header。
        # @return [void]
        # @see docs/research/28-api-contract.md §0.1–0.4
        def execute
          authorize :admin_api, :execute?
          variables = normalized_variables(params[:variables])
          requested_cost = GraphqlRequestCost.calculate(query: params[:query], variables:)

          if requested_cost > GraphqlLimits.fetch(:max_query_cost_points)
            return render_graphql_error(
              code: "MAX_COST_EXCEEDED",
              message: "查詢成本超過單次上限。",
              requested_cost:
            )
          end

          # 伺服端訊息（userErrors.message）依員工介面語言（67 §E.1；ML-1）。
          # 未登入／未設定時走平台預設，不得落到 Rails 的 :en 以外的隱含值。
          result = I18n.with_locale(ui_locale_for(Current.staff)) do
            ChillloveSchema.execute(
              params[:query].to_s,
              variables:,
              operation_name: params[:operationName],
              context: { current_shop: Current.shop, current_staff: Current.staff }
            )
          end
          payload = result.to_h
          normalize_top_level_errors!(payload)
          payload["extensions"] = payload.fetch("extensions", {}).merge(
            "cost" => GraphqlRequestCost.envelope(requested: requested_cost)
          )

          render json: payload, status: :ok
        rescue InvalidVariables
          render_graphql_error(code: "BAD_USER_INPUT", message: "variables 必須是有效的 JSON 物件。")
        rescue Pundit::NotAuthorizedError
          render_access_denied
        # 🔴 **`RecordNotUnique` 必須排在下一條之前**——實測
        #    `ActiveRecord::RecordNotUnique <= ActiveRecord::StatementInvalid` 為 **true**。
        #    少了這個子句，`63` §A.1 ④ 最在意的那個例外會被下一條原封不動再吞一次。
        rescue ActiveRecord::RecordNotUnique
          # 業務錯誤：`63` §A.1 ④ 要求在 mutation 層轉成 userErrors，「**不得漏成 500**」。
          # 落到這裡代表那一層漏了 ⇒ **刻意不吞**，讓它爆出來。
          raise
        # 🔴 **本 rescue 由 `ActiveRecord::ActiveRecordError` 收窄而來**（2026-08-15）。
        #    原本那條是**方法層** rescue，而 `ChillloveSchema.execute` 就在方法體裡
        #    ⇒ resolver 內部拋出的**任何** AR 例外都被渲染成 `INTERNAL`／HTTP 200，
        #    而 `render_internal_error` 只 log `error_class`，訊息一個字都不留。
        #    ⚠️ 這與本檔上方那個 `TypeError` 事故**是同一種病**，只是型別換了一個。
        #    被錯誤吞掉的具體例子：`RecordInvalid`、`StaleObjectError`
        #    （`28` §0.3.2 明定樂觀鎖走 `STALE_OBJECT` userErrors）、`RecordNotFound`
        #    ——實測這三個**都不是** `StatementInvalid` 的子類，收窄後不再被吞。
        #    ℹ️ 今天還不可達（`ChillloveSchema.mutation` 為 `nil`，唯讀 schema），
        #    但**第一支 mutation 掛上 root 當天就引爆**。
        rescue ActiveRecord::StatementInvalid,
               ActiveRecord::ConnectionNotEstablished => error
          # 只有基礎設施錯誤走去敏 INTERNAL。實測涵蓋關係：
          #   QueryCanceled／LockWaitTimeout／Deadlocked ⊂ StatementInvalid
          #   ConnectionTimeoutError ⊂ ConnectionNotEstablished
          render_internal_error(error)
        end

        private

        # 只把可預期的 DB 基礎設施錯誤轉成去敏 INTERNAL；NoMethodError 等
        # 程式錯誤刻意交給 Rails exception handling，避免 broad rescue 隱藏 bug。
        def render_internal_error(error)
          Rails.logger.error(
            message: "admin_graphql_internal_error",
            request_id: request.request_id,
            shop_id: Current.shop&.id,
            error_class: error.class.name
          )
          render_graphql_error(code: "INTERNAL", message: "伺服器暫時無法完成請求。")
        end

        def normalized_variables(raw_variables)
          case raw_variables
          when String
            parsed = raw_variables.blank? ? {} : JSON.parse(raw_variables)
            raise InvalidVariables unless parsed.is_a?(Hash)

            parsed
          when ActionController::Parameters
            raw_variables.to_unsafe_h
          when Hash
            raw_variables
          when nil
            {}
          else
            raise InvalidVariables
          end
        rescue JSON::ParserError
          # 🔴 在**這裡**轉型別而不是在 `execute` 的方法層 rescue——
          # 方法層 rescue 會連 `ChillloveSchema.execute` 內部的解析錯誤一起吞掉。
          raise InvalidVariables
        end

        def normalize_top_level_errors!(payload)
          payload.fetch("errors", []).each do |error|
            error["extensions"] ||= {}
            error["extensions"]["code"] ||= "GRAPHQL_VALIDATION_FAILED"
            error["extensions"]["requestId"] ||= request.request_id
          end
        end

        def set_api_version_header
          response.set_header("X-CL-API-Version", API_VERSION)
        end

        def handle_unauthenticated
          render_graphql_error(code: "ACCESS_DENIED", message: "帳號或密碼錯誤。")
        end

        def handle_not_authorized
          render_access_denied
        end

        # 員工介面語言 → Rails I18n locale；值域外或未登入走平台預設（limits i18n.admin.ui_locale_default）。
        def ui_locale_for(staff)
          allowed = Limits.fetch(:i18n, :admin, :ui_locales).map(&:to_s)
          tag = staff&.locale.to_s
          (allowed.include?(tag) ? tag : Limits.fetch(:i18n, :admin, :ui_locale_default).to_s).to_sym
        end

        def render_access_denied
          render_graphql_error(code: "ACCESS_DENIED", message: "沒有權限執行此操作。")
        end

        def render_graphql_error(code:, message:, requested_cost: GraphqlLimits.fetch(:object_cost_points))
          render json: {
            errors: [
              {
                message:,
                extensions: { code:, requestId: request.request_id }
              }
            ],
            extensions: {
              cost: GraphqlRequestCost.envelope(requested: requested_cost, actual: 0)
            }
          }, status: :ok
        end
      end
    end
  end
end
