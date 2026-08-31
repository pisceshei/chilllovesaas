# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL 的 mutation root。
  #
  # 🔴 **本型別自 2026-08-23 起掛上 `ChillloveSchema`**——解鎖條件
  # 「第一支真正的 mutation 落地時，同批處理 claim/replay」已由本批滿足：
  # `Mutations::ProductSet` ＋ `Idempotency::Guard`（11 §2.1 狀態機）＋
  # `idempotency_keys` 表形對齊遷移，三者同一個 PR 交付。
  #
  # 歷史（保留給讀 blame 的人）：掛載前它刻意空置且不掛 schema，因為
  # `enforce_idempotency_contract!` 只檢查 key 有沒有帶、不做去重——
  # 掛一個沒有 claim/replay 的 mutation root 會給下一位作者**虛假的安全感**。
  # 那個保護消失的條件就是本次交付的內容；guard spec
  # （spec/graphql/mutation_root_guard_spec.rb）已同批反轉成掛載後的斷言。
  #
  # 🔴 新增 mutation 的義務（① 有 CI 擋；②③ 靠 review——尚無機械斷言，誠實標示）：
  #   ① `resolve` 開頭呼叫 `enforce_idempotency_contract!`（graphql-ruby 無
  #      around hook，忘了呼叫沒有 runtime 機制會發現——由
  #      `spec/graphql/mutation_idempotency_call_spec.rb` 靜態掃描兜底）；
  #   ② 建立型 mutation 進 `limits.idempotency` 對應清單（判準：重放會不會
  #      憑空多出實體或一筆錢）；
  #   ③ 專屬 error code enum ＋ error object type（鐵律 4：code 一律有值）。
  #
  # @see docs/research/28-api-contract.md §0.3.3
  # @see docs/dev/m1-product-set-foundation.md
  class MutationType < BaseObject
    graphql_name "Mutation"
    description "Admin API 的寫入入口。"

    field :staged_uploads_create, mutation: Mutations::StagedUploadsCreate,
      description: "為一批待上傳檔案簽發 staged 上傳目標（12 §D.7 第 1 步）。"
    field :file_create, mutation: Mutations::FileCreate,
      description: "以 originalSource 建立檔案（12 §D.7 第 3 步）。"
    field :file_update, mutation: Mutations::FileUpdate,
      description: "更新檔案層 alt／檔名（第 28 包檔案庫）。"
    field :file_delete, mutation: Mutations::FileDelete,
      description: "刪除檔案，連帶解除商品引用並補位（第 28 包）。"
    field :product_create_media, mutation: Mutations::ProductCreateMedia,
      description: "把媒體掛到商品上（第 27 包）。"
    field :product_update_media, mutation: Mutations::ProductUpdateMedia,
      description: "更新商品媒體的 alt。"
    field :product_delete_media, mutation: Mutations::ProductDeleteMedia,
      description: "從商品移除媒體。"
    field :product_reorder_media, mutation: Mutations::ProductReorderMedia,
      description: "重排商品媒體（宣告式全量）。"
    field :product_variant_append_media, mutation: Mutations::ProductVariantAppendMedia,
      description: "把一張圖掛到變體上。"
    field :product_set, mutation: Mutations::ProductSet,
      description: "商品全樹宣告式 upsert（admin 商品頁 SaveBar 的唯一寫入映射，63 §B.4）。"
    field :staff_locale_update, mutation: Mutations::StaffLocaleUpdate,
      description: "更新目前員工的 admin 介面語言（67 §E.1；ML-1）。"
    field :inventory_adjust_quantities, mutation: Mutations::InventoryAdjustQuantities,
      description: "以差額調整庫存（唯一入口 Inventory::Adjust；idempotencyKey 必填＝G28）。"
    field :inventory_set_quantities, mutation: Mutations::InventorySetQuantities,
      description: "以絕對值＋CAS 設定庫存（同一唯一入口的 set 模式）。"
    field :collection_set, mutation: Mutations::CollectionSet,
      description: "商品系列全樹宣告式 upsert（ML-3；與 productSet 對稱）。"
    # ML-4：語言集合是**資料**——這三支只動 shop_locales 的列，不建表、不 migration。
    field :shop_locale_enable, mutation: Mutations::ShopLocaleEnable,
      description: "為本店啟用一個內容語言（67 §A.2）。"
    field :shop_locale_update, mutation: Mutations::ShopLocaleUpdate,
      description: "更新已啟用語言的發布狀態與排序。"
    field :shop_locale_disable, mutation: Mutations::ShopLocaleDisable,
      description: "停用一個內容語言（保留譯文）。"
    # 包 36：路徑級重導管理（62 §B.5；301 引擎的後台面）。
    field :url_redirect_create, mutation: Mutations::UrlRedirectCreate,
      description: "建立自訂 301 重導（無 locale 前綴正規形）。"
    field :url_redirect_delete, mutation: Mutations::UrlRedirectDelete,
      description: "刪除一筆重導（刪除＝釋放舊 handle，HDL-8）。"
    field :url_redirect_update, mutation: Mutations::UrlRedirectUpdate,
      description: "更新自訂重導（系統產生列不可改）。"
    # G6-3 前半：PSP provider 憑證層（祕密 write-only、payload 只回指紋——37 §6.3）。
    field :order_mark_as_paid, mutation: Mutations::OrderMarkAsPaid,
      description: "把待付款訂單標記為已付款（G6-6 步 4；manual 收款確認）。"

    # G6-8（步 5）：履約與退款線。fulfillmentCreate 是本尊現行命名
    # （fulfillmentCreateV2 官方標 Deprecated）；refundCreate 官方 2026-04 起強制冪等鍵。
    field :fulfillment_create, mutation: Mutations::FulfillmentCreate,
      description: "建立出貨（行項＋追蹤資訊；出貨釋放庫存承諾）。"
    field :fulfillment_tracking_info_update, mutation: Mutations::FulfillmentTrackingInfoUpdate,
      description: "更新出貨追蹤資訊（整組取代）。"
    field :fulfillment_cancel, mutation: Mutations::FulfillmentCancel,
      description: "取消出貨（品項回到可出貨、庫存承諾回加）。"
    field :refund_create, mutation: Mutations::RefundCreate,
      description: "建立退款（軟上限條件式 UPDATE＋restock；idempotencyKey 必帶）。"
    field :shop_payment_provider_set, mutation: Mutations::ShopPaymentProviderSet,
      description: "宣告式寫入 PSP provider 的憑證與偏好。"

    # G6-3（步 2）：付款設定本體（86 §2/§3——capture modal／manual methods／activation）。
    field :payment_capture_method_update, mutation: Mutations::PaymentCaptureMethodUpdate,
      description: "更新請款模式（三值 modal 對位；Plus 專屬值誠實拒絕）。"
    field :shop_payment_method_create, mutation: Mutations::ShopPaymentMethodCreate,
      description: "建立 manual 付款方式。"
    field :shop_payment_method_update, mutation: Mutations::ShopPaymentMethodUpdate,
      description: "更新 manual 付款方式文案。"
    field :shop_payment_method_activate, mutation: Mutations::ShopPaymentMethodActivate,
      description: "啟用 manual 付款方式。"
    field :shop_payment_method_deactivate, mutation: Mutations::ShopPaymentMethodDeactivate,
      description: "停用 manual 付款方式（設定保留）。"
    field :shop_payment_provider_activate, mutation: Mutations::ShopPaymentProviderActivate,
      description: "啟用 PSP provider（前置＝憑證已設定）。"
    field :shop_payment_provider_deactivate, mutation: Mutations::ShopPaymentProviderDeactivate,
      description: "停用 PSP provider（憑證保留）。"
    field :shop_payment_provider_sync_capabilities, mutation: Mutations::ShopPaymentProviderSyncCapabilities,
      description: "重新讀取 PSP 帳號已開通的付款方式（G6-1b；首次成功自動啟用可用方式）。"
    # S1：publication 生命週期。🔴 `publicationUpdate` 是本倉庫**第一條**
    #   `resource_publications` 的非建立寫入路徑（在它之前發布列只在建立時被寫入）。
    field :publication_create, mutation: Mutations::PublicationCreate,
      description: "建立一個 publication（銷售管道的發布容器）。"
    # 包 30（D77）：主題發布（本尊 themePublish 對位）。
    field :theme_publish, mutation: Mutations::ThemePublish,
      description: "發布主題（現任已發布者自動降回草稿）。"

    field :publication_update, mutation: Mutations::PublicationUpdate,
      description: "更新 publication：autoPublish 與批次加／減 publishable（🔴 累加語義，非宣告式全量）。"
    field :publication_delete, mutation: Mutations::PublicationDelete,
      description: "刪除一個 publication（綁著管道的不可刪）。"

    # S5：逐資源的發布寫入面。🔴 **這兩支才是 `resource_publications.published_at` 的
    #   第一條 UPDATE 路徑**——S1 的 `publicationUpdate` 走 create-only 區塊，
    #   結構上改不到既有列，所以設排程／改期／取消排程在 S5 之前無路可達。
    # 🔴 **排程只能經 `publishablePublish` 進入系統**：`PublicationUpdateInput`
    #   官方恰三欄且沒有 `publishDate`（取證 2026-08-27）。這是本尊的功能邊界。
    field :publishable_publish, mutation: Mutations::PublishablePublish,
      description: "把一個資源發布到一或多個銷售管道（未來時間＝排程發布）。"
    field :publishable_unpublish, mutation: Mutations::PublishableUnpublish,
      description: "把一個資源自一或多個銷售管道取消發布（🔴 其中的 publishDate 一律無效果）。"
  end
end
