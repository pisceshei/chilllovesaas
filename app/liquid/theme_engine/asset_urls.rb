# frozen_string_literal: true

module ThemeEngine
  # 主題資產 URL 本尊形（路線圖 T12；external-facts §G28；docs/dev/t12-theme-asset-urls.md）。
  #
  # 官方逐字（shopify.dev/docs/api/liquid/filters，取證 2026-09-05）：
  #   asset_url         → `//polinas-potent-potions.myshopify.com/cdn/shop/t/4/assets/cart.js?v=83971781268232213281663872410`
  #   asset_img_url     → `…/cdn/shop/t/4/assets/red-and-black-bramble-berries_small.jpg?v=337`（size 預設 small；`'large'` ⇒ `_large`）
  #   file_url          → `//…/cdn/shop/files/disclaimer.pdf?v=9043651738044769859`
  #   file_img_url      → `//…/cdn/shop/files/potions-header_small.png?v=4246568442683817558`
  #   shopify_asset_url → `//…/cdn/shopifycloud/storefront/assets/themes_support/option_selection-b017cd28.js`
  #   global_asset_url  → `//…/cdn/s/global/lightbox.js`
  #   font_url          → `//…/cdn/fonts/assistant/assistant_n4.9120912a469cad1cc292572851508ca49d12e768.woff2`（`'woff'` ⇒ 另一雜湊的 .woff）
  # hoko.vip 實測（2026-09-05，商品頁 89 個 asset_url）：主機＝**店主機**（hoko.vip，非 myshopify）；`?v=` 28–30 位十進位＝
  #   **前段 ≤20 位（64 位無號整數範圍）＋後 10 位 unix 秒**——同主題全部資產後 10 位相同（1788313528），compiled_assets 另一時間戳
  #   （1788313593）⇒ 前段＝每檔摘要、後段＝該檔產生時的主題版本時間。摘要演算法本尊未公開（91 §3.89 V）：我方＝MD5 前 8 位元組的
  #   無號 64 位整數（**形同、值必不同**；Normalizer 抹 `?v=\d+`）。
  # 供給端：`/cdn/shop/t/{id}/assets/*`（AssetsController#cdn，任一主題以 id 供給——hoko `/t/1/` 亦 200）、`/cdn/fonts/*`（#font）、
  #   `/cdn/shop/files/*`（MediaController#by_filename）；themes_support／global 兩類本體我方未提供（404，91 V）。
  module AssetUrls
    module_function

    # 官方 img_url 表（deprecated 頁，取證 2026-09-05）：pico 16／icon 32／thumb 50／small 100／compact 160／medium 240／large 480／
    # grande 600／original＝master 1024；另有 `{w}x{h}` 形。
    NAMED_SIZE_PX = { "pico" => 16, "icon" => 32, "thumb" => 50, "small" => 100, "compact" => 160, "medium" => 240,
                      "large" => 480, "grande" => 600, "original" => 1024, "master" => 1024 }.freeze
    SIZE_SUFFIX_RE = /\A(.+)_(#{NAMED_SIZE_PX.keys.join('|')}|\d*x\d*)(\.[A-Za-z0-9]+)\z/

    # @param host [String, nil] 含埠的店主機（nil ⇒ 主機相對形，裸 harness 用）
    def theme_asset(host:, theme:, source:, file:)
      v = version(theme, source, file)
      "#{origin(host)}/cdn/shop/t/#{theme.id}/assets/#{file}#{v ? "?v=#{v}" : ''}"
    end

    # `_{size}` 插在副檔名前；`?v=` 取原檔摘要（尺寸形在主題裡不存在）
    def theme_asset_img(host:, theme:, source:, file:, size:)
      v = version(theme, source, file)
      "#{origin(host)}/cdn/shop/t/#{theme.id}/assets/#{sized_name(file, size)}#{v ? "?v=#{v}" : ''}"
    end

    # @param stored_file [StoredFile, nil] 找不到 ⇒ 仍出 URL、無 `?v=`（本尊缺檔形未取得，91 V）
    def shop_file(host:, stored_file:, name:, size: nil)
      path = size ? sized_name(name, size) : name
      v = stored_file && file_version(stored_file)
      "#{origin(host)}/cdn/shop/files/#{path}#{v ? "?v=#{v}" : ''}"
    end

    # `themes_support/{dir/}{stem}-{8hex}{ext}`：官方例的 8 位＝本尊檔內容雜湊；我方無本體 ⇒ 以路徑 SHA-1 前 8 位定形（V）
    def shopify_asset(host:, file:)
      dir, base = File.split(file)
      ext = File.extname(base)
      stem = File.basename(base, ext)
      prefix = dir == "." ? "" : "#{dir}/"
      "#{origin(host)}/cdn/shopifycloud/storefront/assets/themes_support/#{prefix}#{stem}-#{Digest::SHA1.hexdigest("themes_support/#{file}")[0, 8]}#{ext}"
    end

    def global_asset(host:, file:) = "#{origin(host)}/cdn/s/global/#{file}"

    # @param drop [FontDrop] file 形 `/fonts/{family}/{handle}.woff2`（config/storefront_fonts.yml）；不合形 ⇒ 原路徑
    def font(host:, drop:, format: "woff2")
      m = drop.file.to_s.match(%r{\A/fonts/([a-z0-9_-]+)/([a-z0-9_-]+)\.woff2\z}) or return drop.file.to_s
      sha = FontFiles.sha1(m[1], m[2]) or return drop.file.to_s
      "#{origin(host)}/cdn/fonts/#{m[1]}/#{m[2]}.#{sha}.#{format}"
    end

    # 每檔摘要＋主題版本秒；以主題版本鍵快取（主題檔寫入必 touch theme——theme_file_upsert／delete）。缺檔 ⇒ nil（無 `?v=`）
    def version(theme, source, file)
      stamp = theme.updated_at.to_i
      v = Rails.cache.fetch([ "theme_asset_v", theme.id, stamp, file ], expires_in: 1.day) do
        body = source&.read("assets/#{file}")
        body.nil? ? "" : "#{digest64(body)}#{stamp}"
      end
      v.presence
    end

    # Files 頁檔案：官方例 19 位、無時間戳形 ⇒ 我方＝id＋checksum 的 64 位摘要（語義未取得，V）
    def file_version(stored_file) = digest64("#{stored_file.id}:#{stored_file.checksum}").to_s

    # MD5 前 8 位元組 ⇒ 無號 64 位整數（十進位 1–20 位）
    def digest64(body) = Digest::MD5.digest(body.to_s)[0, 8].unpack1("Q>")

    def sized_name(name, size)
      ext = File.extname(name)
      "#{name.delete_suffix(ext)}_#{size}#{ext}"
    end

    # `{stem}_{size}{ext}` ⇒ [原檔名, size]；非尺寸形 ⇒ [name, nil]
    def split_size(name)
      m = SIZE_SUFFIX_RE.match(name)
      m ? [ "#{m[1]}#{m[3]}", m[2] ] : [ name, nil ]
    end

    def origin(host) = host.present? ? "//#{host}" : ""
  end
end
