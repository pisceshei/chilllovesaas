# frozen_string_literal: true

# 主題渲染面的 CSP（Ella 整合修復 PR-1；2026-09-01 實錘根因 #1）。
#
# ①🔴 為什麼要放寬：主題是**商家作者內容**——Ella 每個 section 都靠
#   inline `<style>`（settings→CSS 變數、色階、逐 section 間距）與 inline
#   event handler／inline `<script>` 驅動。全域嚴格 CSP（style-src 'self'、
#   script-src 'self'+nonce）把這些全部封殺 ⇒ 前台退化成 Times New Roman
#   無圖無互動（本尊 storefront 對主題內容不設此類 CSP）。
# ②🔴 nonce 必須一併拿掉：CSP 規範裡 script-src 只要帶 nonce，'unsafe-inline'
#   即被忽略；而 inline event handler 只有 'unsafe-inline' 能放行 ⇒ 主題面
#   的回應要同時（a）改 policy（b）關 per-request nonce。
# ③admin SPA 不 include 本 concern——嚴格 CSP 原樣（信任邊界不同：admin 是
#   我方第一方代碼，主題面是商家內容）。
# ④img-src 加 https:：商品圖／外連圖（主題常引外部 CDN 圖）；其餘維持收斂。
module ThemeCsp
  extend ActiveSupport::Concern

  included do
    content_security_policy do |policy|
      policy.default_src :self
      policy.base_uri :self
      policy.connect_src :self
      policy.font_src :self, :data, :https
      policy.form_action :self
      # 編輯器 iframe 需要嵌入預覽（admin 同源）；公開面維持自家。
      policy.frame_ancestors :self
      policy.img_src :self, :data, :https
      policy.object_src :none
      policy.script_src :self, :unsafe_inline
      policy.style_src :self, :unsafe_inline
    end

    before_action :disable_csp_nonce_for_theme!
  end

  private

  # 關掉本請求的 nonce 產生器（見檔頭②——有 nonce 則 unsafe-inline 失效）。
  def disable_csp_nonce_for_theme!
    request.content_security_policy_nonce_generator = nil
  end
end
