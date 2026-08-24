# frozen_string_literal: true

module Types
  # 一張圖的讀取面（第 26 包）——原圖 URL＋四個衍生尺寸的 URL 與實際像素。
  #
  # 🔴 衍生尺寸尚未產出（status 非 ready）時，`thumbUrl` 等一律 **null**：
  #   前端據此顯示占位／處理中，不得拿原圖冒充縮圖（20MB 原圖當縮圖＝列表爆掉）。
  # 🔴 **alt 的權威在 `media` 那一列不在 `files`**：同一個檔案掛在不同商品可以有
  #   不同 alt（62 §F.1 的度量對象也是 media）。因此本 type 的 object 是
  #   `Presenter`（file ＋ 該媒體列的 alt），不是裸 StoredFile。
  class ImageType < Types::BaseObject
    graphql_name "Image"
    description "圖片與其衍生尺寸。"

    field :id, ID, null: false, description: "檔案 GID。"
    field :url, String, null: false, description: "原圖讀出端點。"
    field :alt, String, null: true, description: "該媒體列的 alt（不是檔案層的）。"
    field :status, Types::FileStatusEnum, null: false
    field :width, Integer, null: true, description: "原圖寬（處理後才有值）。"
    field :height, Integer, null: true

    field :thumb_url, String, null: true, description: "160px 衍生（列表縮圖）。"
    field :card_url, String, null: true, description: "533px 衍生（卡片）。"
    field :detail_url, String, null: true, description: "1200px 衍生（詳情頁）。"
    field :og_url, String, null: true, description: "1200×630 裁切（Open Graph）。"

    # 呈現物件：檔案本體＋該媒體列的 alt。
    Presenter = Data.define(:file, :alt) do
      def id = file.id
      def status = file.status
      def width = file.width
      def height = file.height
    end

    def id = "gid://chilllove/File/#{object.id}"

    def url = "/admin/files/#{object.id}/blob"

    def thumb_url = object.file.derivative_url("thumb")

    def card_url = object.file.derivative_url("card")

    def detail_url = object.file.derivative_url("detail")

    def og_url = object.file.derivative_url("og")
  end
end
