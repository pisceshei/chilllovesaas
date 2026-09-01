# frozen_string_literal: true

module Types
  # 主題（包 30／D77）。本尊對位＝`OnlineStoreTheme`；v1 只曝露清單頁需要的欄。
  class ThemeType < BaseObject
    graphql_name "Theme"
    description "主題庫項目（清單頁子集；本尊 OnlineStoreTheme 的對位）。"

    field :id, ID, null: false
    field :license_attested, Boolean, null: false, description: "匯入時的授權聲明（鐵律 9 gate）。"
    field :name, String, null: false
    field :role, String, null: false, description: "draft／published（published_slot 唯一索引保證同店至多一個 published）。"
    field :source, String, null: false, description: "first_party／licensed／import。"
    field :version, String, null: true
    field :published_at, GraphQL::Types::ISO8601DateTime, null: true
    field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    field :preview_url, String, null: false, description: "登入後預覽入口（noindex；admin session 內有效）。"
    # 步 15b（99 §1）：filenames 萬用字元過濾（官方 "At most 50 filenames…Use '*'
    # to match zero or more characters."）＋first 上限。
    field :files, [ ThemeFileType ], null: false do
      argument :filenames, [ String ], required: false
      argument :first, Integer, required: false
    end
    field :import_report, GraphQL::Types::JSON, null: true,
      description: "最近一次匯入的相容掃描報告（非匯入主題為 null）。"

    def id = "gid://chilllove/Theme/#{object.id}"
    def preview_url = "/admin/store/preview/#{object.id}"

    def files(filenames: nil, first: nil)
      source = ThemeEngine::Sources.resolve(object)
      return [] if source.nil?

      rels = source.list
      if filenames.present?
        patterns = filenames.first(50) # 官方上限
        rels = rels.select { |rel| patterns.any? { |pattern| File.fnmatch?(pattern, rel) } }
      end
      rels = rels.first([ first || 250, 2500 ].min) # 官方 "At most 2500"
      rels.map { |rel| { filename: rel, size: source.size_of(rel).to_i } }
    end

    def import_report
      report = ThemeImportReport.where(shop_id: object.shop_id, theme_id: object.id)
                                .order(:id).last
      report&.report
    end
  end
end
