# frozen_string_literal: true

# 上傳檔案 metadata（第 25 包；表＝`files`）。
#
# ①這是什麼：檔案庫的一列——filename／content_type／byte_size／checksum＋
#   `storage_key`（本體在物件儲存，B6＝自建 presigned POST，不用 Active Storage）。
#   🔴 類名取 StoredFile 因為 `File` 撞 Ruby core——GraphQL 面仍曝露為 `File`
#   （`Types::FileType.graphql_name`）、GID 仍是 `gid://chilllove/File/{id}`。
# ②狀態機：limits `media.statuses` 四態（uploaded→processing→ready／failed）；
#   本包 fileCreate 落 `ready`（圖片不需轉檔即可用；第 26 包管線接手後
#   進場改 uploaded→processing）。
# ③引用：`file_usages`（附掛端第 27 包寫入）；刪除確認與 in-use 擋刪讀它。
# ④跨功能影響：fileCreate／fileUpdate／fileDelete（25／28）、媒體卡（27）、
#   檔案庫頁（28）、`media.source_url` 衍生（27）。
class StoredFile < ApplicationRecord
  self.table_name = "files"

  # limits 是大寫 GraphQL 形（`Limits.enum` 契約）；DB 存小寫。
  STATUSES = Limits.enum(:media, :statuses).map { |v| v.to_s.downcase }.freeze

  acts_as_tenant :shop

  has_many :file_usages, foreign_key: :file_id, inverse_of: :stored_file, dependent: :restrict_with_error

  validates :filename, presence: true, length: { maximum: 255 }
  validates :content_type, presence: true
  validates :byte_size, presence: true, numericality: { greater_than: 0 }
  validates :checksum, presence: true
  validates :storage_key, presence: true, uniqueness: { scope: :shop_id }
  validates :status, inclusion: { in: STATUSES }
  validates :alt_text, length: { maximum: 512 }, allow_nil: true

  # 引用數（第 28 包刪除確認的數字來源；兩套計數＝事故，排程 §四.28）。
  def usage_count = file_usages.count
end
