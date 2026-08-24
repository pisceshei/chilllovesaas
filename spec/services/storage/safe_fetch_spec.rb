# frozen_string_literal: true

require "rails_helper"

# 第 25 包 SSRF 防線（12 §B.6:155 嚴格版）。無 webmock：Resolv 與 HTTP 層以 stub
# 隔離，被測物＝驗證邏輯本體（scheme／IP 域／redirect 每跳重驗／尺寸）。
RSpec.describe Storage::SafeFetch do
  def stub_dns(mapping)
    allow(Resolv).to receive(:getaddresses) { |host| Array(mapping.fetch(host, [])) }
  end

  # request 內部契約＝[status, headers, body]（審查 C0 後 body 已在 request 內 cap）
  def http_triple(body: "x", content_type: "image/png")
    [ 200, { "location" => nil, "content-type" => content_type }, body ]
  end

  def redirect_triple(location)
    [ 302, { "location" => location, "content-type" => nil }, "" ]
  end

  it "scheme 白名單：file:// 與 ftp:// 一律 Blocked" do
    expect { described_class.call("file:///etc/passwd") }.to raise_error(described_class::Blocked, /scheme/)
    expect { described_class.call("ftp://example.com/a.png") }.to raise_error(described_class::Blocked, /scheme/)
  end

  it "🔴 審查 C1：IPv6 transition 形式嵌入的私網 IPv4 全拒（NAT64／6to4／v4-compat／v4-mapped）" do
    # 這些都嵌入 10.0.0.5，denylist 會漏、抽取內層後應全擋
    %w[64:ff9b::a00:5 2002:0a00:0005:: ::10.0.0.5 ::ffff:10.0.0.5].each do |addr|
      expect(described_class.blocked_ip?(addr)).to be(true), "#{addr} 未被擋"
    end
    # 公網 IPv6 放行
    expect(described_class.blocked_ip?("2606:4700:4700::1111")).to be(false)
    # 走 DNS：AAAA 記錄回 NAT64 → 被擋
    stub_dns("nat64.test" => [ "64:ff9b::a00:5" ])
    expect { described_class.call("http://nat64.test/x.png") }
      .to raise_error(described_class::Blocked, /address/)
  end

  it "🔴 審查 C0：非 2xx／redirect 響應體同樣 cap（攻擊者 404＋巨量 body 不得無上限讀入）" do
    stub_dns("attacker.test" => [ "93.184.216.34" ])
    max_bytes = Limits.fetch(:outbound_http, :file_fetch_download_bytes_max)
    # request 內部真的跑 read_body cap：以一個「回 404＋超量 body」的假 connection 驗
    fake_response = Object.new
    fake_response.define_singleton_method(:code) { "404" }
    fake_response.define_singleton_method(:[]) { |_k| nil }
    fake_response.define_singleton_method(:read_body) do |&block|
      # 分塊送，累計超過上限就該在 SafeFetch 內 raise TooLarge
      (max_bytes / 1000 + 2).times { block.call("x" * 1000) }
    end
    fake_conn = Object.new
    fake_conn.define_singleton_method(:request_get) { |_uri, &block| block.call(fake_response) }
    fake_http = Object.new
    %i[ipaddr= use_ssl= open_timeout= read_timeout=].each { |m| fake_http.define_singleton_method(m) { |_v| } }
    fake_http.define_singleton_method(:start) { |&block| block.call(fake_conn) }
    allow(Net::HTTP).to receive(:new).and_return(fake_http)
    expect { described_class.call("http://attacker.test/x.png") }
      .to raise_error(described_class::TooLarge)
  end

  it "🔴 私網／loopback／link-local／CGN／metadata 全拒（解析後逐 IP 驗）" do
    {
      "10.0.0.5" => "internal", "127.0.0.1" => "loop", "169.254.169.254" => "meta",
      "172.16.9.9" => "rfc1918b", "192.168.31.246" => "lan", "100.64.1.1" => "cgn",
      "::1" => "v6loop", "fd00::1" => "ula"
    }.each do |ip, label|
      stub_dns("evil-#{label}.test" => [ ip ])
      expect { described_class.call("http://evil-#{label}.test/x.png") }
        .to raise_error(described_class::Blocked, /address/), "#{label}(#{ip}) 未被擋"
    end
  end

  it "多 A 記錄只要一顆私網即拒（rebinding 混种解析）" do
    stub_dns("mixed.test" => [ "93.184.216.34", "10.0.0.5" ])
    expect { described_class.call("https://mixed.test/x.png") }
      .to raise_error(described_class::Blocked, /address/)
  end

  it "redirect 每跳重驗：公網跳私網被擋；跳數超過 limits 上限被擋" do
    stub_dns("ok.test" => [ "93.184.216.34" ], "inner.test" => [ "192.168.1.1" ])
    allow(described_class).to receive(:request) do |uri, _ip|
      uri.host == "ok.test" ? redirect_triple("http://inner.test/steal") : http_triple
    end
    expect { described_class.call("http://ok.test/a.png") }
      .to raise_error(described_class::Blocked, /address/)

    # 跳數上限：無限 302 迴圈在 hops_max 停下
    allow(described_class).to receive(:request).and_return(redirect_triple("http://ok.test/loop"))
    expect { described_class.call("http://ok.test/a.png") }
      .to raise_error(described_class::Blocked, /redirects/)
  end

  it "成功路徑回 body 與 content_type；連線以解析出的 IP 釘選" do
    stub_dns("cdn.test" => [ "93.184.216.34" ])
    seen_ip = nil
    allow(described_class).to receive(:request) do |_uri, ip|
      seen_ip = ip
      http_triple(body: "PNGDATA", content_type: "image/png")
    end
    result = described_class.call("https://cdn.test/a.png")
    expect(result.body).to eq("PNGDATA")
    expect(result.content_type).to eq("image/png")
    expect(seen_ip).to eq("93.184.216.34")
  end
end
