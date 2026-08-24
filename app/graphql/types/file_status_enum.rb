# frozen_string_literal: true

module Types
  # 檔案處理四態（正典＝limits `media.statuses`；第 24 包 CI enum 對照釘住）。
  class FileStatusEnum < GraphQL::Schema::Enum
    graphql_name "FileStatus"
    description "檔案處理狀態（UPLOADED→PROCESSING→READY／FAILED）。"

    Limits.enum(:media, :statuses).each do |status|
      value status.to_s, value: status.to_s.downcase
    end
  end
end
