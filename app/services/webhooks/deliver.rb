# frozen_string_literal: true

require "net/http"

module Webhooks
  # 單次 webhook 投遞（步 20a；28 §15 headers＋18 F4 紅線）。
  #
  # ①🔴 投遞時 UrlGuard 再驗（DNS rebinding——18 F4）＋以 vetted IP 直連
  #   （Net::HTTP#ipaddr；Host/SNI 仍用原主機名）；不跟 redirect（3xx＝失敗）。
  # ②headers＝28 §15 七件：Topic/Shop-Domain/Webhook-Id/Event-Id/Triggered-At/
  #   API-Version/Hmac-Sha256（base64(HMAC-SHA256(raw body, secret))）。
  # ③timeout 5s、回應存檔截 1KB（讀取上限 64KB——18 F4）；成功＝2xx。
  class Deliver
    API_VERSION = "2026-08"

    Result = Struct.new(:ok, :status_code, :duration_ms, :error, keyword_init: true) do
      def ok? = ok
    end

    def self.call(subscription:, event:, shop:)
      new(subscription:, event:, shop:).call
    end

    def initialize(subscription:, event:, shop:)
      @subscription = subscription
      @event = event
      @shop = shop
    end

    def call
      uri, vetted_ip = UrlGuard.vet!(@subscription.url)
      body = JSON.generate(@event.payload)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = post!(uri, vetted_ip, body)
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      ok = response.code.to_i.between?(200, 299)
      record!(ok ? "sent" : "failed", status_code: response.code.to_i,
              duration_ms:, excerpt: response.body.to_s.byteslice(0, 1024))
      Result.new(ok:, status_code: response.code.to_i, duration_ms:)
    rescue UrlGuard::GuardError, SocketError, Timeout::Error, SystemCallError,
           OpenSSL::SSL::SSLError, Net::ProtocolError => e
      record!("failed", excerpt: e.class.name)
      Result.new(ok: false, error: e.class.name)
    end

    private

    def post!(uri, vetted_ip, body)
      timeout = Limits.fetch(:webhook, :delivery_timeout_seconds)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.ipaddr = vetted_ip # 🔴 直連 vetted IP（rebinding 窗關閉）
      http.open_timeout = timeout
      http.read_timeout = timeout
      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      headers(body).each { |key, value| request[key] = value }
      request.body = body
      http.start { |conn| conn.request(request) }
    end

    def headers(body)
      {
        "X-CL-Topic" => @event.topic,
        "X-CL-Shop-Domain" => @shop.subdomain.to_s,
        "X-CL-Webhook-Id" => SecureRandom.uuid,
        "X-CL-Event-Id" => @event.event_id,
        "X-CL-Triggered-At" => @event.created_at.utc.iso8601,
        "X-CL-API-Version" => API_VERSION,
        "X-CL-Hmac-Sha256" => Base64.strict_encode64(
          OpenSSL::HMAC.digest("SHA256", @subscription.secret, body)
        )
      }
    end

    def record!(state, status_code: nil, duration_ms: nil, excerpt: nil)
      ActsAsTenant.without_tenant do
        WebhookDelivery.create!(shop_id: @shop.id, webhook_subscription_id: @subscription.id,
                                event_id: @event.event_id, state:, status_code:,
                                duration_ms:, response_excerpt: excerpt)
      end
    end
  end
end
