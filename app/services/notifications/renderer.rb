# frozen_string_literal: true

module Notifications
  # 通知模板渲染器（G6 步 6；89 §5 的官方變數契約落點）。
  #
  # ①這是什麼：subject＋body 的 Liquid 渲染。模板來源＝overlay（表列）→ 平台預設。
  # ②環境：獨立 Liquid::Environment，註冊主題引擎同一 Filters（money 族吃
  #   integer cents——鐵律 3 儲存尺度直通）；error_mode :lax（商家模板容錯，
  #   錯誤行輸出空字串不炸信）。
  # ③🔴 payload＝**攤平的 hash**（89 §5 官方句：email 模板的 order 屬性不帶
  #   `order.` 前綴；fulfillment 帶前綴）——由 Payloads 建構，本類不讀 DB。
  # ④money 符號＝runtime.rb 同款 v1 表（91 §3.48 已登記只承諾 HKD）。
  class Renderer
    ENVIRONMENT = Liquid::Environment.build do |e|
      e.error_mode = :lax
      e.register_filter(ThemeEngine::Filters)
    end

    Result = Data.define(:subject, :html)

    class << self
      # @param shop [Shop]
      # @param kind [String] Catalog::KINDS 之一
      # @param payload [Hash] 攤平 assigns（Payloads 產物）
      # @return [Result]
      def render(shop:, kind:, payload:)
        overlay = NotificationTemplate.find_by(shop_id: shop.id, channel: "email", key: kind)
        entry = Catalog.entry(kind)
        subject_src = overlay&.subject || entry.default_subject
        body_src = overlay&.body || Catalog.default_body(kind)

        Result.new(subject: render_one(subject_src, shop, payload),
                   html: render_one(body_src, shop, payload))
      end

      private

      def render_one(source, shop, payload)
        template = Liquid::Template.parse(source, environment: ENVIRONMENT)
        template.render(
          payload.deep_stringify_keys,
          registers: { money_symbol: money_symbol(shop), currency: shop.store_currency }
        )
      end

      # v1 符號表（與 ThemeEngine::Runtime#money_symbol 同款；91 §3.48）。
      def money_symbol(shop)
        { "HKD" => "HK$" }.fetch(shop.store_currency, "#{shop.store_currency} ")
      end
    end
  end
end
