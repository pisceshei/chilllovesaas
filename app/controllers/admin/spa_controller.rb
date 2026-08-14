# 商家後台 controller 使用的 namespace。
module Admin
  # 為 client-side route 提供已驗證的 React admin shell。
  #
  # 所有資料操作仍只走版本化 Admin GraphQL API；本 controller 不提供 REST
  # resource action。見 HANDOFF.md D5、docs/research/28 §0.1。
  class SpaController < BaseController
    layout "admin"

    # 授權並 render 共用的 admin SPA 入口。
    #
    # @note 副作用：執行 Pundit 授權並設定 view 使用的品牌名稱。
    # @return [void]
    # @see docs/specs/12-spec-tenancy-auth-permissions.md F3
    def show
      authorize :admin_shell, :show?
      @brand_name = Rails.configuration.x.brand.name
    end
  end
end
