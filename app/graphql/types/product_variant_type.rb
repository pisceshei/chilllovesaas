# frozen_string_literal: true

module Types
  # 商品變體（admin 編輯頁讀取面；v1＝隱含變體，具名選項屬變體包）。
  #
  # 🔴 金額欄位一律 **R4 十進位字串**出向（65 §B X2：cents/100 恆兩位小數）——
  # 走 `Money::Storage#to_decimal`，不得在 GraphQL 層手算除法。
  class ProductVariantType < BaseObject
    include Types::InventoryAuthorization

    graphql_name "ProductVariant"
    description "商品變體。"

    field :id, ID, null: false, description: "gid://chilllove/ProductVariant/{id}"
    field :legacy_resource_id, ID, null: false
    field :title, String, null: false,
      description: "變體標題；隱含變體恆為 Default Title（Liquid 硬相容契約）。"
    field :price, String, null: false, description: "售價（主單位十進位字串，恆兩位小數）。"
    field :compare_at_price, String, null: true, description: "原價（劃線價），格式同 price。"
    field :cost, String, null: true, description: "每品項成本，格式同 price；不對顧客顯示。"
    field :sku, String, null: true
    field :barcode, String, null: true
    field :taxable, Boolean, null: false
    field :position, Integer, null: false
    # 第 21 包：本尊 SelectedOption 形（name/value 扁平對；隱含變體＝空陣列）。
    field :selected_options, [ Types::SelectedOptionType ], null: false,
      description: "選中的選項（選項 position 序；隱含變體為空）。"

    # ── 第 29 包（變體子頁）新增 ──
    # 運送兩欄。🔴 `weight` 出向是**公克整數**不是浮點公斤：重量與金額同紀律
    #   ——內部整數、顯示層才換算單位。前端拿 grams 自己按 locale 顯示 kg／lb，
    #   伺服端不做單位轉換（換算基數屬 jurisdiction pack，鐵律 11）。
    field :weight_grams, Integer, null: false, description: "商品重量（公克；顯示單位由前端決定）。"
    field :requires_shipping, Boolean, null: false, description: "是否為需運送的實體商品。"
    # 變體圖（`media.product_variant_id`；上限 limits product.max_images_per_variant＝1）。
    field :image, Types::ImageType, null: true, description: "變體專屬圖片；未掛則為 null。"
    # 🔴 **全地點一次回**（不是 `inventoryItems` 的單地點視角）——見
    #   `VariantInventoryLevelType` 檔頭。呼叫端必須 preload，否則每個變體一條查詢。
    field :inventory_levels, [ Types::VariantInventoryLevelType ], null: false,
      description: "各地點的庫存數量（地點 priority 序）。"

    # @return [String] GID
    def id
      "gid://chilllove/ProductVariant/#{object.id}"
    end

    # @return [String] 十進位主鍵字串
    def legacy_resource_id
      object.id.to_s
    end

    # @return [String] R4 字串
    def price
      Money::Storage.from_cents(object.price_cents, object.currency).to_decimal.string
    end

    # @return [String, nil]
    def compare_at_price
      cents = object.compare_at_price_cents
      cents && Money::Storage.from_cents(cents, object.currency).to_decimal.string
    end

    # @return [String, nil]
    def cost
      cents = object.cost_cents
      cents && Money::Storage.from_cents(cents, object.currency).to_decimal.string
    end

    # @return [Integer] 公克
    def weight_grams = object.weight_grams.to_i

    # @return [Types::ImageType::Presenter, nil]
    #   alt 由 `Presenter` 從檔案導出（D48：權威在 `files.alt_text`、全店一份）。
    #   ⚠️ 本方法原本傳 `alt: row.alt_text` 兩個參數——那是第 26／27 包 per-product
    #   裁定的寫法，D48 推翻後 `Presenter` 收成單成員，這裡**會直接 ArgumentError**。
    #   那正是把它做成型別守衛的用意：不是靜默讀舊值，是當場炸。
    def image
      row = object.media.find { |m| m.media_type == "image" }
      return nil if row.nil? || row.stored_file.nil?

      Types::ImageType::Presenter.new(file: row.stored_file)
    end

    # @return [Array<InventoryLevel>] 地點 priority 序
    #   關聯由呼叫端 preload（`ProductType#variants` 的 includes）。
    # 🔴 **自己擋 `inventory.view`**（審查 R-1）：本欄長在 `product(id:)` 底下，
    #   而那條路徑只跑 `authorize_products!` ⇒ 沒有這一行，只給了商品權限的員工
    #   就能讀到全地點庫存明細、地點名稱與可寫入的 `inventoryItemId`。
    #   D42 把兩個權限鍵分開，讀取面就必須逐處落實，不能靠父欄位的授權。
    def inventory_levels
      authorize_inventory!
      item = object.inventory_item
      return [] if item.nil?

      item.inventory_levels.sort_by { |level| [ level.location&.priority.to_i, level.location_id ] }
    end

    # @return [Array<Hash>] 座標展開為 {name:, value:}（依選項 position 排序）。
    #   關聯已由 ProductType#variants preload——這裡只走記憶體。
    def selected_options
      object.product_variant_option_values
            .sort_by { |pvov| pvov.product_option.position }
            .map { |pvov| { name: pvov.product_option.name, value: pvov.option_value.value } }
    end
  end
end
