# frozen_string_literal: true

module Types
  # 檔案（表 files／model StoredFile——類名避開 Ruby core `File`，對外仍是 `File`）。
  #
  # 🔴 **本 type 是檔案庫的讀取面，`Image` 是商品媒體的讀取面**——兩者都掛在同一張
  #   `files` 列上，而 D48（2026-08-25 使用者裁定）之後**兩邊的 `alt` 是同一個值**：
  #   權威在 `files.alt_text`、全店一份，改哪一邊都一樣。
  #   ⚠️ 曾經不是這樣：第 26／27 包裁定 alt 在 `media` 那一列（同檔掛不同商品可各有
  #   alt），本檔頭原本明文「改這裡不會回頭改既有 media 的 alt」——那句已隨 D48 作廢。
  class FileType < Types::BaseObject
    graphql_name "File"
    description "檔案庫的一個檔案。"

    implements Types::Interfaces::Node

    field :id, ID, null: false, description: "GID（gid://chilllove/File/{id}）。"
    field :filename, String, null: false
    field :content_type, String, null: false
    field :byte_size, GraphQL::Types::BigInt, null: false
    field :status, FileStatusEnum, null: false
    field :alt, String, null: true, method: :alt_text,
                        description: "alt 說明（全店一份；改它會影響所有用到本檔的商品）。"
    field :url, String, null: false, description: "檔案讀出端點（admin 認證後可取）。"
    field :created_at, GraphQL::Types::ISO8601DateTime, null: false

    # ── 第 28 包檔案庫新增 ──
    field :width, Integer, null: true, description: "原圖寬（處理完才有值）。"
    field :height, Integer, null: true
    field :thumb_url, String, null: true,
                              description: "160px 衍生（列表縮圖）；未產出時 null，不得拿原圖冒充。"
    field :preview_url, String, null: true, description: "533px 衍生（預覽）。"
    field :usage_count, Integer, null: false,
                                 description: "被幾個商品媒體引用（file_usages 計數；刪除確認的數字來源）。"
    field :processing_error, String, null: true, description: "處理失敗的原因（status=FAILED 時有值）。"

    def id = "gid://chilllove/File/#{object.id}"

    def url = "/admin/files/#{object.id}/blob"

    def thumb_url = object.derivative_url("thumb")

    def preview_url = object.derivative_url("card")

    # 🔴 走 `usage_count_loaded` 而不是 model 的 `usage_count`（＝一次 COUNT）：
    #   列表 50 列就是 50 條查詢（同第 26 包 featuredImage 的 N+1 前例）。
    #   `files` query 已用一次 GROUP BY 把計數 preload 進來；單筆路徑（fileCreate 回傳、
    #   node(id:)）沒有 preload，回落 model 方法。
    def usage_count = object.usage_count_loaded || object.usage_count
  end
end
