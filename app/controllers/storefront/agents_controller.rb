# frozen_string_literal: true

module Storefront
  # `/agents.md`／`/llms.txt`／`/llms-full.txt` 三別名端點（包 35；62 §H.2/H.3）。
  #
  # 🔴 三條路徑預設全開、內容相同、同一生成器（limits `agents.llms_paths_default_alias_of_agents_md`
  #   ——Shopify 的 llms-full 是別名不是打包，68 §C-1 誤讀更正）；不投入內容策展。
  # 🔴 裸主網域、無 locale 前綴、不可在地化（62 §H.3(a)：市場與語言不進這個檔）。
  # 🔴 能力宣告鐵律（§H.3(b)）：ucp／mcp 端點**未實作 ⇒ 不輸出該欄位**（不出空字串
  #   佔位——指向 404 的宣告比沒有更糟）。商家自訂 templates/agents.md.liquid 的
  #   fallback 鏈待主題編輯器包（登記）。
  class AgentsController < BaseController
    def show
      shop = current_shop
      sitemap = "https://#{request.host}/sitemap.xml"
      body = <<~MARKDOWN
        # #{shop.name}

        - store_url: https://#{request.host}/
        - sitemap_url: #{sitemap}
        - currency: #{shop.store_currency}
      MARKDOWN
      render plain: body, content_type: "text/markdown"
    end
  end
end
