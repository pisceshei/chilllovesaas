# frozen_string_literal: true

module Types
  # 主題檔案清單項（步 15b；本尊 OnlineStoreThemeFile 的 v1 子集——filename/size；
  # body 三形 union 隨步 16 編輯器讀取面，99 §1）。
  class ThemeFileType < BaseObject
    graphql_name "ThemeFile"
    description "主題檔案（清單子集）。"

    field :body, String, null: true,
      description: "文字內容（UTF-8 可解者；binary ⇒ null——官方 body 三形 union 的 Text 面）。"
    field :filename, String, null: false
    field :size, Integer, null: false, description: "bytes。"

    def body
      raw = object[:source]&.read(object[:filename])
      return nil if raw.nil?

      text = raw.dup.force_encoding("UTF-8")
      text.valid_encoding? ? text : nil
    end
  end
end
