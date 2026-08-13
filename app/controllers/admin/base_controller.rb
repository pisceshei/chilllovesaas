# 商家後台 controller 使用的 namespace。
module Admin
  # 所有 admin 頁面的 server-side 認證與授權基底。
  #
  # 每個 action 前要求有效 staff session，action 後要求 Pundit 已完成授權；
  # callback 可能 redirect 或 raise 未授權錯誤。見 docs/specs/12 F2/F3。
  class BaseController < ApplicationController
    before_action :authenticate_staff!
    after_action :verify_authorized
  end
end
