# frozen_string_literal: true

module Psp
  module Airwallex
    # Airwallex HTTP client（G6-1a；digest §H 定值，逐項帶取證）。
    #
    # ①認證：`POST /api/v1/authentication/login`（x-client-id／x-api-key 標頭）→
    #   Bearer token；**expires_at 為準**（官方 30 分鐘，不寫死——limits
    #   `token_refresh_safety_seconds` 提前重登）。
    # ②host 由 provider 列的 `environment` 決定（limits `psp_integration.airwallex.hosts`；
    #   跨環境禁用＝limits `psp_credentials.cross_environment_use_forbidden`）。
    # ③🔴 **金額＝JSON number 原文注入**（65 §B X7c）：`BigDecimal#to_json` 預設吐字串、
    #   `to_f` 是鐵律 3 違規 ⇒ `post_json` 收 `amount_psp_number:`（C2 後綴），把
    #   `to_s("F")` 的十進位字面直接拼進 body 的 `"amount":` 位。
    # ④transport 可注入（specs 用 fake；生產＝Net::HTTP）——不引新 HTTP gem（鐵律 1）。
    class Client
      Error = Class.new(StandardError)
      # 401／403：憑證或權限問題——訊息帶 Airwallex 的 code，不帶任何祕密。
      Unauthorized = Class.new(Error)

      # @param provider [ShopPaymentProvider] airwallex 列（解密 getter 供憑證）
      # @param transport [#call, nil] `(Net::HTTP::Generic, URI) → Net::HTTPResponse`；nil＝真連線
      def initialize(provider, transport: nil)
        raise ArgumentError, "provider 必須是 airwallex 列" unless provider.provider == "airwallex"

        @provider = provider
        @transport = transport || method(:real_transport)
        @token = nil
        @token_expires_at = nil
      end

      # 送一個 JSON POST；`amount_psp_number:` 非 nil 時以原文注入 `"amount"`。
      #
      # @param path [String]
      # @param payload [Hash] 不含 amount 的其餘欄位
      # @param amount_psp_number [BigDecimal, nil] `to_payload` 產物（R7）
      # @return [Hash] 解析後的回應（🔴 金額欄位不在本層轉換——入向走 Money.from_psp_amount）
      def post_json(path, payload, amount_psp_number: nil)
        body = JSON.generate(payload)
        if amount_psp_number
          unless amount_psp_number.is_a?(BigDecimal)
            raise TypeError, "amount_psp_number 只收 BigDecimal（鐵律 3：Float 即 bug），實得 #{amount_psp_number.class}"
          end

          # 🔴 整數值不得帶 `.0` 尾：零小數幣別（JPY 等，Airwallex 覆蓋表）語義上
          # 「帶小數即形不符」——`BigDecimal("1480").to_s("F")` 是 "1480.0"，
          # 對 0 位幣別要送 `1480`。A6c 已保證 scale ≤ 生效位數 ⇒ 整數判定即足。
          literal = amount_psp_number.frac.zero? ? amount_psp_number.to_i.to_s : amount_psp_number.to_s("F")
          body = body.sub(/\A\{/, %({"amount":#{literal},))
        end
        request(Net::HTTP::Post, path, body:)
      end

      # @param path [String]
      # @return [Hash]
      def get_json(path)
        request(Net::HTTP::Get, path)
      end

      private

      def request(klass, path, body: nil)
        req = klass.new(path)
        req["Authorization"] = "Bearer #{token!}"
        req["Content-Type"] = "application/json"
        req["x-api-version"] = Limits.fetch(:psp_integration, :airwallex, :api_version)
        req.body = body if body
        res = @transport.call(req, base_uri)
        parse!(res, path)
      end

      # 登入並快取 token（expires_at 減 safety 秒；缺 expires_at ⇒ 不快取、每次重登）。
      def token!
        return @token if @token && @token_expires_at && Time.current < @token_expires_at

        req = Net::HTTP::Post.new(Limits.fetch(:psp_integration, :airwallex, :login_path))
        req["x-client-id"] = @provider.client_id.to_s.strip
        req["x-api-key"] = @provider.api_secret.to_s.strip
        req["Content-Type"] = "application/json"
        data = parse!(@transport.call(req, base_uri), "login")
        @token = data.fetch("token")
        if (expires = data["expires_at"])
          safety = Limits.fetch(:psp_integration, :airwallex, :token_refresh_safety_seconds)
          @token_expires_at = Time.zone.parse(expires.to_s) - safety
        end
        @token
      end

      def parse!(res, path)
        code = res.code.to_i
        data = begin
          JSON.parse(res.body.to_s)
        rescue JSON::ParserError
          {}
        end
        return data if code < 400

        message = "Airwallex #{path} 回 #{code}（code=#{data['code'].inspect}）"
        raise Unauthorized, message if [ 401, 403 ].include?(code)

        raise Error, "#{message} #{data['message'].inspect}"
      end

      def base_uri
        env = @provider.environment
        host = Limits.fetch(:psp_integration, :airwallex, :hosts, env.to_sym)
        URI("https://#{host}")
      end

      def real_transport(req, uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = Limits.fetch(:psp_integration, :airwallex, :request_timeout_seconds)
        http.read_timeout = Limits.fetch(:psp_integration, :airwallex, :request_timeout_seconds)
        http.request(req)
      end
    end
  end
end
