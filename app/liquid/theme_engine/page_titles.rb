# frozen_string_literal: true

module ThemeEngine
  # `page_title`（官方 objects/page_title："The page title of the current page."）各頁型的值——引擎缺口 PR-8。
  # 值形＝真店逐字（2026-09-03）：英文店 kyliecosmetics.com、中文店 hoko.vip（pnrjnw-sy）；兩店主題 layout 皆
  # `{{ page_title }} &ndash; {{ shop.name }}` 形，故 page_title 本身不含店名（首頁例外＝店名，hoko `<title>我的商店 3</title>`）。
  #   product／collection／page／blog／article ⇒ 資源標題（hoko `Acme Tee`、`首頁`；kylie `New in`）；
  #   vendors／types 虛擬系列 ⇒ q（hoko `Acme`／`Mug`）；/collections/all ⇒ "Products"／"商品"；
  #   /collections ⇒ "Collections"／"产品系列"（繁體店逐字出簡體字）；search 無 q ⇒ "Search"／"搜索"；
  #   有 q ⇒ `Search: 0 results found for "tee"`／`搜尋：找到「tee」的結果，共 0 筆`（N＝search.results_count）；
  #   cart ⇒ "Your Shopping Cart"／"您的購物車"；404 ⇒ "404 Not Found"／"404 找不到"。
  # 其他語言＝未取得 ⇒ 退英文。原實作恆＝店名（hoko 稽核候選）。
  module PageTitles
    STRINGS = {
      "en" => { products: "Products", collections: "Collections", search: "Search",
                search_results: 'Search: %<count>d results found for "%<terms>s"',
                cart: "Your Shopping Cart", not_found: "404 Not Found" },
      "zh" => { products: "商品", collections: "产品系列", search: "搜索",
                search_results: "搜尋：找到「%<terms>s」的結果，共 %<count>d 筆",
                cart: "您的購物車", not_found: "404 找不到" }
    }.freeze

    module_function

    def strings(locale)
      lang = locale.to_s.split(/[-_]/).first.to_s.downcase
      STRINGS.fetch(lang, STRINGS["en"])
    end

    def products_title(locale) = strings(locale)[:products]

    # @param page_type [String] PageRenderer#resolve 的頁型鍵
    # @param assigns [Hash] 該頁的 drops（product／collection／page／blog／article／search）
    def for(page_type:, assigns:, status:, shop:, locale:)
      t = strings(locale)
      return t[:not_found] if status.to_i == 404 || page_type == "404"

      case page_type
      when "index" then shop.name
      when "cart" then t[:cart]
      when "list-collections" then t[:collections]
      when "search"
        search = assigns["search"]
        if search.respond_to?(:performed) && search.performed
          format(t[:search_results], count: search.results_count.to_i, terms: search.terms.to_s)
        else
          t[:search]
        end
      else
        resource = assigns["product"] || assigns["collection"] || assigns["page"] || assigns["article"] || assigns["blog"]
        resource.respond_to?(:title) ? resource.title.to_s : shop.name
      end
    end
  end
end
