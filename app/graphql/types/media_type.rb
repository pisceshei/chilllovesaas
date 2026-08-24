# frozen_string_literal: true

module Types
  # 商品媒體的一列（第 27 包）——position 即展示序，第一格＝精選圖。
  #
  # 🔴 `alt` 讀 `media.alt_text` 不是 `files.alt_text`：同一檔案掛不同商品可有不同
  #   alt（第 26 包 ImageType 檔頭已載明；62 §F.1 的度量對象也是 media）。
  class MediaType < Types::BaseObject
    graphql_name "Media"
    description "商品的一個媒體項。"

    field :id, ID, null: false
    field :position, Integer, null: false, description: "展示序（1-based；1＝精選圖）。"
    field :alt, String, null: true, method: :alt_text
    field :media_content_type, Types::MediaContentTypeEnum, null: false, method: :media_type
    field :status, Types::FileStatusEnum, null: false
    field :image, Types::ImageType, null: true,
      description: "檔案本體與衍生尺寸；處理未完成時衍生 URL 為 null。"
    field :product_variant_id, ID, null: true, description: "掛在哪個變體（官方每變體 1 張）。"

    def id = "gid://chilllove/Media/#{object.id}"

    # 🔴 狀態的真相在 `files.status`（審查 C2）：`media.status` 是建立當下的快照，
    #    管線把檔案轉 ready 時不回頭改媒體列——讀它會讓卡片永遠停在「處理中」。
    def status = object.stored_file&.status || object.status

    def product_variant_id
      object.product_variant_id && "gid://chilllove/ProductVariant/#{object.product_variant_id}"
    end

    def image
      return nil unless object.stored_file

      Types::ImageType::Presenter.new(file: object.stored_file, alt: object.alt_text)
    end
  end
end
