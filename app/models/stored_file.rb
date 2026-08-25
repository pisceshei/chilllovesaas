# frozen_string_literal: true

# 上傳檔案 metadata（第 25 包；表＝`files`）。
#
# ①這是什麼：檔案庫的一列——filename／content_type／byte_size／checksum＋
#   `storage_key`（本體在物件儲存，B6＝自建 presigned POST，不用 Active Storage）。
#   🔴 類名取 StoredFile 因為 `File` 撞 Ruby core——GraphQL 面仍曝露為 `File`
#   （`Types::FileType.graphql_name`）、GID 仍是 `gid://chilllove/File/{id}`。
# ②狀態機：limits `media.statuses` 四態。fileCreate 落 `uploaded`（起點），
#   `media.uploaded` 事件的消費者（第 26 包 `MediaPipeline::ProcessConsumer`）
#   產完衍生尺寸才轉 `ready`；壞檔轉 `failed` 並記 `processing_error`。

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
  # 512 原本是硬編（鐵律 6 違反，與 Media 同型、第 37 包已修過那邊）——正典在
  # limits `media.alt_max_length`，`MediaSync::ALT_MAX` 也引同一鍵。
  validates :alt_text, length: { maximum: Limits.fetch(:media, :alt_max_length) }, allow_nil: true
  # 第 3 包：alt 來源稽核（62 §F.1；值域正典＝limits `media.alt_sources`）。
  validates :alt_source,
    inclusion: { in: Limits.enum(:media, :alt_sources).map(&:downcase) },
    allow_nil: true

  before_save :stamp_alt_source

  # 🔴 預設 `human` 是**兜底**不是權威：現行全部 alt 寫入路徑都是後台人工輸入，
  #   所以「有人改了 alt 而沒明說來源」＝human。未來的 AI 產生器與 CSV 匯入
  #   **必須顯式帶 alt_source**（本 callback 看到顯式值就不動）——若它們忘了帶，
  #   會被錯標成 human，這是已登記的殘餘風險（worklog Pending），代價換來的是
  #   「所有現行路徑零改動即正確」。
  def stamp_alt_source
    return unless will_save_change_to_alt_text?
    return if will_save_change_to_alt_source?

    self.alt_source = "human"
  end

  # 引用數的**相關子查詢**（第 28 包檔案庫列表）。
  #
  # 🔴 為什麼不是列表逐列呼叫 `usage_count`：那是每列一條 COUNT，50 列的檔案庫頁
  #   就是 50 條查詢（第 26 包 `featuredImage` 的 N+1 已經踩過一次）。列表路徑
  #   `.select(Arel.sql(StoredFile::USAGE_COUNT_SELECT))` 把計數併進同一條 SELECT。
  # 🔴 **這不是第二套計數**（排程 §四.28 的紅線）：算式與 `usage_count` 逐字同義
  #   ——都是「`file_usages` 裡 file_id 等於本列的列數」。兩者的一致性由
  #   `spec/models/stored_file_spec.rb` 的同源斷言釘住。
  USAGE_COUNT_SELECT = <<~SQL.squish.freeze
    (SELECT COUNT(*)
       FROM file_usages fu
      WHERE fu.shop_id = files.shop_id
        AND fu.file_id = files.id) AS usage_count_select
  SQL

  # 引用數（第 28 包刪除確認的數字來源；兩套計數＝事故，排程 §四.28）。
  def usage_count = file_usages.count

  # 列表路徑 preload 進來的計數；沒走 `USAGE_COUNT_SELECT` 時為 nil（呼叫端回落）。
  def usage_count_loaded
    return nil unless has_attribute?(:usage_count_select)

    self[:usage_count_select]&.to_i
  end

  # 衍生尺寸的讀出 URL（第 26 包；nil＝該尺寸尚未產出／處理失敗）。
  # 端點與原圖同一支（`/admin/files/:id/blob`）＋variant 參數——衍生檔不另開路由，
  # 授權面因此只有一處（StoredFilePolicy#index?）。
  def derivative_url(variant)
    return nil unless derivatives.is_a?(Hash) && derivatives[variant.to_s]

    "/admin/files/#{id}/blob?variant=#{variant}"
  end
end
