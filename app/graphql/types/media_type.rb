# frozen_string_literal: true

module Types
  # 商品媒體的一列（第 27 包）——position 即展示序，第一格＝精選圖。
  #
  # 🔴 `alt` 讀 **`files.alt_text`** 不是本列的 `alt_text`（D48，2026-08-25 使用者裁定
  #   「所有的都跟 Shopify」）：本尊一張圖只有一份說明。
  #   ⚠️ 本檔頭原文寫的是相反的事（「同一檔案掛不同商品可有不同 alt」），
  #   那是第 26／27 包的裁定，D48 已推翻；`media.alt_text` 欄保留但停用。
  class MediaType < Types::BaseObject
    graphql_name "Media"
    description "商品的一個媒體項。"

    field :id, ID, null: false
    field :position, Integer, null: false, description: "展示序（1-based；1＝精選圖）。"
    # 🔴 D48：alt 讀**檔案**不讀本列。`media.alt_text` 欄仍在（遷移的落選值留著可救）
    #    但已停用——讀它會讓「在檔案庫改了 alt、商品頁沒變」重現，
    #    那正是本尊沒有、而我方一度有的行為。
    field :alt, String, null: true
    field :media_content_type, Types::MediaContentTypeEnum, null: false, method: :media_type
    field :status, Types::FileStatusEnum, null: false
    field :image, Types::ImageType, null: true,
      description: "檔案本體與衍生尺寸；處理未完成時衍生 URL 為 null。"
    field :product_variant_id, ID, null: true, description: "掛在哪個變體（官方每變體 1 張）。"

    def id = "gid://chilllove/Media/#{object.id}"

    # D48：權威在檔案。沒有檔案的 M0 遺留列回 nil（不回落 `media.alt_text`
    # ——那正是停用的那一欄，回落等於讓舊語義從後門活著）。
    def alt = object.stored_file&.alt_text

    # 🔴 狀態的真相在 `files.status`（審查 C2）：`media.status` 是建立當下的快照，
    #    管線把檔案轉 ready 時不回頭改媒體列——讀它會讓卡片永遠停在「處理中」。
    def status = object.stored_file&.status || object.status

    def product_variant_id
      object.product_variant_id && "gid://chilllove/ProductVariant/#{object.product_variant_id}"
    end

    def image
      return nil unless object.stored_file

      Types::ImageType::Presenter.new(file: object.stored_file)
    end
  end
end
