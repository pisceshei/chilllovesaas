# frozen_string_literal: true

module RuboCop
  module Cop
    module Chilllove
      # 庫存數量的唯一寫入入口是 `Inventory::Adjust`（13 §F5；D43：**不留豁免口**）。
      #
      # 本 cop 擋三種繞過形態（2026-08-24 對抗審查以 repro 證實初版有三個洞，本版關掉）：
      #   ① 建立 ledger 列——const receiver（`InventoryAdjustment.create!`）**與**
      #      association receiver（`group.inventory_adjustments.create!`）都算；
      #   ② 對 quantity 欄位的寫入——`update/update!/update_columns/update_column/
      #      update_all/increment!/decrement!/upsert/upsert_all` 帶七個 quantity 鍵任一者。
      #      🔴 **不做 receiver 判斷**：七個欄名（available/committed/reserved/damaged/
      #      safety_stock/quality_control/incoming）在 db/schema.rb 全庫唯一（2026-08-24
      #      逐欄 grep 確認各恰 1 次），變數叫什麼都逃不掉；日後若有別表新增同名欄，
      #      在這裡改回 receiver 判斷並記錄。
      #
      # 允許範圍由 .rubocop.yml 的 Exclude 定義（唯一 Exclude＝入口自己）；
      # spec/** 不在掃描範圍（fixture 直建資料是測試需要，cop 守生產代碼）。
      # 已知殘餘盲區：裸 SQL（execute）——由 STORED GENERATED 與 nightly 對帳補位，
      # 三道合起來才完整（docs/dev/m1-inventory-adjust.md §3）。
      class InventoryDirectWrite < Base
        MSG_LEDGER = "ledger 列只能由 Inventory::Adjust 建立（D43：唯一入口、無豁免口）。"
        MSG_QUANTITY = "庫存數量欄位只能經 Inventory::Adjust 變動（13 §F5）。"

        QUANTITY_KEYS = %i[available committed reserved damaged safety_stock quality_control incoming].freeze
        WRITE_METHODS = %i[update update! update_columns update_column update_all increment! decrement! upsert upsert_all assign_attributes toggle!].freeze
        # attribute writer（level.available = 5）——七個 setter 名同樣全庫唯一。
        WRITER_METHODS = QUANTITY_KEYS.map { |key| :"#{key}=" }.freeze
        CREATE_METHODS = %i[create create! new insert insert! insert_all insert_all! upsert upsert_all build find_or_create_by find_or_create_by!].freeze

        # @!method ledger_const_write?(node)
        def_node_matcher :ledger_const_write?, <<~PATTERN
          (send (const {nil? cbase} {:InventoryAdjustment :InventoryAdjustmentGroup}) {#{CREATE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        # @!method ledger_association_write?(node)
        def_node_matcher :ledger_association_write?, <<~PATTERN
          (send (send _ {:inventory_adjustments :inventory_adjustment_groups}) {#{CREATE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        # @!method level_create_with_quantity?(node)
        def_node_matcher :level_create_with_quantity?, <<~PATTERN
          (send {(const {nil? cbase} :InventoryLevel) (send _ :inventory_levels)} {#{CREATE_METHODS.map(&:inspect).join(' ')}} ...)
        PATTERN

        def on_send(node)
          if ledger_const_write?(node) || ledger_association_write?(node)
            add_offense(node, message: MSG_LEDGER)
            return
          end

          # attribute writer：level.available = 5
          if WRITER_METHODS.include?(node.method_name)
            add_offense(node, message: MSG_QUANTITY)
            return
          end

          quantity_kwargs = quantity_keys_in(node)
          # Level 建列帶初始數量＝繞過 ledger 的開帳（不帶數量的建列是 callback 的正當路徑）
          if level_create_with_quantity?(node) && quantity_kwargs.any?
            add_offense(node, message: MSG_QUANTITY)
            return
          end

          return unless WRITE_METHODS.include?(node.method_name)

          add_offense(node, message: MSG_QUANTITY) if quantity_kwargs.any?
        end

        private

        def quantity_keys_in(node)
          hash = node.arguments.find { |arg| arg.hash_type? }
          return [] unless hash

          hash.pairs.map { |pair| pair.key.sym_type? ? pair.key.value : nil }.compact & QUANTITY_KEYS
        end
      end
    end
  end
end
