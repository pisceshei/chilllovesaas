# frozen_string_literal: true

# 路徑級重導（第 6 包；62 §B.5）。
#
# 🔴 `handle_change` 來源的列是**無 locale 前綴的正規路徑**（62 §F.3）：
#   路由層剝前綴查表、命中後把前綴加回去再 301。
#   ⚠️ 這是**該寫入者的屬性、不是表級不變量**：62 §B.5 允許帶前綴的列
#   （manual／import），語義由第 36 包裁定（審查 DOC-5）。
# 🔴 本表同時是 handle 唯一性的一部分（舊 handle 永不回收）——判準入口＝
#   `Catalog::HandleChange.path_reserved?`，不要在別處自寫查詢。
class UrlRedirect < ApplicationRecord
  acts_as_tenant :shop

  validates :from_path, :to_path, presence: true,
    length: { maximum: Limits.fetch(:seo, :redirect_path_max_chars) },
    format: { with: %r{\A/}, message: "must start with /" }
  validates :source, inclusion: { in: Limits.enum(:seo, :redirect_sources).map(&:downcase) }
  validates :status_code, inclusion: { in: Limits.fetch(:seo, :redirect_status_codes) }
  # from == to 的列＝自我迴圈；鏈坍縮的不變量（見 HandleChange）保證寫入端
  # 不會產生，這裡是第二道。
  validate :no_self_loop

  private

  def no_self_loop
    errors.add(:to_path, "must differ from from_path") if from_path.present? && from_path == to_path
  end
end
