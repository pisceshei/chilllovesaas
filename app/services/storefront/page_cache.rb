# frozen_string_literal: true

module Storefront
  # 頁級快取（包 33 後半；63 §D.3 的 key 組成＋14 §F1-3）。
  #
  # 🔴 **key-based expiry 唯一許可**（limits `catalog_flow.cache_strategy`；63 §D.4）：
  #   沒有任何失效動作——資料變 ⇒ stamp 變 ⇒ key 變；舊 entry 靠儲存層 LRU/TTL 自然淘汰。
  #   本檔出現 `Rails.cache.delete` 即違規。
  # 🔴 個人化不進頁快取（14 §F1-4）：呼叫端渲染快取頁時 **cart_json 一律 nil**
  #   （頁本體人人相同；買家的 cart 態由 /cart.js ＋ bundled sections 端點另行取得，
  #   那條路不經本快取）。
  # 🔴 volatile TTL 兜底（63 §D.5）：頁面讀到 inventory_quantity 等揮發欄位 ⇒
  #   該頁 entry TTL ≤ `catalog_flow.volatile_section_ttl_seconds`（價格類靠 key 即時、
  #   數量類最多陳舊 60s，兩個過期條件取先到者）。Ella 商品卡讀庫存 ⇒ 集合頁整頁
  #   降 TTL——正確性優先的已登記代價（63 §D.5 誠實記錄）。
  module PageCache
    NAMESPACE = "sf-page-v1"
    # 非 volatile 頁的 entry 壽命上限：純粹是儲存層回收輔助（key-based 下語義上可無限）。
    DEFAULT_TTL = 1.day

    # 引擎版本維度（步 13b；生產實錘：13a 部署後首頁仍吐舊 stub @font-face——
    # key 無代碼版本維，快取頁跨部署存活到 TTL）。boot 時戳＝每次部署重啟自然
    # 換 key；重啟即清倉的代價可接受（快取即時回暖）。
    BOOT_STAMP = Time.now.to_i

    module_function

    # @param shop [Shop]
    # @param theme [Theme]
    # @param market [Market]
    # @param locale_tag [String]
    # @param path [String] 前綴已剝除的站內路徑
    # @param params [Hash] 白名單化後的 query 參數（見 PagesController::CACHE_PARAMS）
    # @yieldreturn [ThemeEngine::PageRenderer::Result]
    # @return [Hash] {"status"=>, "html"=>, "volatile"=>}——快取值用純 Hash，
    #   不 Marshal Result（Struct 版本演進會讓舊 entry 反序列化炸）
    def fetch(shop:, theme:, market:, locale_tag:, path:, params:, &block)
      key = key_for(shop:, theme:, market:, locale_tag:, path:, params:)
      cached = Rails.cache.read(key)
      return cached if cached

      result = block.call
      payload = { "status" => result.status, "html" => result.html,
                  "volatile" => result.volatile? }
      # 只快取 200 整頁：404 頁便宜且 handle 空間無界（快取 404＝敵手可灌爆儲存）。
      if result.status == 200 && result.content_type != :json
        ttl = result.volatile? ? Limits.fetch(:catalog_flow, :volatile_section_ttl_seconds).seconds : DEFAULT_TTL
        Rails.cache.write(key, payload, expires_in: ttl)
      end
      payload
    end

    # key 維度＝63 §D.3 頁級列逐項：shop／theme 版本／locale／market（含其 stamp）／
    # currency／page_kind＋resource stamp／路徑與白名單參數。
    # theme.updated_at 承擔「theme.version＋template.updated_at」兩維（v1 主題檔來源
    # 按版本不可變、DB template 覆寫寫入時 touch theme——結構上同一時戳）。
    def key_for(shop:, theme:, market:, locale_tag:, path:, params:)
      # 自帶租戶脈絡：resource_stamp 查的是 tenant-scoped model（require_tenant 下
      # 呼叫端沒設租戶會 NoTenantSet）；with_tenant 冪等，middleware 已設也無妨。
      kind, stamp = ActsAsTenant.with_tenant(shop) { resource_stamp(shop, path) }
      [ NAMESPACE, BOOT_STAMP, shop.id, theme.id, theme.updated_at.to_i,
        locale_tag, market.id, market.updated_at.to_i,
        shop.store_currency, shop.catalog_version,
        kind, stamp, path, params.sort.flatten.join(":") ].join("/")
    end

    # 資源級 stamp（63 §D.3 的 MAX 組合，收斂到路徑指到的那一筆資源）。
    # 查無資源 ⇒ stamp 0（該請求會渲染 404，不進快取）。
    def resource_stamp(shop, path)
      case path
      when %r{\A/policies/([^/]+)\z} # T13：政策內容更新即換 key
        [ "policy", ShopPolicy.where(shop_id: shop.id, kind: Regexp.last_match(1)).maximum(:updated_at).to_i ]
      when %r{\A/products/([^/]+)\z}
        # 🔴 MySQL GREATEST 任一參數 NULL ⇒ 回 NULL（不是忽略）：rollup 欄（media_updated_at
        # 等）在資源沒該類寫入前是 NULL ⇒ 不 COALESCE 的話 stamp 恆 0、改價改名都換不了
        # key＝永遠舊頁（S6 抓到的現行犯）。以 updated_at 兜底。
        row = Product.where(shop_id: shop.id, handle: Regexp.last_match(1))
                     .pick(Arel.sql("GREATEST(updated_at, COALESCE(variants_updated_at, updated_at), " \
                                    "COALESCE(publications_updated_at, updated_at), " \
                                    "COALESCE(media_updated_at, updated_at))"))
        [ "product", time_stamp(row) ]
      when %r{\A/collections/([^/]+)\z}
        row = Collection.where(shop_id: shop.id, handle: Regexp.last_match(1))
                        .pick(Arel.sql("GREATEST(updated_at, COALESCE(products_updated_at, updated_at))"))
        [ "collection", time_stamp(row) ]
      when "/", ""
        [ "index", 0 ]
      when %r{\A/pages/([^/]+)\z}
        [ "page", time_stamp(Page.where(shop_id: shop.id, handle: Regexp.last_match(1)).pick(:updated_at)) ]
      else
        [ "other", 0 ]
      end
    end

    # 🔴 raw SQL 的 pick 可能回 Time 或字串（GREATEST 是計算欄，AR 不套型別轉換保證）：
    #   對字串走 String#to_i 會得到年份「2026」⇒ 全部資源 stamp 同值 ⇒ 永遠舊快取。
    #   毫秒粒度：同一秒內連續兩次寫入也要換 key（保守方向＝寧多渲染，不舊值）。
    def time_stamp(value)
      case value
      when Time, DateTime then (value.to_f * 1000).to_i
      when String then (Time.zone.parse(value).to_f * 1000).to_i
      else 0
      end
    end
  end
end
