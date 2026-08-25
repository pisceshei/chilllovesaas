# frozen_string_literal: true

module Types
  # 外嵌影片（第 37 包；YouTube／Vimeo）。
  #
  # ①這是什麼：`Media` 底下與 `image` 平行的一個欄位——媒體是外嵌影片時才有值。
  #
  # ②🔴 **`embedUrl` 與 `originUrl` 都是導出的，不落庫**（limits
  #   `external_video_embed_url_templates` 的紅字）：隱私決策（youtube-nocookie、
  #   Vimeo `dnt=1`）會變，落庫等於改設定之後舊資料還停在舊網域，要跑 data migration
  #   才救得回來。導出＝翻一個 limits 鍵全店立刻生效。
  #
  # ③🔴 **不宣告 `presentation`**：那個欄位只存在於 **Storefront** API，Admin 沒有
  #   （取證 2026-08-25）。抄過來就是憑空多一個本尊 Admin 沒有的欄位。
  #   **不宣告 `aspectRatio`**：Admin 與 Storefront 都沒有，只有 Liquid 有；前台需要
  #   時由 `width`／`height` 在 drop 層算（第 30 包）。
  #   **不宣告 `preview`**：官方有，但它的 `status` enum 值域本輪只確認到 `READY`
  #   一個值（未取得 U9）；宣告一個恆 null 又沒有 enum 可用的半成品沒有意義，
  #   而 GraphQL **新增欄位不是 breaking change**，B 面（oEmbed 縮圖）再補即可。
  #
  # ④跨功能影響：第 30／33 包的 Liquid `external_video` drop 直接吃這裡的
  #   `host`／`externalId`；`MediaCard` 用 `host` 決定 badge。
  class ExternalVideoType < Types::BaseObject
    graphql_name "ExternalVideo"
    description "外嵌的第三方影片（YouTube／Vimeo）。"

    field :id, ID, null: false,
      description: "gid://chilllove/Media/{id}（不另立 GID 型別——資料主體就是那一列 media）。"
    field :host, Types::MediaHostEnum, null: false, description: "影片平台。"
    # 🔴 `externalId` 是 **ours**：Admin 與 Storefront 都沒有這個欄位，但 Liquid 的
    #   `external_video.external_id` 有（型別 string）。曝露它是因為前台 drop 需要，
    #   admin 也要顯示。**型別是 String 不是 ID**——Liquid 官方型別逐字是 string，
    #   且 YouTube 的 ID 本來就不是數字。
    field :external_id, String, null: false, description: "平台的影片 ID（ours；Liquid drop 需要）。"
    field :embed_url, String, null: false, description: "可放進 iframe 的 URL（導出，不落庫）。"
    field :origin_url, String, null: false, description: "影片在平台上的頁面 URL。"
    field :alt, String, null: true, description: "替代文字。"

    def id = "gid://chilllove/Media/#{object.id}"
    def host = object.external_host
    def external_id = object.external_id
    def origin_url = Catalog::ExternalVideoUrl.origin_url(object.external_host, object.external_id)
    def embed_url = Catalog::ExternalVideoUrl.embed_url(object.external_host, object.external_id)
    # D48 的窄縫：外嵌影片沒有檔案，媒體列就是 alt 的唯一落點（見 `MediaType#alt`）。
    def alt = object.alt_text
  end
end
