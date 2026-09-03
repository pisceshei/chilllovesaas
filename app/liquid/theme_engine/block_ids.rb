# frozen_string_literal: true

require "digest"

module ThemeEngine
  # block 實例 id（渲染 1:1，2026-09-03）。
  #
  # ①這是什麼：本尊 storefront 對 JSON 定義的每個 block 實例輸出 `{18 碼}__{key}` 形的 `block.id`
  #   （hoko.vip 首頁 170 處、105 個相異前綴：`group-block--AWlFwNUZ5UVVuRmp6e__group_announcement_bar_PeTpTw`、
  #   `shopify-block-A…__slide_3UKqHy`、靜態 block `Slider-A…__static-collection-list`；同一 block 在頁內各處前綴一致，
  #   同一 key 出現在兩個 section 時前綴不同 ⇒ 前綴＝f(section 實例, block 路徑)。首字恆 `A`，其後 17 碼 `[A-Za-z0-9]`）。
  #   本尊演算法**未取得**（不可觀測），我方以 SHA-256 導出同形、同穩定性的值：形同、值為 ours（登記）。
  # ②怎麼做：seed＝`{section 完整 id}/{block key 路徑}`；base64 去掉 `+/=` 後取 17 碼，前綴 `A`。
  # ③跨功能：`BlockDrop#id`（Liquid `block.id`）、`Runtime#block_wrapper`（`shopify-block-{id}`）；
  #   `data-shopify-editor-block` 與編輯器橋仍用**裸 key**（`BlockDrop#key`；`cl:*` 契約以 key 定址）。
  module BlockIds
    module_function

    # @param section_id [String, nil] section 完整 id（`template--index__hero`／`sections--header-group__x`／靜態名）
    # @param path [Array<String>] 自 section 根算起的 block key 路徑
    # @return [String] `A` + 17 碼 `[A-Za-z0-9]`
    def prefix(section_id, path)
      digest = Digest::SHA256.digest("#{section_id}/#{Array(path).join('/')}")
      "A#{[ digest ].pack('m0').tr('+/=', '')[0, 17]}"
    end

    # @return [String] `{prefix}__{key}`
    def instance_id(section_id, path)
      keys = Array(path)
      "#{prefix(section_id, keys)}__#{keys.last}"
    end
  end
end
