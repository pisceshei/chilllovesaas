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

          if requested_cost > GraphqlLimits.fetch(:max_request_cost)
            return render_graphql_error(
              code: "MAX_COST_EXCEEDED",
              message: "查詢成本超過單次上限。",
              requested_cost:
            )
          end

          result = ChillloveSchema.execute(
            params[:query].to_s,
            variables:,
            operation_name: params[:operationName],
            context: { current_shop: Current.shop, current_staff: Current.staff }
          )
          payload = result.to_h
          normalize_top_level_errors!(payload)
          payload["extensions"] = payload.fetch("extensions", {}).merge(
            "cost" => GraphqlRequestCost.envelope(requested: requested_cost)
          )

          render json: payload, status: :ok
        rescue JSON::ParserError, TypeError
          render_graphql_error(code: "BAD_USER_INPUT", message: "variables 必須是有效的 JSON 物件。")
        rescue Pundit::NotAuthorizedError
          render_access_denied
        rescue ActiveRecord::ActiveRecordError => error
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
            raise TypeError unless parsed.is_a?(Hash)

            parsed
          when ActionController::Parameters
            raw_variables.to_unsafe_h
          when Hash
            raw_variables
          when nil
            {}
          else
            raise TypeError
          end
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

        def render_access_denied
          render_graphql_error(code: "ACCESS_DENIED", message: "沒有權限執行此操作。")
        end

        def render_graphql_error(code:, message:, requested_cost: GraphqlLimits.fetch(:object_cost))
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
