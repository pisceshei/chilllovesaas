# frozen_string_literal: true

module Storefront
  # storefront 密碼頁（PR-10；chill.deals /password 標本逐層對表）。
  # 🔴 平台級頁（真店標本：零 script／零主題資產／自帶單一 style 塊）——
  # 走 Rails ERB 直渲染、**不進 Liquid 引擎**；結構與類名對表、品牌資產
  # （商標/字型/CSS 原文）依鐵律 9 換我方（標本用 ShopifySans＋Shopify 商標）。
  class PasswordController < BaseController
    skip_before_action :require_storefront_password, raise: false
    layout false
    helper_method :current_shop

    def show
      response.headers["X-Robots-Tag"] = "noindex, nofollow"
      render :show
    end

    def create
      shop = current_shop
      if shop.storefront_password_digest.present? &&
         BCrypt::Password.new(shop.storefront_password_digest) == params[:password].to_s
        cookies.signed[:cl_storefront_digest] = {
          value: Digest::SHA256.hexdigest(shop.storefront_password_digest),
          httponly: true, same_site: :lax
        }
        redirect_to "/"
      else
        flash.now[:password_error] = t_error
        response.headers["X-Robots-Tag"] = "noindex, nofollow"
        render :show, status: :unprocessable_entity
      end
    end

    private

    def t_error = "密碼不正確，請再試一次。"
  end
end
