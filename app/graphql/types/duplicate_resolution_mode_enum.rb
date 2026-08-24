# frozen_string_literal: true

module Types
  # 撞名解法（官方三值照搬：FileCreateInputDuplicateResolutionMode，取證 2026-08-24；
  # 正典＝limits `media.duplicate_resolution_modes`）。
  class DuplicateResolutionModeEnum < GraphQL::Schema::Enum
    graphql_name "FileCreateInputDuplicateResolutionMode"
    description "檔名已存在時的處理方式。"

    Limits.enum(:media, :duplicate_resolution_modes).each do |mode|
      value mode.to_s, value: mode.to_s.downcase
    end
  end
end
