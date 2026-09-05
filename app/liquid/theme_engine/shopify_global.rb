# frozen_string_literal: true

module ThemeEngine
  # 買家面 window.Shopify 全域（Ella 修復 PR-3；E19 改為本尊逐字形）。
  #
  # 為什麼：主題 JS 生態依賴本尊 storefront runtime 注入的 window.Shopify——缺它＝「Shopify is not defined」連鎖崩。
  # 形＝本尊 content_for_header 第 11 節點逐字（hoko.vip 2026-09-05，external-facts §G27）：
  #   `var Shopify = Shopify || {};` → shop（本尊＝myshopify 永久網域；我方＝平台子網域）→ locale → currency（JSON 形）→ country
  #   → theme（name／id／schema_name／schema_version／theme_store_id／role）→ theme.handle="null" → theme.style={"id":null,"handle":null}
  #   → cdnHost（`host/cdn`）→ routes.root → shopJsCdnBaseUrl → SignInWithShop.User.recognized=false。
  # 🔴 本尊 script **沒有** formatMoney／postLink／CountryProvinceSelector／bind／addListener／setSelectorByValue／removeItem／getCart／
  #   onCartUpdate——這些由 **Ella 自己的 global.js** 定義（grep 取證 2026-09-05：global.js L880／1210／1216／1226／1232／1253／4388／4392／4432），
  #   本尊執行期 `Shopify.ModelViewerUI`＝undefined（loadFeatures 按需載）。PR-3 加的 ours 版本已移除（重複定義且蓋掉 E18 的
  #   `Shopify.PaymentButton`／loadFeatures 佇列）；主題自帶 shopify_common.js 者走 `shopify_asset_url`。
  # designMode：官方文檔明載的偵測介面（shopify.dev theme editor 章）；本尊在編輯器內的位置未取得（置於 routes.root 之後，91 V）。
  module ShopifyGlobal
    module_function

    # @param country [String, nil] localization 國別（本尊 `Shopify.country = "TW"`）
    # @param schema_name／schema_version [String, nil] settings_schema theme_info
    # @param host [String, nil] 本店主機（cdnHost 形 `{host}/cdn`）
    # @param origin [String, nil] shop-js 基底（本尊 `https://cdn.shopify.com/shopifycloud/shop-js`；我方走店主機同路徑）
    def script(shop:, theme:, locale:, currency:, root:, design_mode:, country: nil, schema_name: nil,
               schema_version: nil, host: nil, origin: nil)
      theme_json = JSON.generate(name: theme.name.to_s, id: theme.id, schema_name: schema_name,
                                 schema_version: schema_version, theme_store_id: nil,
                                 role: theme.role.to_s == "published" ? "main" : "unpublished")
      lines = [ "var Shopify = Shopify || {};",
                "Shopify.shop = #{"#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}".inspect};",
                "Shopify.locale = #{locale.to_s.inspect};",
                "Shopify.currency = #{JSON.generate(active: currency.to_s, rate: '1.0')};",
                "Shopify.country = #{country.to_s.inspect};",
                "Shopify.theme = #{theme_json};",
                'Shopify.theme.handle = "null";',
                'Shopify.theme.style = {"id":null,"handle":null};',
                "Shopify.cdnHost = #{"#{host}/cdn".inspect};",
                "Shopify.routes = Shopify.routes || {};",
                "Shopify.routes.root = #{root.to_s.inspect};" ]
      lines << "Shopify.designMode = true;" if design_mode
      lines << "Shopify.shopJsCdnBaseUrl = #{"#{origin || "https://#{host}"}/cdn/shopifycloud/shop-js".inspect};"
      lines << "Shopify.SignInWithShop = Shopify.SignInWithShop || {};"
      lines << "Shopify.SignInWithShop.User = Shopify.SignInWithShop.User || {};"
      lines << "Shopify.SignInWithShop.User.recognized = false;"
      "<script>#{lines.join("\n")}</script>" # 本尊：`recognized = false;</script>` 無換行（T13 空白骨架對表）
    end
  end
end
