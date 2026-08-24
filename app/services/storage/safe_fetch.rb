# frozen_string_literal: true

require "resolv"

module Storage
  # SSRF 防護抓檔（第 25 包；12 §B.6:155 嚴格版——fileCreate originalSource 外部 URL 路徑）。
  #
  # ①防線四道（缺一＝SSRF）：
  #   - scheme 僅 http/https（12 §B.6；§C.7 寫「僅 https」＝較鬆敘述，聯集後從 §B.6
  #     取 http/https，worklog 登記兩處不一致）。
  #   - DNS 解析後逐 IP 驗（🔴 審查 C1：**先抽出 IPv6 transition 形式嵌入的 IPv4**
  #     ——NAT64 64:ff9b::/96、6to4 2002::/16、v4-compat ::/96、v4-mapped ::ffff:/96
  #     ——再對內層與本體套私網/loopback/link-local/CGN/metadata/reserved 判定。
  #     純 denylist 會漏掉這些嵌入形式（IPv6-only + DNS64 網路上 64:ff9b::a00:5
  #     會被核心翻成內網 10.0.0.5）。
  #   - 🔴 連線釘選已驗 IP（`Net::HTTP#ipaddr=`）——僅驗 DNS 擋不住 rebinding：
  #     驗證時回公網 IP、連線時二次解析換私網 IP（12 §B.6 逐字警告）。TLS 憑證
  #     仍以主機名驗（ipaddr= 保留 SNI／hostname verification）。
  #   - redirect ≤ limits `outbound_http.file_fetch_redirect_hops_max`，每跳重走全套驗證。
  # ②尺寸＝streaming 累計，超過 `file_fetch_download_bytes_max` 即斷線——🔴 審查 C0：
  #   **非 2xx（redirect/4xx/5xx）與 redirect 響應體同樣 cap**，不得靠 Net::HTTP 隱式
  #   讀完整 body（攻擊者用 404＋數 GB body 打 OOM）。
  # ③逾時＝`file_fetch_timeout_seconds`（open＋read 各自設）。
  class SafeFetch
    class Blocked < StandardError; end
    class TooLarge < StandardError; end

    Result = Data.define(:body, :content_type)

    class << self
      # @param url [String]
      # @return [Result]
      def call(url)
        fetch(url, hops_left: Limits.fetch(:outbound_http, :file_fetch_redirect_hops_max))
      end

      # 🔴 審查 C1：允許連線的判定＝抽出嵌入 IPv4 後，內層與本體都不落私網等保留域。
      # 對外導出供 spec 直接驗矩陣。
      # @return [Boolean] true＝該拒
      def blocked_ip?(address)
        ip = IPAddr.new(address.to_s)
        embedded = embedded_ipv4(ip)
        return true if embedded && reserved_ipv4?(embedded)

        reserved?(ip)
      rescue IPAddr::InvalidAddressError
        true
      end

      private

      # IPv6 transition 形式 → 內層 IPv4（無則 nil）。用固定前綴 include? 判別，
      # 避免手算位移弄錯（NAT64 前綴曾算錯，實測抓到）。
      def embedded_ipv4(ip)
        return nil unless ip.ipv6?

        value = ip.to_i
        low = value & 0xffff_ffff # NAT64／v4-mapped／v4-compat 的 IPv4 都在低 32 bit
        return IPAddr.new(low, Socket::AF_INET) if IPAddr.new("64:ff9b::/96").include?(ip) && low.positive?
        return IPAddr.new(low, Socket::AF_INET) if IPAddr.new("::ffff:0:0/96").include?(ip) && low.positive?
        return IPAddr.new(low, Socket::AF_INET) if IPAddr.new("::/96").include?(ip) && low > 1 # 排除 ::／::1
        # 6to4 2002:WWXX:YYZZ::/16 → IPv4 在 bit 16-47（>>80）
        return IPAddr.new((value >> 80) & 0xffff_ffff, Socket::AF_INET) if IPAddr.new("2002::/16").include?(ip)

        nil
      rescue IPAddr::InvalidAddressError
        nil
      end

      def reserved?(ip)
        return reserved_ipv4?(ip) if ip.ipv4?

        ip.loopback? || ip.private? || ip.link_local? ||
          IPAddr.new("::/128").include?(ip) ||       # 未指定
          IPAddr.new("fc00::/7").include?(ip) ||     # ULA（部分 Ruby 版 private? 未涵蓋）
          IPAddr.new("fe80::/10").include?(ip) ||    # link-local
          IPAddr.new("ff00::/8").include?(ip)        # multicast
      end

      def reserved_ipv4?(ip)
        ip.loopback? || ip.private? || ip.link_local? ||
          IPAddr.new("100.64.0.0/10").include?(ip) ||   # CGN/RFC6598
          IPAddr.new("169.254.0.0/16").include?(ip) ||  # link-local/metadata
          IPAddr.new("192.0.0.0/24").include?(ip) ||    # IETF protocol
          IPAddr.new("198.18.0.0/15").include?(ip) ||   # benchmarking
          IPAddr.new("0.0.0.0/8").include?(ip) ||       # this-network/未指定
          IPAddr.new("224.0.0.0/4").include?(ip) ||     # multicast
          IPAddr.new("240.0.0.0/4").include?(ip)        # reserved（含 255.255.255.255）
      end

      def fetch(url, hops_left:)
        uri = URI.parse(url.to_s)
        raise Blocked, "scheme not allowed" unless %w[http https].include?(uri.scheme)
        raise Blocked, "host missing" if uri.host.blank?

        ip = resolve_and_validate!(uri.host)
        status, headers, body = request(uri, ip)

        if status.between?(300, 399)
          raise Blocked, "too many redirects" if hops_left <= 0

          location = headers["location"].to_s
          raise Blocked, "redirect without location" if location.blank?

          target = URI.join(uri, location).to_s
          fetch(target, hops_left: hops_left - 1) # 每跳重走全套驗證
        elsif status.between?(200, 299)
          Result.new(body:, content_type: headers["content-type"].to_s)
        else
          raise Blocked, "upstream returned #{status}"
        end
      end

      def resolve_and_validate!(host)
        addresses = Resolv.getaddresses(host)
        raise Blocked, "unresolvable host" if addresses.empty?

        addresses.each do |address|
          raise Blocked, "address not allowed" if blocked_ip?(address)
        end
        addresses.first
      end

      # @return [Array(Integer, Hash, String)] [status, headers, capped_body]
      #   🔴 body 一律 streaming 累計並 cap（不論狀態）——非 success 也不得隱式讀完整 body。
      def request(uri, pinned_ip)
        timeout = Limits.fetch(:outbound_http, :file_fetch_timeout_seconds)
        max_bytes = Limits.fetch(:outbound_http, :file_fetch_download_bytes_max)
        http = Net::HTTP.new(uri.host, uri.port)
        http.ipaddr = pinned_ip # 連線釘選（rebinding 防線）；SNI 與憑證仍照 uri.host
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.start do |connection|
          connection.request_get(uri.request_uri) do |response|
            body = +""
            response.read_body do |chunk|
              body << chunk
              raise TooLarge, "exceeds #{max_bytes} bytes" if body.bytesize > max_bytes
            end
            headers = { "location" => response["location"], "content-type" => response["content-type"] }
            return [ response.code.to_i, headers, body ]
          end
        end
      end
    end
  end
end
