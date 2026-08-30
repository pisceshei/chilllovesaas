# 26 — Liquid API 全量清單（相容層實作 checklist）

> 由文檔研究代理彙整自 shopify.dev/docs/api/liquid 全站與官方機器可讀資料庫 `Shopify/theme-liquid-docs`（與 shopify.dev、theme-check 同源）。**這份清單就是 M2/M6 Liquid 相容層的實作 checklist 與驗收基準**；策略與架構見 `25-liquid-compat-spec.md`，工程事實（gem 能力/端點規格/授權）另見 25 號 §資料來源。

# Shopify Liquid 相容層全量 API 面清單（objects / tags / filters / theme 結構）

資料來源：shopify.dev/docs/api/liquid 全站 + Shopify 官方機器可讀資料庫 `Shopify/theme-liquid-docs`（`data/objects.json` 138 個、`data/tags.json` 30 個、`data/filters.json` 154 條目/153 個唯一 filter、`schemas/theme/*.json`），為 shopify.dev 文件與官方 VS Code 擴充的同源資料，可直接 clone 作為實作 checklist 與測試 fixture。

通用約定：
- 「gem」= Shopify/liquid Ruby gem（MIT）已內建，語言核心免實作；其餘皆為平台層（drops/tags/filters）需自行實作。
- 金額型 `number` 一律以**最小貨幣單位（cents）**表示，由 money 系列 filters 格式化。
- `?` 結尾屬性（如 `empty?`）為布林查詢方法。
- Tier 定義：**T0** = Dawn/Horizon 首頁+商品頁+系列頁（含 layout/header/footer/cart drawer）渲染必需；**T1** = 完整店面（blog/search/customer/order/cart 進階/metafields）；**T2** = 長尾（selling plans、gift cards、B2B、markets 進階、robots、deprecated）。
- 標注「T2（T0 需 nil-stub）」= Dawn/Horizon 模板會引用該屬性，T0 階段必須讓屬性存在並回 nil/空陣列，不然渲染會炸，完整行為可延後。

---

## 1. Objects（138 個）

欄位：name / 說明 / 關鍵屬性（挑常用，`名稱:型別`）/ 可用範圍 / Tier

### 1.1 商品與變體

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| product | 商品（共 44 屬性） | id:number, title:string, handle:string, description/content:string, vendor:string, type:string, url:string, price/price_min/price_max:number, compare_at_price:number, price_varies:boolean, available:boolean, featured_image:image, featured_media:media, media:array\<media>, images:array, variants:array\<variant>, options_with_values:array\<product_option>, selected_or_first_available_variant:variant, selected_variant:variant, collections:array, tags:array, metafields, has_only_default_variant:boolean, requires_selling_plan:boolean, gift_card?:boolean, category:taxonomy_category, quantity_price_breaks_configured?:boolean, selected_or_first_available_selling_plan_allocation | template `product`；all_products / collection.products / line_item.product / settings 等 | T0 |
| variant | 商品變體（共 38 屬性） | id:number, title:string, price:number, compare_at_price:number, available:boolean, sku:string, barcode:string, options:array, option1/2/3:string(DEP), url:string, weight:number, weight_unit:string, unit_price:number, unit_price_measurement, inventory_quantity:number, inventory_policy:string, inventory_management:string, requires_shipping:boolean, taxable:boolean, featured_image:image, featured_media:media, selected:boolean, matched:boolean, quantity_rule, selling_plan_allocations:array, store_availabilities:array, incoming:boolean, next_incoming_date:string | product.variants / line_item.variant | T0 |
| product_option | 商品選項（如 Color） | name:string, position:number, values:array\<product_option_value>, selected_value:string | product.options_with_values | T0 |
| product_option_value | 選項值 | id:number, name:string, available:boolean, selected:boolean, swatch:swatch, variant:variant, product_url:string | product_option.values / variant.options | T0 |
| swatch | 色票/圖樣（選項值或 filter 值） | color:color, image:image | product_option_value.swatch / filter_value.swatch | T0 |
| quantity_rule | B2B/量購數量規則 | min:number, max:number, increment:number | variant.quantity_rule | T2（T0 需 stub：預設 min=1,increment=1） |
| quantity_price_break | 量購階梯價 | minimum_quantity:number, price:number | variant.quantity_price_breaks | T2 |
| taxonomy_category | 標準商品分類 | id:string, gid:string, name:string, ancestors:array | product.category | T2 |
| store_availability | 門市取貨可用性 | available:boolean, pick_up_enabled:boolean, pick_up_time:string, location:location | variant.store_availabilities | T2 |
| location | 門市/庫存地點 | id:number, name:string, address:address, latitude/longitude:number, metafields | store_availability.location | T2 |

### 1.2 購物車與結帳

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| cart | 購物車（共 18 屬性） | item_count:number, items:array\<line_item>, total_price:number, original_total_price:number, items_subtotal_price:number, total_discount:number, checkout_charge_amount:number, note:string, attributes, currency, empty?:boolean, requires_shipping:boolean, total_weight:number, discount_applications:array, cart_level_discount_applications:array, taxes_included:boolean, duties_included:boolean | 全域（cart drawer 常駐 header） | T0 |
| line_item | 購物車/訂單行項（共 42 屬性） | id:number, key:string, quantity:number, title:string, product:product, variant:variant, product_id/variant_id:number, final_price:number, final_line_price:number, original_price:number, original_line_price:number, line_level_total_discount:number, line_level_discount_allocations:array, discount_allocations:array, image:image, url:string, url_to_remove:string, sku:string, vendor:string, properties:array, selling_plan_allocation, unit_price:number, unit_price_measurement, requires_shipping:boolean, gift_card:boolean, taxable:boolean, grams:number, item_components:array, error_message:string, message:string | cart.line_items / order.line_items | T0 |
| discount_application | 折扣應用（v2 折扣模型） | title:string, type:string(automatic/discount_code/manual/script), value:number, value_type:string(fixed_amount/percentage), target_type:string(line_item/shipping_line), target_selection:string(all/entitled/explicit), total_allocated_amount:number | cart/order.discount_applications | T1（T0 空陣列） |
| discount_allocation | 折扣分配到行項 | amount:number, discount_application:discount_application | line_item.discount_allocations | T1（T0 空陣列） |
| unit_price_measurement | 單位價格量測（歐盟法規） | measured_type:string, quantity_value:number, quantity_unit:string, reference_value:number, reference_unit:string | variant/line_item.unit_price_measurement | T1（T0 需 nil-stub） |
| instructions | 行項可否操作（bundle） | can_remove:boolean, can_update_quantity:boolean | line_item.instructions | T2 |
| parent_relationship | 行項父子關係（bundle） | parent:line_item | line_item.parent_relationship | T2 |
| additional_checkout_buttons | 是否有第三方快捷結帳（PayPal 等） | （本身為 boolean） | 全域 | T1（T0 stub false） |
| content_for_additional_checkout_buttons | 快捷結帳按鈕 HTML | （輸出 string） | 全域 | T1 |
| checkout | **DEPRECATED**（checkout.liquid 已於 2024-08 淘汰；共 39 屬性） | order:order, line_items, total_price, email, shipping_address, billing_address, shipping_method, tax_lines, transactions | template `checkout`（僅舊 Plus） | T2（不建議實作） |
| pending_payment_instruction_input | 待付款指示欄位 | header:string, value:string | transaction.buyer_pending_payment_instructions | T2 |

### 1.3 客戶、訂單與 B2B

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| customer | 登入客戶（共 25 屬性；未登入為 nil） | id:number, first_name/last_name/name:string, email:string, phone:string, orders:array\<order>, orders_count:number, last_order:order, total_spent:number, addresses:array\<address>, addresses_count:number, default_address:address, tags:array, has_account:boolean, accepts_marketing:boolean, tax_exempt:boolean, has_avatar?:boolean, store_credit_account, b2b?:boolean, current_company:company, current_location:company_location, payment_methods:array | 全域（可為 nil）；customers/* templates 必有 | T1（T0 需 nil） |
| address | 地址 | id:number, first_name/last_name/name:string, company:string, address1/address2:string, city:string, province:string, province_code:string, zip:string, country:country, country_code:string, phone:string, street:string, summary:string, url:string | customer.addresses / order.shipping_address 等 | T1 |
| order | 訂單（共 44 屬性） | id:number, name:string, order_number:number, confirmation_number:string, created_at:string, financial_status:string(+label), fulfillment_status:string(+label), cancelled:boolean, email:string, phone:string, customer:customer, line_items:array, subtotal_price:number, total_price:number, total_discounts:number, shipping_price:number, tax_price:number, tax_lines:array, shipping_address/billing_address:address, shipping_methods:array, transactions:array, discount_applications:array, order_status_url:string, customer_url:string, tags:array, metafields, item_count:number, pickup_in_store?:boolean | customer.orders / template `customers/order` | T1 |
| fulfillment | 出貨紀錄 | created_at:string, item_count:number, fulfillment_line_items:array, tracking_company:string, tracking_number:string, tracking_numbers:array, tracking_url:string | line_item.fulfillment | T1 |
| transaction | 付款交易 | id:number, name:string, kind:string, status:string(+label), gateway:string, gateway_display_name:string, amount:number, created_at:string, payment_details, receipt:string | order.transactions | T1 |
| transaction_payment_details | 交易付款細節 | credit_card_company:string, credit_card_last_four_digits:string, gift_card:gift_card | transaction.payment_details | T1 |
| shipping_method | 運送方式 | id:string, handle:string, title:string, price:number(DEP→price_with_discounts), original_price:number, tax_lines:array, discount_allocations:array | order.shipping_methods | T1 |
| tax_line | 稅目 | title:string, price:number, rate:number, rate_percentage:number | order.tax_lines | T1 |
| customer_payment_method | 客戶儲存付款方式（訂閱） | token:string, payment_instrument_type:string | customer.payment_methods | T2 |
| store_credit_account | 商店額度帳戶 | balance:money | customer.store_credit_account | T2 |
| company | B2B 公司 | id:number, name:string, external_id:string, available_locations:array, available_locations_count:number, metafields | customer.current_company | T2 |
| company_location | B2B 公司據點 | id:number, name:string, current?:boolean, company:company, shipping_address:company_address, tax_registration_id:number, url_to_set_as_current:string, store_credit_account, metafields | customer.current_location | T2 |
| company_address | B2B 公司地址 | attention:string, address1/2, city, zip, country:country, country_code, province_code, street | company_location.shipping_address | T2 |

### 1.4 內容（blog / page / 政策）

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| blog | 部落格 | id:number, title:string, handle:string, url:string, articles:array, articles_count:number, all_tags:array, tags:array, comments_enabled?:boolean, moderated?:boolean, next_article/previous_article:article, metafields | template `blog`/`article`；blogs[handle] | T1 |
| blogs | 全店 blog 集合（by handle 存取） | （iterable + `blogs['news']`） | 全域 | T1 |
| article | 文章（共 21 屬性） | id:string, title:string, handle:string, url:string, author:string, content:string, excerpt:string, excerpt_or_content:string, image:image, published_at:string, created_at:string, updated_at:string, tags:array, user:user, comments:array, comments_count:number, comments_enabled?:boolean, comment_post_url:string, moderated?:boolean, metafields | template `article`；blog.articles / articles[...] | T1 |
| articles | 全店文章集合（`articles['blog/article']`） | （by handle 存取） | 全域 | T1 |
| comment | 文章留言 | id:number, author:string, email:string, content:string, status:string, created_at:string, updated_at:string, url:string | article.comments | T1 |
| user | 文章作者（staff） | name:string, first_name/last_name:string, email:string, bio:string, homepage:string, image:image, account_owner:boolean | article.user | T1 |
| page | 自訂頁面 | id:number, title:string, handle:string, content:string, author:string, url:string, published_at:string, template_suffix:string, metafields | template `page`；pages[handle] | T1 |
| pages | 全店頁面集合（by handle） | （iterable + `pages['about']`） | 全域 | T1 |
| policy | 商店政策（退款/隱私/條款…） | id:string, title:string, body:string, url:string | shop.policies / shop.refund_policy 等 | T1 |

### 1.5 導覽與連結

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| linklists | 全店選單集合（by handle） | `linklists['main-menu']` | 全域 | T0 |
| linklist | 選單 | handle:string, title:string, links:array\<link>, levels:number | linklists | T0 |
| link | 選單項（可 3 層巢狀） | title:string, url:string, active:boolean, child_active:boolean, current:boolean, child_current:boolean, links:array\<link>, handle:string, type:string, object, levels:number | linklist.links | T0 |
| routes | 全部標準路徑 URL（共 19 屬性，全列）<br><!-- 2026-08-30 live（83 §4.4）：平台 `window.Shopify.routes` 只注入 `root`；Ella 另自注入 `window.routes` 十鍵，其中 **`root` 字面 null**（`root_url` 才有值）——相容層照抄，勿「修正」。 --> | root_url, account_url, account_login_url, account_logout_url, account_register_url, account_recover_url, account_addresses_url, account_profile_url, storefront_login_url, collections_url, all_products_collection_url, search_url, predictive_search_url, cart_url, cart_add_url, cart_change_url, cart_clear_url, cart_update_url, product_recommendations_url（皆 string） | 全域 | T0 |

### 1.6 店面、請求與設定

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| shop | 商店資訊（共 37 屬性） | id:string, name:string, description:string, email:string, url:string, secure_url:string, domain:string, permanent_domain:string, phone:string, address:address, currency:string, money_format, money_with_currency_format, enabled_currencies:array, published_locales:array, enabled_payment_types:array\<string>, customer_accounts_enabled:boolean, customer_accounts_optional:boolean, accepts_gift_cards:boolean, products_count:number, collections_count:number, vendors:array, types:array, policies:array\<policy>, refund_policy/shipping_policy/privacy_policy/terms_of_service/subscription_policy:policy, brand:brand, password_message:string | 全域 | T0 |
| request | 當前請求 | host:string, origin:string, path:string, page_type:string（index/product/collection/…/404）, locale:shop_locale, design_mode:boolean, visual_preview_mode:boolean | 全域 | T0 |
| settings | 主題全域設定（settings_schema 定義） | 動態（依 schema id 存取） | 全域 | T0 |
| section | 當前 section | id:string, settings, blocks:array\<block>, index:number, index0:number, location:string | section 檔案內 | T0 |
| block | 當前 block | id:string, type:string, settings, shopify_attributes:string（editor 用 data 屬性） | section.blocks / content_for | T0 |
| template | 當前模板資訊 | name:string（如 product）, suffix:string（alternate）, directory:string（customers） | 全域 | T0 |
| theme | **DEPRECATED** 主題資訊 | id:number, name:string, role:string | 全域 | T2 |
| color_scheme | 配色方案 | id:string, settings（方案內各色） | settings 的 color_scheme 值 | T0 |
| color_scheme_group | 配色方案群組（iterable） | （迭代出 color_scheme） | settings_schema 定義 | T0 |
| color | 顏色物件 | red/green/blue:number, hue/saturation/lightness:number, alpha:number, chroma:number, oklch/oklcha:string, rgb/rgba:string, color_space:string | color 設定值 / swatch.color | T0 |
| font | 字型（font_picker 值） | family:string, fallback_families:string, weight:number, style:string, baseline_ratio:number, variants:array\<font>, system?:boolean | settings | T0 |
| brand | 商店品牌資產 | logo:image, square_logo:image, cover_image:image, favicon_url:image, colors, slogan:string, short_description:string, metafields | shop.brand | T2 |
| brand_color | 品牌色 | （string 值） | brand.colors | T2 |
| app | App 資訊（theme app extensions） | metafields | app blocks 內 | T2 |
| closest | 就近資源解析（2024+，Horizon/AI blocks 用） | product, collection, article, blog, page, metaobject | 全域 | T2 |
| self | 當前 Liquid scope 動態解析（2025+） | （動態） | 全域 | T2 |

### 1.7 媒體

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| image | 圖片 | src:string, width:number, height:number, aspect_ratio:number, alt:string, id:number, position:number, presentation:image_presentation, product_id:number, variants:array, attached_to_variant?:boolean, media_type:string, preview_image:image | 各處（product.featured_image、settings…）| T0 |
| image_presentation | 圖片呈現設定 | focal_point:focal_point | image.presentation | T0 |
| focal_point | 焦點座標（% 值） | x:number, y:number | image_presentation.focal_point | T0 |
| media | 媒體抽象父型（product.media 多型） | id:number, media_type:string(image/video/external_video/model), position:number, alt:string, preview_image:image | product.media / featured_media | T0 |
| video | 平台代管影片 | sources:array\<video_source>, duration:number, aspect_ratio:number, alt:string, id, media_type, position, preview_image | product.media / video 設定 / metafield | T0 |
| video_source | 影片來源檔 | url:string, format:string(mp4/m3u8), mime_type:string, width:number, height:number | video.sources | T0 |
| external_video | YouTube/Vimeo 影片 | external_id:string, host:string(youtube/vimeo), aspect_ratio:number, alt, id, media_type, position, preview_image | product.media | T0 |
| model | 3D 模型 | sources:array\<model_source>, alt, id, media_type, position, preview_image | product.media | T0 |
| model_source | 3D 模型來源檔 | url:string, format:string(glb/usdz), mime_type:string | model.sources | T0 |
| generic_file | 一般檔案（file_reference metafield） | url:string, id:number, media_type:string, preview_image:image, position:number, alt:string | metafield.value | T1 |
| images | 全店上傳圖片（by 檔名存取） | `images['x.jpg']` | 全域 | T2 |

### 1.8 Metafield / Metaobject

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| metafield | 自訂欄位 | value:untyped（依 type 回傳 string/number/boolean/json/money/rating/measurement/richtext/參照 drop/list）, type:string, list?:boolean | product/collection/customer/order/shop/… `.metafields.namespace.key` | T1 |
| metaobject | Metaobject 實體（欄位動態存取） | system:metaobject_system, （各欄位為 metafield） | metaobjects[type][handle] / template `metaobject` / settings | T1 |
| metaobjects | 全店 metaobjects（`metaobjects.type.handle`、可迭代 definition） | （動態） | 全域 | T1 |
| metaobject_definition | Metaobject 定義（可迭代 entries） | values:array\<metaobject>, values_count:number | metaobjects.type | T1 |
| metaobject_system | Metaobject 系統資訊 | type:string, handle:string, id:number, url:string | metaobject.system | T1 |
| money | 金額物件（money metafield 值） | currency:currency（本身可被 money filters 格式化） | metafield.value / store_credit_account.balance | T1 |
| rating | 評分 metafield 值 | rating:number, scale_min:number, scale_max:number | metafield.value | T1 |
| measurement | 度量 metafield 值 | type:string, value:number, unit:string | metafield.value | T1 |

### 1.9 集合、搜尋與篩選（faceted search）

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| collection | 商品系列（共 25 屬性） | id:number, title:string, handle:string, description:string, url:string, image:image, featured_image:image, products:array\<product>（分頁後）, products_count:number, all_products_count:number, all_tags:array, tags:array（當前頁）, all_types:array, all_vendors:array, current_type:string, current_vendor:string, filters:array\<filter>, sort_by:string, sort_options:array\<sort_option>, default_sort_by:string, next_product/previous_product:product, metafields, template_suffix, published_at | template `collection`；collections[handle] | T0 |
| collections | 全店系列集合（by handle） | `collections['frontpage']` | 全域 | T0 |
| all_products | 全店商品 by handle（**上限 20 個/頁面**） | `all_products['handle']` | 全域 | T1 |
| filter | Storefront 篩選器 | label:string, param_name:string（如 filter.v.option.color）, type:string(boolean/list/price_range), operator:string(AND/OR), values:array\<filter_value>, active_values:array, inactive_values:array, min_value/max_value:filter_value, false_value/true_value:filter_value, range_max:number, url_to_remove:string, presentation:string(swatch/image/text) | collection.filters / search.filters | T0 |
| filter_value | 篩選值 | label:string, value:string, param_name:string, count:number, active:boolean, url_to_add:string, url_to_remove:string, swatch:swatch, image:image, display(DEP) | filter.values | T0 |
| filter_value_display | **DEPRECATED**（改用 swatch/image） | type:string, value | filter_value.display | T2 |
| sort_option | 排序選項 | name:string, value:string | collection.sort_options / search.sort_options | T0 |
| search | 搜尋結果頁 | performed:boolean, terms:string, results:array（product/article/page 多型）, results_count:number, filters:array, sort_by, sort_options:array, default_sort_by:string, types:array | template `search` | T1 |
| predictive_search | 預測搜尋（Ajax，Section Rendering API） | performed:boolean, terms:string, resources:predictive_search_resources, types:array | predictive search 請求的 section | T1 |
| predictive_search_resources | 預測搜尋結果 | products:array, collections:array, articles:array, pages:array | predictive_search.resources | T1 |
| recommendations | 相關/互補商品推薦（Ajax endpoint） | performed?:boolean, products:array, products_count:number, intent:string(related/complementary) | recommendations 請求的 section | T1 |
| current_tags | 當前套用的 tag 篩選 | （string array） | template `collection`/`blog` | T0 |
| current_page | 當前分頁頁碼 | （number） | 全域 | T0 |
| handle | 當前資源 handle | （string） | 全域（product/collection/page/blog/article 模板有值） | T0 |

### 1.10 分頁與迴圈

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| paginate | 分頁狀態 | current_page:number, current_offset:number, items:number, page_size:number, pages:number, parts:array\<part>, next:part, previous:part, page_param:string | `{% paginate %}` 區塊內 | T0 |
| part | 分頁連結元素 | is_link:boolean, title:string, url:string | paginate.parts/next/previous | T0 |
| forloop | for 迴圈狀態（**gem 內建**） | index/index0, rindex/rindex0, first, last, length, parentloop | for 內 | T0(gem) |
| tablerowloop | tablerow 迴圈狀態（**gem 內建**） | col/col0, row, index/index0, rindex/rindex0, first, last, col_first, col_last, length | tablerow 內 | T0(gem) |

### 1.11 在地化與 Markets

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| localization | 在地化上下文 | available_countries:array\<country>, available_languages:array\<shop_locale>, country:country, language:shop_locale, market:market | 全域 | T0 |
| country | 國家 | name:string, iso_code:string, currency:currency, unit_system:string, market:market, popular?:boolean, continent:string, available_languages:array（+ 可用 image_url 取國旗） | localization.* / address.country | T0 |
| currency | 幣別 | iso_code:string, symbol:string, name:string | country.currency / cart.currency | T0 |
| shop_locale | 語系 | name:string, endonym_name:string, iso_code:string, primary:boolean, root_url:string | localization.language / request.locale | T0 |
| market | Market | id:string, handle:string, metafields | localization.market | T2 |

### 1.12 Selling plans（訂閱）

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| selling_plan_group | 銷售方案群組 | id:number, name:string, app_id:string, options:array\<selling_plan_group_option>, selling_plans:array\<selling_plan>, selling_plan_selected:boolean | product.selling_plan_groups | T2（product.selling_plan_groups 需 T0 空陣列） |
| selling_plan | 銷售方案 | id:number, name:string, description:string, group_id:string, options:array, recurring_deliveries:boolean, selected:boolean, price_adjustments:array, checkout_charge | selling_plan_group.selling_plans | T2 |
| selling_plan_allocation | 方案套用後價格 | price:number, compare_at_price:number, per_delivery_price:number, unit_price:number, price_adjustments:array, selling_plan:selling_plan, selling_plan_group_id:string, checkout_charge_amount:number, remaining_balance_charge_amount:number | variant.selling_plan_allocations / line_item | T2（T0 需 nil-stub） |
| selling_plan_allocation_price_adjustment | 分配價格調整 | position:number, price:number | allocation.price_adjustments | T2 |
| selling_plan_price_adjustment | 方案價格調整規則 | position:number, value_type:string(percentage/fixed_amount/price), value:number, order_count:number | selling_plan.price_adjustments | T2 |
| selling_plan_checkout_charge | 結帳收費方式 | value_type:string, value:number | selling_plan.checkout_charge | T2 |
| selling_plan_group_option | 群組選項 | name:string, position:number, values:array, selected_value:string | selling_plan_group.options | T2 |
| selling_plan_option | 方案選項值 | name:string, position:number, value:string | selling_plan.options | T2 |

### 1.13 Gift card

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| gift_card | 禮品卡 | code:string, last_four_characters:string, balance:number, initial_value:number, currency:string, enabled:boolean, expired:boolean, expires_on:string, url:string, qr_identifier:string, pass_url:string, customer:customer, recipient:recipient, message:string, send_on:string, product:product, variant:variant, properties | template `gift_card.liquid` | T2 |
| recipient | 禮品卡收件人 | name:string, nickname:string, email:string | gift_card.recipient | T2 |

### 1.14 特殊全域變數與其他

| name | 說明 | 關鍵屬性 | 可用範圍 | Tier |
|---|---|---|---|---|
| content_for_header | Shopify 注入 head 的 scripts（layout `<head>` 必含） | （string；復刻層注入自家 analytics/editor scripts） | layout | T0 |
| content_for_layout | 模板輸出注入點（layout `<body>` 必含） | （string） | layout | T0 |
| content_for_index | **舊制** index.liquid 的 sections 內容 | （string） | 僅 Liquid index 模板 | T2 |
| canonical_url | 當前頁 canonical URL | string | 全域 | T0 |
| page_title | SEO 標題 | string | 全域 | T0 |
| page_description | SEO 描述 | string | 全域 | T0 |
| page_image | SEO/社群分享圖 | image | 全域 | T0 |
| powered_by_link | 「Powered by Shopify」連結 HTML | string | 全域 | T1 |
| country_option_tags | 運送區國家 `<option>` 群 | string | 全域 | T2 |
| all_country_option_tags | 全部國家 `<option>` 群 | string | 全域 | T2 |
| form | `{% form %}` 內表單狀態（共 20 屬性） | errors:form_errors, posted_successfully?:boolean, id:string, author/email/body/message:string（contact/comment）, address1/address2/city/country/province/zip/first_name/last_name/company/phone:string（address form）, password_needed:boolean, set_as_default_checkbox:string, name:string | `{% form %}` 內 | T0 |
| form_errors | 表單錯誤 | messages:array\<string>, translated_fields:array\<string> | form.errors | T0 |
| discount | **DEPRECATED**（改用 discount_application） | title, code, amount, total_amount, savings, total_savings, type | cart/order.discounts | T2 |
| scripts / script | **已落日**（Shopify Scripts，2025-08-28 終止） | cart_calculate_line_items:script；id, name | 全域 | T2（免實作） |
| robots | robots.txt 規則 | default_groups:array\<group> | template `robots.txt.liquid` | T2 |
| group | robots 規則群 | user_agent:user_agent, rules:array\<rule>, sitemap:sitemap | robots.default_groups | T2 |
| rule | robots 規則 | directive:string, value:string | group.rules | T2 |
| sitemap | robots sitemap | directive:string, value:string | group.sitemap | T2 |
| user_agent | robots UA | directive:string, value:string | group.user_agent | T2 |
| remote_product | 遠端來源商品（2025+，繼承 product 全屬性 + remote_details） | remote_details:remote_details + product 同構（42 屬性） | search.results 等 | T2 |
| remote_details | 遠端來源資訊 | type:string, shop:remote_shop | remote_product | T2 |
| remote_shop | 遠端商店 | name:string, brand:brand, policies:array, shipping_policy/refund_policy:policy | remote_details.shop | T2 |

**Objects 統計：T0 = 54、T1 = 37、T2 = 47（含 deprecated 6 + 落日 2）。**

來源：https://shopify.dev/docs/api/liquid/objects 、https://github.com/Shopify/theme-liquid-docs（data/objects.json）

---

## 2. Tags（30 個文件化 + `{% schema %}`）

語言核心（if/for/assign 等）由 liquid gem 免費取得；「實作」欄標 gem = 零工作量。運算子（`==,!=,>,<,>=,<=,contains,and,or`）、whitespace control（`{%- -%}`）、range `(1..n)`、`blank/empty/nil`、`{% # 行內註解 %}` 皆為 gem 語言層。

| name | 分類 | 語法 | 行為要點 | 實作 | Tier |
|---|---|---|---|---|---|
| if / elsif / else / endif | conditional | `{% if cond %}…{% endif %}` | 條件渲染 | gem | T0 |
| unless | conditional | `{% unless cond %}…{% endunless %}` | 反向條件 | gem | T0 |
| case / when / else | conditional | `{% case var %}{% when v %}…{% endcase %}` | 多值分支；when 可逗號/or 多值 | gem | T0 |
| for / else / endfor | iteration | `{% for x in arr limit:n offset:n reversed %}` | 迭代；參數 limit/offset/reversed/range `(1..n)`；else = 空集合時 | gem | T0 |
| break / continue | iteration | `{% break %}` `{% continue %}` | 迴圈控制 | gem | T0 |
| cycle | iteration | `{% cycle 'a','b' %}`（可加 group 名） | 輪替輸出 | gem | T0 |
| tablerow | iteration | `{% tablerow x in arr cols:3 limit offset %}` | 產生 `<tr><td>`；參數 cols/limit/offset/range | gem | T0 |
| paginate | iteration | `{% paginate coll.products by 24 window_size: 3 %}…{% endpaginate %}` | 分頁包裹 for；每頁上限 50；提供 paginate 物件；page URL 參數 `?page=N`；window_size 控制頁碼窗 | **平台** | T0 |
| assign | variable | `{% assign x = value \| filter %}` | 宣告變數 | gem | T0 |
| capture | variable | `{% capture x %}…{% endcapture %}` | 捕捉渲染結果為字串 | gem | T0 |
| increment / decrement | variable | `{% increment c %}` | 獨立計數器（與 assign 變數不同名空間），輸出後 +1 / -1 起始 0 / -1 | gem | T0 |
| echo | syntax | `{% liquid echo expr %}` | 於 liquid tag 內輸出，等同 `{{ }}` | gem | T0 |
| liquid | syntax | `{% liquid …多行… %}` | 無分隔符多行 Liquid | gem | T0 |
| raw | syntax | `{% raw %}…{% endraw %}` | 不解析輸出 | gem | T0 |
| comment | syntax | `{% comment %}…{% endcomment %}` | 註解不輸出 | gem | T0 |
| doc | syntax | `{% doc %}@param {type} name - desc / @example{% enddoc %}` | 文件註解（LLM/editor 用），渲染不輸出；新版 gem 已支援，舊版需補 no-op | gem(新)/平台 | T0 |
| render | theme | `{% render 'snippet', var: x %}`；`{% render 'x' with obj as name %}`；`{% render 'x' for arr as item %}` | 渲染 snippets/*.liquid；**隔離 scope**（僅傳入參數可見）；for 版提供 forloop | gem | T0 |
| include | theme | `{% include 'snippet' %}` | **DEPRECATED**；共享父 scope；gem 已含 | gem | T2 |
| section | theme | `{% section 'name' %}` | 靜態渲染單一 section（含其 JSON 設定） | **平台** | T0 |
| sections | theme | `{% sections 'header-group' %}` | 渲染 section group（sections/*.json） | **平台** | T0 |
| layout | theme | `{% layout 'full-width' %}` / `{% layout none %}` | 指定 layout/*.liquid；none = 無 layout | **平台** | T0 |
| content_for | theme | `{% content_for 'blocks' %}` / `{% content_for 'block', type:'text', id:'static-1' %}` | theme blocks 渲染點：'blocks' = 依 JSON 順序渲染子 blocks；'block' = 靜態渲染指定 block | **平台** | T0 |
| form | html | `{% form 'type'[, object][, return_to: url][, id:, class:, data-*: ] %}…{% endform %}` | 產生 `<form>` + hidden inputs（form_type/utf8）+ 對應 action；提供 form 物件；型別見下表 | **平台** | T0 |
| style | html | `{% style %}CSS{% endstyle %}` | 輸出 `<style data-shopify>`；Dawn 用於 section 內 CSS 變數 | **平台** | T0 |
| stylesheet | html/theme | `{% stylesheet %}CSS{% endstylesheet %}` | section/block/snippet 內 CSS；全站彙整去重為單一資產輸出 | **平台** | T0 |
| javascript | theme | `{% javascript %}JS{% endjavascript %}` | 同上之 JS 彙整（每 section 一次） | **平台** | T0 |
| schema | theme | `{% schema %}{JSON}{% endschema %}`（文件在 architecture 區，非 tags 區） | section/block 的設定 schema；**不渲染**；每檔一個、不可含 Liquid、不可巢狀於其他 tag | **平台** | T0 |

### form 的 type 枚舉（15 種）

| type | 參數 | action / 行為 | Tier |
|---|---|---|---|
| product | product 物件（必填） | POST `/cart/add`；含 variant id input | T0 |
| cart | cart 物件（必填） | POST `/cart`；結帳/更新 note 與 attributes | T0 |
| localization | — | POST `/localization`；country/language selector（Dawn header/footer） | T0 |
| contact | — | POST `/contact`；form.author/email/body | T1 |
| customer_login | — | POST 登入；form.password_needed | T1 |
| create_customer | — | POST 註冊 | T1 |
| recover_customer_password | — | 密碼救援；form.posted_successfully? | T1 |
| reset_customer_password | — | 重設密碼（信件連結頁） | T1 |
| activate_customer_password | — | 啟用帳號（信件連結頁） | T1 |
| customer_address | customer.new_address 或既有 address（必填） | 新增/編輯地址；delete 用 method override | T1 |
| customer | — | 訂閱名單（無帳號）；form.email | T1 |
| new_comment | article 物件（必填） | POST 文章留言 | T1 |
| guest_login | — | 密碼保護店的訪客結帳返回 | T1 |
| storefront_password | — | password 頁登入 | T1 |
| currency | — | **DEPRECATED**（改用 localization） | T2 |

**Tags 統計：31 項（含 schema）：T0 = 30（其中 gem 免實作 18）、T2 = 1（include，gem 已含）。平台需實作：paginate、section、sections、layout、content_for、form、style、stylesheet、javascript、schema（10 個）。**

來源：https://shopify.dev/docs/api/liquid/tags 、https://shopify.dev/docs/storefronts/themes/architecture/sections/section-schema（schema tag）

---

## 3. Filters（153 個唯一；154 條目中 date 重複歸類）

「實作」欄：gem = Shopify/liquid 內建（含 5.x 新增之 find/find_index/has/reject/sum/remove_last/replace_last/base64 系列）；平台 = 需自行實作。

### 3.1 array（17，全 gem，全 T0）

| name | 簽名 | 行為 | 實作 | Tier |
|---|---|---|---|---|
| compact | array → array | 移除 nil | gem | T0 |
| concat | array \| concat: array → array | 串接 | gem | T0 |
| find | array \| find: prop, value → item | 首個符合屬性值的項 | gem(新) | T0 |
| find_index | array \| find_index: prop, value → number | 首個符合項之索引 | gem(新) | T0 |
| first | array → item | 第一項 | gem | T0 |
| has | array \| has: prop, value → boolean | 是否存在符合項 | gem(新) | T0 |
| join | array \| join: sep → string | 合併字串（預設空白） | gem | T0 |
| last | array → item | 最末項 | gem | T0 |
| map | array \| map: prop → array | 取屬性投影 | gem | T0 |
| reject | array \| reject: prop[, value] → array | 排除符合項（where 反向） | gem(新) | T0 |
| reverse | array → array | 反轉 | gem | T0 |
| size | string\|array → number | 長度（亦可 `.size`） | gem | T0 |
| sort | array → array | 區分大小寫排序；可帶屬性 | gem | T0 |
| sort_natural | array → array | 不分大小寫排序 | gem | T0 |
| sum | array \| sum[: prop] → number | 加總 | gem(新) | T0 |
| uniq | array → array | 去重 | gem | T0 |
| where | array \| where: prop[, value] → array | 篩選符合項 | gem | T0 |

### 3.2 string（40：gem 31 + 平台 9）

| name | 簽名 | 行為 | 實作 | Tier |
|---|---|---|---|---|
| append / prepend | string \| append: s → string | 前後串接 | gem | T0 |
| capitalize / upcase / downcase | string → string | 大小寫 | gem | T0 |
| escape / escape_once | string → string | HTML escape | gem | T0 |
| lstrip / rstrip / strip | string → string | 去空白 | gem | T0 |
| newline_to_br | string → string | `\n` → `<br>` | gem | T0 |
| remove / remove_first / remove_last | string \| remove: s → string | 移除子字串 | gem | T0 |
| replace / replace_first / replace_last | string \| replace: a, b → string | 取代 | gem | T0 |
| slice | string\|array \| slice: offset[, len] → 同型 | 0-based 切片（負索引可） | gem | T0 |
| split | string \| split: sep → array | 切割 | gem | T0 |
| strip_html | string → string | 去 HTML 標籤 | gem | T0 |
| strip_newlines | string → string | 去換行 | gem | T0 |
| truncate | string \| truncate: n[, ellipsis] → string | 截斷（含 "…"） | gem | T0 |
| truncatewords | string \| truncatewords: n[, ellipsis] → string | 按詞截斷 | gem | T0 |
| url_encode / url_decode | string → string | percent-encoding | gem | T0 |
| url_escape / url_param_escape | string → string | URL 安全 escape（param 版連 `&` 也轉） | 平台 | T0 |
| base64_encode / base64_decode | string → string | Base64 | gem | T2 |
| base64_url_safe_encode / base64_url_safe_decode | string → string | URL-safe Base64 | gem | T2 |
| handleize（alias: handle） | string → string | 轉 handle（小寫、連字號） | 平台 | T0 |
| camelize | string → string | 轉 CamelCase | 平台 | T2 |
| pluralize | number \| pluralize: singular, plural → string | 英文單複數 | 平台 | T1 |
| md5 / sha1 / sha256 | string → string | 雜湊（md5 用於 gravatar 等） | 平台 | T2 |
| hmac_sha1 / hmac_sha256 | string \| hmac_sha256: secret → string | HMAC | 平台 | T2 |
| blake3 | string → string | Blake3 雜湊（2025 新增，官方建議取代 md5/sha） | 平台 | T2 |

### 3.3 math（11，全 gem，全 T0）

abs、at_least、at_most、ceil、floor、round、plus、minus、times、divided_by（除數型別決定結果型別：整數除法截斷）、modulo。簽名皆 `number | f[: number] → number`。

### 3.4 money（5，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| money | number(cents) → string | 按商店「不含幣別」格式（如 `${{amount}}` → $12.34） | T0 |
| money_with_currency | number → string | 按「含幣別」格式（$12.34 CAD） | T0 |
| money_without_currency | number → string | 只有數字（12.34） | T0 |
| money_without_trailing_zeros | number → string | 去小數尾零（$12） | T0 |
| money_amount | number → string | 純十進位字串，無符號/千分位/在地化（2025 新增） | T1 |

格式模板來自 `shop.money_format` / `shop.money_with_currency_format`，占位符 `{{amount}}`、`{{amount_no_decimals}}`、`{{amount_with_comma_separator}}`、`{{amount_no_decimals_with_comma_separator}}`、`{{amount_with_apostrophe_separator}}`。

### 3.5 media（12，平台）

| name | 簽名 | 行為 / 關鍵參數 | Tier |
|---|---|---|---|
| image_url | image\|product\|variant\|line_item\|collection\|article\|country(旗) \| image_url: width:, height: → string | 回傳 CDN URL。**必須給 width 或 height 之一，否則錯誤**；**上限各 5760px**；不放大原圖。參數：`crop:`(top/center/bottom/left/right/**region**，預設 center)、`format:`(jpg/pjpg；WebP/AVIF 自動協商)、`pad_color:`(hex) | T0 |
| image_tag | string(image_url 結果) \| image_tag → string | 產生 `<img>`；參數 width/height/widths(產 srcset)/sizes/srcset/alt/preload/loading 及任意 HTML 屬性；自動帶 width/height/alt | T0 |
| media_tag | media → string | 依 media_type 產生對應標籤；參數 image_size | T0 |
| video_tag | video → string | `<video>`（含 mp4+m3u8 sources）；參數 image_size、autoplay、loop、muted、controls | T0 |
| external_video_tag | external_video → string | YouTube/Vimeo `<iframe>`；可傳任意屬性 | T0 |
| external_video_url | external_video \| external_video_url: attr: value → string | 外部播放器 URL 加參數（autoplay 等） | T0 |
| model_viewer_tag | model → string | Google `<model-viewer>`；參數 image_size 等 | T0 |
| img_url | **DEPRECATED**（→ image_url）；size 字串參數（'450x450'）、crop/scale/format | 舊主題大量使用；若目標含舊主題應提前 | T2 |
| img_tag | **DEPRECATED**（→ image_tag）；alt/class/size | 同上 | T2 |
| product_img_url / collection_img_url / article_img_url | **DEPRECATED**（→ image_url）；size | 同上 | T2 |

### 3.6 hosted_file（6，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| asset_url | string(檔名) → string | theme `assets/` 檔案 CDN URL（帶版本 query） | T0 |
| asset_img_url | string \| asset_img_url[: size] → string | assets 圖片 URL（舊式 size） | T1 |
| file_url | string → string | 商店 Files（後台上傳）URL | T1 |
| file_img_url | string \| file_img_url[: size] → string | Files 圖片 URL | T1 |
| global_asset_url | string → string | Shopify 全域資產（舊 jquery 等） | T2 |
| shopify_asset_url | string → string | Shopify 平台資產（option_selection.js 等） | T2 |

### 3.7 html（8，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| stylesheet_tag | string(url) → string | `<link rel="stylesheet">`；參數 media、preload:boolean（加 Link header） | T0 |
| script_tag | string(url) → string | `<script src type="text/javascript">` | T0 |
| preload_tag | string(url) \| preload_tag: as: 'font' → string | `<link rel="preload">` + Link header；參數 as(必)、type、crossorigin 等 | T0 |
| inline_asset_content | string(assets 檔名) → string | 將 SVG/JS/CSS 資產內容內聯輸出；**限 <15KB**（Horizon icon 系統重度使用） | T0 |
| placeholder_svg_tag | string(名稱) \| placeholder_svg_tag[: class] → string | 佔位 SVG（product-1…6、collection-1…6、lifestyle-1/2、image、product-apparel-*、hero-apparel-* 等） | T0 |
| time_tag | date \| time_tag[: format 或 strftime][, datetime: fmt] → string | `<time datetime="ISO8601">格式化日期</time>` | T1 |
| link_to | string(文字) \| link_to: url[, title 等 HTML 屬性] → string | `<a href>` | T1 |
| highlight | string \| highlight: term → string | 以 `<strong class="highlight">` 包裹搜尋詞 | T1 |

### 3.8 format（6，平台；date 於 date/format 兩類重複計）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| date | string\|date \| date: strftime 或 format: 'name' → string | strftime 全支援（gem 有基本版）；**平台需覆寫**支援命名格式：`abbreviated_date`、`basic`、`date`、`date_at_time`、`default`、`on_date`（+ deprecated `short`/`long`），命名格式定義於 locale 檔 `date_formats` 群、可自訂、隨語系在地化；輸入 'now'/'today' 可用 | T0 |
| json | any → string | 序列化為 JSON（drop 走白名單屬性）；輸出含引號、內部引號 escape；product 的 variant 不輸出 inventory_quantity/inventory_policy（2017-12 後商店） | T0 |
| structured_data | product\|article → string | schema.org JSON-LD：product→Product/ProductGroup（有變體）、article→Article（Horizon 使用） | T0 |
| weight_with_unit | number(grams) \| weight_with_unit[: unit] → string | 依商店單位格式化重量 | T1 |
| unit_price_with_measurement | number \| unit_price_with_measurement: unit_price_measurement → string | 單位價格顯示（€9.99/100g） | T1 |
| standard_event_data | event \| standard_event_data: context: string → string | 分析事件 JSON payload | T2 |

### 3.9 localization（3，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| translate（**alias: t**） | string(key) \| t[: 具名插值…, count: n] → string | 從 locales/*.json 查翻譯；插值 `{{ name }}`；`count:` 觸發複數鍵（zero/one/two/few/many/other）；`_html` 結尾鍵不 escape；缺鍵輸出 `Translation missing: locale.key`；schema 內 `t:` 前綴由 *.schema.json 解析 | T0 |
| format_address | address → string | 依國家地址格式輸出 HTML | T1 |
| currency_selector | **DEPRECATED**（form 'currency' 內）；class/id 參數 | → localization form | T2 |

### 3.10 color（16，平台，純函數）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| color_to_rgb / color_to_hsl / color_to_hex / color_to_oklch | string → string | 色彩空間轉換（hex6；oklch 為 2025 新增） | T0 |
| color_extract | string \| color_extract: 'red'\|'green'\|'blue'\|'hue'\|'saturation'\|'lightness'\|'alpha' → number | 抽取分量 | T0 |
| color_modify | string \| color_modify: component, value → string | 改分量（含 alpha） | T0 |
| color_lighten / color_darken | string \| f: percent(0-100) → string | 加亮/加深 | T0 |
| color_saturate / color_desaturate | string \| f: percent → string | 飽和度 | T0 |
| color_mix | string \| color_mix: color, percent → string | 混色 | T0 |
| color_brightness | string → number | 感知亮度（0-255） | T0 |
| brightness_difference / color_difference | string \| f: color → number | W3C 亮度差/色差 | T0 |
| color_contrast | string \| color_contrast: color → number | 對比度（回傳比值分子） | T0 |
| hex_to_rgba | **DEPRECATED**（→ color_to_rgb + color_modify）；alpha 參數 | | T2 |

### 3.11 font（3，平台，全 T0）

| name | 簽名 | 行為 |
|---|---|---|
| font_url | font \| font_url[: 'woff'] → string | 字型 CDN URL（預設 woff2） |
| font_face | font \| font_face[: font_display: 'swap'] → string | 產生 `@font-face` 宣告 |
| font_modify | font \| font_modify: 'weight'\|'style', value → font | 變體（'bolder'、'+100'、'italic' 等；無則回 nil） |

### 3.12 default（3）

| name | 簽名 | 行為 | 實作 | Tier |
|---|---|---|---|---|
| default | any \| default: fallback[, allow_false: true] → any | nil/false/empty 時回 fallback | gem | T0 |
| default_pagination | paginate \| default_pagination[: previous:, next:, anchor:] → string | 產生整組分頁 HTML | 平台 | T0 |
| default_errors | form.errors → string | 表單錯誤預設訊息 HTML | 平台 | T1 |

### 3.13 collection 導覽（7，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| sort_by | string(collection.url) \| sort_by: 'price-ascending' → string | URL 加 sort_by 參數；值枚舉：manual、best-selling、title-ascending、title-descending、price-ascending、price-descending、created-ascending、created-descending | T0 |
| within | string(product.url) \| within: collection → string | 產生 `/collections/x/products/y` 上下文 URL | T1 |
| highlight_active_tag | string(tag) \| highlight_active_tag → string | 當前 tag 包 `<span class="active">` | T1 |
| link_to_type / link_to_vendor | string \| f[: HTML 屬性] → string | 連到 type/vendor 系列頁 `<a>` | T1 |
| url_for_type / url_for_vendor | string → string | `/collections/types?q=` / `/collections/vendors?q=` URL | T1 |

### 3.14 tag 篩選（3，平台，全 T1）

link_to_add_tag / link_to_remove_tag / link_to_tag：`string(tag) | f: tag → string`，產生在 blog/collection 加/移除/單選 tag 篩選的 `<a>`。

### 3.15 customer（5，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| customer_login_link / customer_logout_link / customer_register_link | string(連結文字) → string | 登入/登出/註冊 `<a>` | T1 |
| avatar | customer → string | 客戶頭像 HTML | T1 |
| login_button | shop \| login_button[: action: 'default'\|'follow'] → string | Shop 帳號登入按鈕（Sign in with Shop） | T2 |

### 3.16 payment（4，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| payment_type_svg_tag | string(payment type) \| f[: class] → string | 付款方式 SVG（Dawn footer 圖示） | T0 |
| payment_type_img_url | string → string | 付款方式 SVG 圖 URL | T1 |
| payment_button | form \| payment_button → string | 動態結帳按鈕（Shop Pay 等）；限 product form 內（Dawn buy-buttons 預設開啟 → T0 需輸出空 stub） | T1 |
| payment_terms | form \| payment_terms → string | Shop Pay Installments 分期橫幅；product/cart form 內 | T2 |

### 3.17 metafield（2，平台，全 T1）

| name | 簽名 | 行為 |
|---|---|---|
| metafield_tag | metafield → string | 依 type 產生語意 HTML（rich text→HTML、file→img、url→a…）；參數 field:、list_format: unordered/ordered；list 型僅支援 single_line_text_field/metaobject_reference |
| metafield_text | metafield \| metafield_text[: field] → string | 純文字化 |

### 3.18 cart（2，平台）

| name | 簽名 | 行為 | Tier |
|---|---|---|---|
| item_count_for_variant | cart \| item_count_for_variant: variant_id → number | 車內某 variant 總數（商品頁數量規則 UI） | T1 |
| line_items_for | cart \| line_items_for: product\|variant → array | 車內含該商品/變體的行項（volume pricing） | T2 |

**Filters 統計：T0 = 103（其中 gem 免實作約 60）、T1 = 30、T2 = 20（含 deprecated 8）。平台需實作總數約 93。**

來源：https://shopify.dev/docs/api/liquid/filters 、https://shopify.dev/docs/api/liquid/filters/image_url 、https://shopify.dev/docs/api/liquid/filters/date 、https://github.com/Shopify/theme-liquid-docs（data/filters.json）

---

## 4. 模板結構與 schema（JSON 欄位規格）

### 4.1 Theme 資料夾佈局

```
theme/
├── layout/          # theme.liquid（唯一必要檔）；password.liquid；<head> 必含 {{ content_for_header }}，<body> 必含 {{ content_for_layout }}
├── templates/       # 頁面模板：*.json（JSON template）或 *.liquid；上限 1,000 個 JSON templates
│   ├── customers/   # 舊制客戶帳號模板（Dawn 使用；官方標 legacy）
│   └── metaobject/  # metaobject 模板（metaobject.{type}.json）
├── sections/        # section（*.liquid，含 {% schema %}）與 section groups（*.json）
├── blocks/          # theme blocks（*.liquid，含 {% schema %}）；每主題上限 300 檔
├── snippets/        # {% render %} 目標（*.liquid）
├── config/          # settings_schema.json、settings_data.json（上限 1.5MB）
├── locales/         # en.default.json（storefront）、en.default.schema.json（editor）、zh-TW.json…
└── assets/          # 平面資料夾（無子目錄）；支援 .css.liquid / .js.liquid（有限 Liquid）
```

**Template 類型全表**（`request.page_type` 對應）：404、article、blog、cart、collection、list-collections、gift_card（僅 .liquid）、index、page、password、product、robots.txt（僅 .liquid）、search、metaobject、agents.md / llms.txt / llms-full.txt（2025+，僅 .liquid），以及 customers/account、customers/activate_account、customers/addresses、customers/login、customers/order、customers/register、customers/reset_password（官方標 deprecated，但 Dawn 等傳統主題必需）。
**Alternate templates**：`product.summer.json` → `template.suffix == "summer"`；亦可用 URL `?view=summer` 指定。

### 4.2 JSON template 格式（templates/*.json）

| 欄位 | 型別 | 說明 |
|---|---|---|
| layout | string \| false（選填） | 指定 layout 檔名（不含副檔名）；false = 不用 layout；預設 theme.liquid |
| wrapper | string（選填） | 包裹全部 sections 的 HTML 元素，僅 div/main/section + CSS selector 語法（`"div#main.css-class[attr=value]"`） |
| sections | object（必填） | `{ "<section_id>": { "type": "<section 檔名>", "disabled": bool?, "settings": {...}, "blocks": { "<block_id>": { "type", "settings", "blocks"(巢狀), "block_order" } }, "block_order": [ids], "custom_css": [...]? } }`；id 模板內唯一 |
| order | array（必填） | section id 渲染順序；須存在於 sections、不可重複 |

限制：每 template ≤ **25 sections**；每 section ≤ **50 blocks**；全主題 ≤ 1,000 JSON templates。settings 值使用 JSON 六種原生型別：**string / number / boolean / null / array / object**（各 setting type 的序列化見第 5 節）。

### 4.3 Section schema（{% schema %} 全欄位）

| 欄位 | 型別 | 規格 |
|---|---|---|
| name | string | 編輯器顯示名（必填） |
| tag | string | 包裹元素，枚舉：article、aside、div、footer、header、section（預設 div；輸出 `<tag id="shopify-section-{id}" class="shopify-section">`） |
| class | string | 附加至包裹元素 class |
| limit | number | 每 template/group 可加入次數，**僅允許 1 或 2** |
| settings | array\<setting> | 見第 5 節；id 於 section 內唯一 |
| blocks | array | 區塊定義。三種形態：**section 本地 blocks** `{type(自由字串), name, limit, settings[]}`（單層、不可巢狀）；**theme blocks 接受器** `{"type":"@theme"}` / `{"type":"@app"}`；**指定 theme block** `{"type":"<blocks/ 檔名>"}`。**本地 blocks 與 theme blocks 不可在同一 section 混用** |
| max_blocks | number | 上限 50（預設 50） |
| presets | array | 動態加入用預設。欄位：name（必填）、category、settings{}、blocks（陣列或 hash，theme blocks 可含巢狀 blocks + block_order） |
| default | object | 靜態渲染（{% section %}）的預設值；結構同 preset（無 name） |
| locales | object | section 專屬翻譯 `{ "en": { "key": "v" } }` |
| enabled_on / disabled_on | object | 互斥。`{ "templates": ["product", "*"…], "groups": ["header","footer","aside","custom.<name>"] }`；enabled_on 白名單、disabled_on 黑名單 |

### 4.4 Theme blocks（/blocks 資料夾）

- 檔案 = `blocks/*.liquid`，含自身 `{% schema %}`：欄位 **name、settings、blocks（可含 @theme/@app/指定 type）、presets、tag（任意字串 ≤50 字元）、class**；包裹元素帶 `shopify-block` class。
- 渲染：section/block 內用 `{% content_for 'blocks' %}` 依 JSON 順序渲染子 blocks；靜態 block 用 `{% content_for 'block', type: 'x', id: '唯一id' %}`（商家可隱藏、不可刪除）。
- 巢狀：blocks 可遞迴巢狀，**深度上限 8 層（不含 section 層；Shopify staff 於社群確認之文件化上限）**；每主題 ≤ 300 個 block 檔。
- `block.shopify_attributes` 必須輸出在 block 根元素上（editor 對應）。
- app blocks：`@app` 接受app 注入區塊；`{% render block %}` 於本地 blocks 迴圈中渲染 app block。

### 4.5 Section groups（sections/*.json）

`{ "type": "header"|"footer"|"aside"|"custom.<name>", "name": string(≤50), "sections": {...同 JSON template...}, "order": [...] }`，由 layout 以 `{% sections 'file-name' %}` 引入；≤25 sections/group；group 內可含 app sections。

### 4.6 config/settings_schema.json

陣列。第一項慣例為 theme_info：`{ "name": "theme_info", "theme_name"*, "theme_version"*, "theme_author"*, "theme_documentation_url"*, "theme_support_email" XOR "theme_support_url" }`。其餘為分類：`{ "name": string(分類名，可 t: 鍵), "settings": [setting...] }`。

### 4.7 config/settings_data.json

`{ "current": {settings 值, "sections": {…section groups 實例}, "blocks": …} | "preset 名稱字串", "presets": { "名稱": {同 current 結構} }, "platform_customizations": {…平台控制設定} }`。上限 **1.5MB**、presets ≤ **5** 個。theme editor 寫入 current。

### 4.8 Locales

- `locales/en.default.json`（storefront 文案，t filter 查詢）；巢狀鍵 + 複數（one/other…）+ `_html` 尾綴；`date_formats` 群定義命名日期格式。
- `locales/en.default.schema.json`（editor 翻譯，供 schema 內 `t:sections.header.name` 鍵解析）。
- 系統翻譯 `shopify.*` 鍵（如 shopify.pagination.*、shopify.sentence.*）由平台提供（theme-liquid-docs 的 `data/shopify_system_translations.json` 有完整清單）。

來源：https://shopify.dev/docs/storefronts/themes/architecture 、…/architecture/templates 、…/architecture/templates/json-templates 、…/architecture/sections/section-schema 、…/architecture/section-groups 、…/architecture/blocks 、…/architecture/blocks/theme-blocks 、…/architecture/config/settings-data-json 、[Nested blocks depth limit（Shopify 社群，staff 確認 8 層）](https://community.shopify.dev/t/nested-blocks-depth-limit/35499)

---

## 5. Setting input types 全表（35 種）

共通欄位：`type`*、`id`*（sidebar 型免）、`label`*、`default`、`info`、`visible_if`（條件顯示，值為 Liquid 布林字串如 `"{{ section.settings.show == true }}"`）。

| type | 儲存值（JSON 序列化） | Liquid 回傳 | UI 控件 | 專屬欄位 / 限制 | Tier |
|---|---|---|---|---|---|
| text | string | string（空→blank） | 單行文字 | placeholder | T0 |
| textarea | string | string | 多行文字 | placeholder | T0 |
| richtext | string（`<p>…</p>` HTML） | string(HTML) | 富文字編輯器 | default 須以 `<p>` 包裹 | T0 |
| inline_richtext | string（不含 `<p>` 的 inline HTML） | string(HTML) | 行內富文字 | | T0 |
| html | string | string | HTML 原始碼框 | placeholder | T0 |
| liquid | string（Liquid 原始碼） | string（渲染後） | Liquid 框 | **≤50KB**；受限子集（不可 include/layout/section 等） | T0 |
| number | number | number \| nil | 數字框 | placeholder、min、max（0.1 步進）、options、icon | T0 |
| range | number | number | 滑桿 | min*、max*、step、unit、default*；**步數 (max−min)/step ≤ 101** | T0 |
| checkbox | boolean | boolean（預設 false） | 勾選框 | | T0 |
| select | string | string | 下拉（options 或 group） | options*: [{value,label,group?}] | T0 |
| radio | string | string | 單選鈕 | options*: [{value,label}] | T0 |
| text_alignment | string("left"/"center"/"right") | string | 對齊選擇器 | 預設 left | T0 |
| color | string（"#RRGGBB" 或 rgba） | color 物件 \| blank | 色彩選擇器 | alpha:boolean、placeholder | T0 |
| color_background | string（CSS background 值） | string | 背景（含漸層）輸入 | | T0 |
| color_scheme | string（scheme id） | color_scheme 物件 | 方案選擇器 | 預設回第一個 scheme | T0 |
| color_scheme_group | —（定義群組本身） | 可迭代 color_scheme_group | 方案編輯器（僅 settings_schema.json 可用） | definition*: [color/color_background/image_picker 設定…], role*: {background,text,primary_button…對應} | T0 |
| color_palette | object（色名→色值 map；搭配 {solid,gradient}） | 各色為 color 物件 | 調色盤選擇器（2025+） | default: {名稱:色值}（1–20 項，名稱 `^[a-zA-Z]\w*$`） | T1 |
| font_picker | string（字型 handle，如 "assistant_n4"） | font 物件 | 字型選擇器 | default* 必填 | T0 |
| image_picker | string（"shopify://shopify/files/x.png"） | image 物件 \| nil | 圖庫選擇器 | 支援焦點（image.presentation.focal_point） | T0 |
| video | string（平台影片參照/gid） | video 物件 \| nil | 影片選擇器 | | T0 |
| video_url | string（完整 URL） | string（帶 .id、.type 屬性） | URL 框 | accept*: ["youtube","vimeo"]、placeholder | T0 |
| url | string（"/collections/x" 或 "shopify://collections/x" 內部參照） | string | 連結選擇器 | shopify:// scheme 需解析 | T0 |
| collection | string（handle） | collection 物件 \| blank | 系列選擇器 | | T0 |
| collection_list | array\<string>（handles） | array\<collection> | 多系列 | limit | T0 |
| product | string（handle） | product 物件 \| blank | 商品選擇器 | | T0 |
| product_list | array\<string> | array\<product> | 多商品 | limit | T0 |
| blog | string（handle） | blog 物件 \| blank | 部落格選擇器 | | T1 |
| article | string（"blog-handle/article-handle"） | article 物件 \| blank | 文章選擇器（新） | | T2 |
| article_list | array\<string> | array\<article> | 多文章（新） | limit | T2 |
| page | string（handle） | page 物件 \| blank | 頁面選擇器 | | T1 |
| link_list | string（menu handle） | linklist 物件 \| blank | 選單選擇器 | | T0 |
| metaobject | string（參照/gid） | metaobject \| blank | metaobject 選擇器 | metaobject_type* | T2 |
| metaobject_list | array | array\<metaobject> | 多 metaobject | metaobject_type*、limit | T2 |
| header | —（無值） | — | 側欄小標 | content*（顯示文字）、info | T0（schema 解析必須接受） |
| paragraph | —（無值） | — | 側欄說明文字 | content* | T0（同上） |

資源型設定皆為 **lazy loading**（未使用不查詢，對應 drop 需惰性實作）；資源被刪除/未設定時回 blank（`if setting != blank` 為主題慣用防衛）。

來源：https://shopify.dev/docs/storefronts/themes/architecture/settings/input-settings 、theme-liquid-docs `schemas/theme/setting.json`（35 型別 enum 與逐型別欄位為該 schema 原文）

---

## 6. T0/T1/T2 統計與優先級結論

### 6.1 數量統計

| 類別 | 總數 | T0 | T1 | T2 | 其中 gem 免實作 | 平台需實作 |
|---|---|---|---|---|---|---|
| Objects (drops) | 138 | 54 | 37 | 47（含 dep/落日 8） | 2（forloop、tablerowloop） | 136（T0 實作 52） |
| Tags | 31（30+schema） | 30 | 0 | 1 | 19（含 include） | 10（paginate、form、section、sections、layout、content_for、schema、style、stylesheet、javascript） |
| Filters | 153 | 103 | 30 | 20（含 dep 8） | 約 60 | 約 93（T0 實作約 43） |
| Setting types | 35 | 27 | 4 | 4 | 0 | 35（schema 解析器一次做完） |

### 6.2 T0 最小可跑集（Dawn/Horizon 首頁+商品頁+系列頁）

1. **渲染管線**：request 解析 → template 解析（JSON template + alternate suffix）→ layout（content_for_header/content_for_layout）→ `{% sections %}` section groups → section 渲染（schema/settings 綁定、`{% style %}`/`{% stylesheet %}`/`{% javascript %}` 彙整）→ theme blocks（`{% content_for %}`、8 層巢狀、shopify_attributes）。
2. **核心 drops（52）**：product/variant/option 族、collection+filters/sort、cart+line_item、image/media 族、shop/routes/settings/section/block/template、linklist 族、localization 族、font/color/color_scheme 族、paginate/part、form/form_errors、SEO 全域變數。
3. **平台 tags（10）**與 **T0 filters（約 43 個平台實作）**：image_url/image_tag（含 5760px、crop、srcset）、asset_url、money×4、t（插值+複數+date_formats）、date、json、structured_data、default_pagination、sort_by、color×15、font×3、inline_asset_content、placeholder_svg_tag、preload/script/stylesheet_tag、payment_type_svg_tag、handleize、url_escape/url_param_escape、media tags×7。
4. **nil-stub 契約**（防 Dawn/Horizon 模板炸裂）：customer=nil、selling plan 相關屬性=nil/空陣列、quantity_rule 預設值、discount_* 空陣列、unit_price=nil、payment_button 空輸出、additional_checkout_buttons=false。

### 6.3 T1（完整店面）

blog/article/comment、search + predictive_search + recommendations（**需同時實作 Section Rendering API 與 `/search/suggest`、`/recommendations/products` endpoints**）、customer 全家（7 個 customers/* 模板 + 10 種 form types）、order/fulfillment/transaction、metafield/metaobject 值系統（含 metafield_tag/metafield_text）、policy/pages、cart 進階（discount 顯示、item_count_for_variant、additional_checkout_buttons）、file_url 族、tag 篩選 filters、format_address/avatar。

### 6.4 T2（長尾）

selling plans（8 objects）、gift card（模板 + recipient）、B2B（company 族、quantity 規則、line_items_for）、markets 進階（market、@app、brand）、store pickup（location/store_availability）、robots/llms/agents 模板、remote_* / closest / self（2025 AI-era）、全部 deprecated 面（checkout、discount、img_url 族——**若目標含 2022 前舊主題，img_url/img_tag 應提前到 T1**）、hash/base64 filters、Scripts（已落日，免實作）。

### 6.5 工程備註

- 以 `git clone https://github.com/Shopify/theme-liquid-docs`（MIT）取得 `data/objects.json`（138 objects 全屬性+型別+deprecation）、`data/filters.json`、`data/tags.json`、`schemas/theme/*.json`（section/block/setting 的 JSON Schema 可直接用於 schema 驗證器）、`data/shopify_system_translations.json`（shopify.* 系統翻譯鍵）——即本清單的機器可讀版，可自動生成 drop 骨架與相容性測試。
- 另需平台 HTTP 面配套：Cart AJAX API（routes.cart_add_url 等 `/cart/*.js`）、Section Rendering API（`?section_id=` / `?sections=`）、localization/currency 表單端點——Dawn/Horizon 的 JS 硬依賴。

來源：同上各節。