# frozen_string_literal: true

require "resolv"
require "ipaddr"

module Webhooks
  # webhook URL 紅線（specs/18 F4 逐字）：HTTPS only＋SSRF 防護——「解析 DNS 後
  # 拒絕私網/loopback/link-local/雲 metadata IP」，且「投遞時再驗一次（DNS
  # rebinding）」。防護做在 **resolve 層**不是字串黑名單（18 F4 ⚠ 坑）。
  #
  # 投遞側配套：Deliver 以本 guard 回傳的 vetted IP 直連（Net::HTTP#ipaddr）
  # ——關掉 resolve→connect 之間的 rebinding 窗；client 不跟 redirect。
  module UrlGuard
    class GuardError < StandardError; end

    module_function

    # @param url [String]
    # @return [Array(URI, String)] (uri, vetted_ip)
    # @raise [GuardError] 非 HTTPS／解析失敗／任一位址非公網
    def vet!(url)
      uri = URI.parse(url.to_s)
      raise GuardError, "只接受 HTTPS URL。" unless uri.is_a?(URI::HTTPS) && uri.host.present?

      addresses = resolve(uri.host)
      raise GuardError, "主機名解析失敗。" if addresses.empty?

      addresses.each do |address|
        raise GuardError, "目標位址不在公網（SSRF 防線）。" unless public_address?(address)
      end
      [ uri, addresses.first.to_s ]
    rescue URI::InvalidURIError
      raise GuardError, "URL 格式不合法。"
    end

    def resolve(host)
      # 字面 IP 也走同一判準（不能靠 DNS 層漏過）
      begin
        return [ IPAddr.new(host) ]
      rescue IPAddr::InvalidAddressError
        # 非字面 IP ⇒ DNS
      end
      Resolv.getaddresses(host).filter_map do |raw|
        IPAddr.new(raw)
      rescue IPAddr::InvalidAddressError
        nil
      end
    end

    # 🔴 拒絕面（18 F4）：私網／loopback／link-local（含 169.254.169.254 雲
    # metadata）／未指定／multicast；IPv6 對偶（::1/fe80::/fc00::）由 IPAddr
    # 同名判準涵蓋。
    def public_address?(address)
      !(address.private? || address.loopback? || address.link_local? ||
        address.to_s == "0.0.0.0" || address.to_s == "::" ||
        address.ipv4? && address.to_s.start_with?("224.", "255.") ||
        address.ipv6? && address.to_s.start_with?("ff"))
    end
  end
end
