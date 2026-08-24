# frozen_string_literal: true

module Mutations
  # 媒體 mutation 的共用底座（第 27 包）：商品解析＋授權。
  #
  # 授權沿用 `ProductPolicy#create?`（products.edit）——媒體是商品的一部分，
  # 不另立權限鍵；檔案庫本身的權限是 `StoredFilePolicy`（第 25 包）。
  class BaseMediaMutation < BaseMutation
    private

    # @return [Product]
    # @raise [GraphQL::ExecutionError] 無權限／找不到商品
    def authorized_product!(product_id)
      staff = context[:current_staff]
      unless staff && ProductPolicy.new(staff, Product).create?
        raise GraphQL::ExecutionError.new("沒有權限寫入商品。", extensions: { "code" => "ACCESS_DENIED" })
      end

      shop = context.fetch(:current_shop)
      legacy_id = product_id.to_s[%r{\Agid://chilllove/Product/(\d+)\z}, 1]
      product = legacy_id && Product.where(shop_id: shop.id).find_by(id: legacy_id.to_i)
      raise GraphQL::ExecutionError.new("找不到商品。", extensions: { "code" => "NOT_FOUND" }) if product.nil?

      product
    end

    def legacy_media_id(gid)
      gid.to_s[%r{\Agid://chilllove/Media/(\d+)\z}, 1]&.to_i
    end

    def user_errors_from(result) = result.user_errors.map { |e| e.slice(:field, :message, :code) }
  end
end
