# frozen_string_literal: true

module Types
  # 一張圖的讀取面（第 26 包）——原圖 URL＋四個衍生尺寸的 URL 與實際像素。
  #
  # 🔴 衍生尺寸尚未產出（status 非 ready）時，`thumbUrl` 等一律 **null**：
  #   前端據此顯示占位／處理中，不得拿原圖冒充縮圖（20MB 原圖當縮圖＝列表爆掉）。
  # 🔴 **alt 的權威在 `files.alt_text`，全店一份**（D48，2026-08-25 使用者裁定
  #   「所有的都跟 Shopify」）。本尊的 `MediaImage` 同時 implements `File` 與 `Media`
  #   但**只曝露一個 `alt`** ⇒ 一張圖只有一份說明，在檔案庫改了處處跟著改。
  #   ⚠️ 第 26／27 包曾裁定 alt 在 `media` 那一列（同檔掛不同商品可各有 alt），
  #   D48 已推翻；`media.alt_text` 欄保留但**停用**（不刪欄＝schema drift 最小，
  #   同 B4 先例），任何新讀寫端一律走 file。
  # 🔴 `Presenter` 因此**只帶 file**：alt 不再是建構參數，而是從 file 導出。
  #   這是刻意讓「傳入某個 media 的 alt」在型別上不可表達——遷移期最容易的錯法
  #   就是有人照舊 `Presenter.new(file:, alt: row.alt_text)`，少一個參數它就編不過。
  class ImageType < Types::BaseObject
    graphql_name "Image"
    description "圖片與其衍生尺寸。"

    field :id, ID, null: false, description: "檔案 GID。"
    field :url, String, null: false, description: "原圖讀出端點。"
    field :alt, String, null: true, description: "檔案層 alt（全店一份；D48）。"
    field :status, Types::FileStatusEnum, null: false
    field :width, Integer, null: true, description: "原圖寬（處理後才有值）。"
    field :height, Integer, null: true

    field :thumb_url, String, null: true, description: "160px 衍生（列表縮圖）。"
    field :card_url, String, null: true, description: "533px 衍生（卡片）。"
    field :detail_url, String, null: true, description: "1200px 衍生（詳情頁）。"
    field :og_url, String, null: true, description: "1200×630 裁切（Open Graph）。"

    # 呈現物件：只包檔案本體（alt 由它導出，見檔頭）。
    Presenter = Data.define(:file) do
      def id = file.id
      def status = file.status
      def width = file.width
      def height = file.height
      def alt = file.alt_text
    end

    def id = "gid://chilllove/File/#{object.id}"

    def url = "/admin/files/#{object.id}/blob"

    def thumb_url = object.file.derivative_url("thumb")

    def card_url = object.file.derivative_url("card")

    def detail_url = object.file.derivative_url("detail")

    def og_url = object.file.derivative_url("og")
  end
end
