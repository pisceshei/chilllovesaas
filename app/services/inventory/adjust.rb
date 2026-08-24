# frozen_string_literal: true

module Inventory
  # 庫存數量的**唯一寫入入口**（排程第 17 包；13 §F5；總裁定 §一／§三；D41–D43）。
  #
  # ①這是什麼：一次呼叫＝一把 idempotencyKey＝一列 `inventory_adjustment_groups`
  #   ＝N 列 append-only ledger 子行＋levels 現值更新，全有全無。
  #   adjust（差額）與 set（絕對值＋CAS）兩種模式共用本入口。
  # ②值域：
  #   - `reason` ∈ limits.inventory.adjustment_reasons（API 17 值；UI 只露 7 值子集）
  #   - adjust 可調的 name＝available／on_hand／reserved／damaged／safety_stock／quality_control；
  #     **committed 與 incoming 不可調**（committed 由訂單線獨佔、incoming 由採購/轉移線獨佔）
  #   - set 只收 available／on_hand（本尊 InventorySetQuantitiesInput.name 明文）
  #   - 🔴 `on_hand` 是導出量：寫它的語義＝**翻譯成 available 的 delta**（總裁定 §2.3；
  #     與本尊互動語義一致——改 on hand 則 available 同額變動）
  #   - 邊界：adjust delta ∈ ±limits.adjust_quantity_max；set 目標 ∈ ±limits.set_total_quantity_max
  #     （🔴 兩支不同：2e9 vs 1e9，docs/research/95 §5）
  # ③怎麼做：驗證全收集（無半途寫入）→ Guard claim → transaction 內
  #   SELECT FOR UPDATE（🔴 按 level id 排序鎖，防死鎖）→ CAS 比對 → 建 group＋子行＋更新 levels。
  #   同呼叫重複 (item, location) ⇒ reject（V-96.1 fail-closed，不合併——合併會讓
  #   per-change 的 ledgerDocumentUri 與 quantityAfterChange 失去落點）。
  #   ledgerDocumentUri：available **不得帶**、其他 name **必帶**、禁 gid://shopify/*、
  #   同呼叫全部非 nil 值必須相同（MAX_ONE_LEDGER_DOCUMENT）——四條全是本尊語義（95 §4）。
  # ④跨功能影響：Guard 的 result resource＝group 列（Guard 不必改）；歷程頁（第 18 包）
  #   一列＝一 group；對帳（Inventory::Reconcile）以本入口寫的 ledger 為唯一真相；
  #   事件 outbox 屬第 19 包（本包刻意不發事件，該包接上時在本檔加掛）。
  #   🔴 禁直寫 cop（Chilllove/InventoryDirectWrite）確保本檔以外沒有第二條寫入路徑（D43 無豁免口）。
  class Adjust
    Result = Data.define(:group, :user_errors)

    ADJUSTABLE_NAMES = %w[available on_hand reserved damaged safety_stock quality_control].freeze
    SETTABLE_NAMES = %w[available on_hand].freeze
    # name → levels/adjustments 的實體欄（on_hand 翻譯成 available）
    LEAF_FOR = {
      "available" => "available", "on_hand" => "available",
      "reserved" => "reserved", "damaged" => "damaged",
      "safety_stock" => "safety_stock", "quality_control" => "quality_control"
    }.freeze

    ITEM_GID = %r{\Agid://chilllove/InventoryItem/(\d+)\z}
    LOCATION_GID = %r{\Agid://chilllove/Location/(\d+)\z}

    class << self
      # @param shop [Shop]
      # @param mode [String] "adjust"（差額）或 "set"（絕對值）
      # @param input [Hash] idempotency_key / reason / name / reference_document_uri /
      #   changes: [{inventory_item_id:, location_id:, delta: | quantity:,
      #              change_from_quantity: | compare_quantity:, ignore_compare_quantity:,
      #              ledger_document_uri:}]
      # @param staff [StaffMember, nil]
      # @return [Result]
      def call(shop:, mode:, input:, staff: nil)
        errors = validate(shop, mode, input)
        return Result.new(group: nil, user_errors: errors) if errors.any?

        outcome = Idempotency::Guard.with(
          shop: shop,
          key: input.fetch(:idempotency_key),
          mutation_name: mode == "set" ? "InventorySetQuantities" : "InventoryAdjustQuantities",
          input: deep_stringify(input)
        ) do
          apply!(shop, mode, input, staff)
        end

        if outcome[:replayed] && outcome[:resource].nil?
          return Result.new(group: nil, user_errors: [ error(nil, I18n.t("errors.inventory.replay_target_missing"), "NOT_FOUND") ])
        end

        Result.new(group: outcome[:resource], user_errors: outcome[:user_errors] || [])
      rescue Idempotency::Guard::Conflict => conflict
        Result.new(group: nil, user_errors: [ error(nil, conflict.message, conflict.code) ])
      end

      private

      # 全部驗證先行、全部收集——半途才發現錯就會留半成品（宣告式契約的教訓同 SaveCollection）。
      def validate(shop, mode, input)
        errors = []
        reason = input[:reason].to_s
        name = input[:name].to_s
        changes = Array(input[:changes])

        errors << error([ "reason" ], I18n.t("errors.inventory.invalid_reason"), "INVALID_REASON") unless InventoryAdjustmentGroup::REASONS.include?(reason)
        allowed = mode == "set" ? SETTABLE_NAMES : ADJUSTABLE_NAMES
        unless allowed.include?(name)
          code = mode == "set" ? "INVALID_NAME" : "INVALID_QUANTITY_NAME"
          errors << error([ "name" ], I18n.t("errors.inventory.invalid_name", name: name), code)
        end
        errors << error([ "changes" ], I18n.t("errors.inventory.changes_blank"), "BLANK") if changes.empty?

        seen = Set.new
        ledger_uris = []
        changes.each_with_index do |change, index|
          path = [ "changes", index.to_s ]
          item_id = change[:inventory_item_id].to_s[ITEM_GID, 1]
          loc_id = change[:location_id].to_s[LOCATION_GID, 1]
          errors << error(path + [ "inventoryItemId" ], I18n.t("errors.inventory.invalid_gid"), "INVALID") if item_id.nil?
          errors << error(path + [ "locationId" ], I18n.t("errors.inventory.invalid_gid"), "INVALID") if loc_id.nil?

          # 🔴 dedup 用 int：GID 正則截出的是字串，"007" 與 "7" 都落到同一 level，
          #    字串集合會放行前導零的重複（對抗審查 #6）。
          if item_id && loc_id && !seen.add?([ item_id.to_i, loc_id.to_i ])
            # V-96.1 fail-closed：不合併、直接拒
            errors << error(path, I18n.t("errors.inventory.duplicate_item_location"), "DUPLICATE_INVENTORY_ITEM")
          end

          errors.concat(validate_quantity(mode, change, path))
          errors.concat(validate_ledger_document(name, change, path, ledger_uris))
        end
        # MAX_ONE：同呼叫所有非 nil ledgerDocumentUri 必須相同
        if ledger_uris.uniq.length > 1
          errors << error([ "changes" ], I18n.t("errors.inventory.max_one_ledger_document"), "MAX_ONE_LEDGER_DOCUMENT")
        end
        errors
      end

      def validate_quantity(mode, change, path)
        if mode == "set"
          quantity = change[:quantity]
          max = Limits.fetch(:inventory, :set_total_quantity_max)
          min = Limits.fetch(:inventory, :set_total_quantity_min)
          return [ error(path + [ "quantity" ], I18n.t("errors.inventory.quantity_too_high", max: max), "INVALID_QUANTITY_TOO_HIGH") ] if quantity.to_i > max
          return [ error(path + [ "quantity" ], I18n.t("errors.inventory.quantity_too_low", min: min), "INVALID_QUANTITY_TOO_LOW") ] if quantity.to_i < min
          # CAS 必須表態：帶 compareQuantity 或顯式 ignore（本尊 COMPARE_QUANTITY_REQUIRED）
          if change[:compare_quantity].nil? && change[:ignore_compare_quantity] != true
            return [ error(path, I18n.t("errors.inventory.compare_quantity_required"), "COMPARE_QUANTITY_REQUIRED") ]
          end
        else
          delta = change[:delta]
          max = Limits.fetch(:inventory, :adjust_quantity_max)
          min = Limits.fetch(:inventory, :adjust_quantity_min)
          return [ error(path + [ "delta" ], I18n.t("errors.inventory.quantity_too_high", max: max), "INVALID_QUANTITY_TOO_HIGH") ] if delta.to_i > max
          return [ error(path + [ "delta" ], I18n.t("errors.inventory.quantity_too_low", min: min), "INVALID_QUANTITY_TOO_LOW") ] if delta.to_i < min
        end
        []
      end

      # `ledgerDocumentUri` 免附文件的 name 集合。
      #
      # 🔴 **`on_hand` 在此是我方的刻意放寬（ours），不是照抄本尊**（使用者 2026-08-24 裁定）。
      # 本尊語義是「除 available 外全部必填」（95 §4）。我方放寬的理由有二：
      #   ① **在我方模型裡 on_hand 不是獨立變數**——`LEAF_COLUMN` 明文把它翻譯成
      #      `available` leaf（見本檔 §「name → levels/adjustments 的實體欄」）。
      #      既然實際寫的是 available 這條 leaf，卻要求它附一份 available 自己不准附的文件，
      #      規則就自相矛盾。
      #   ② **手動盤點沒有文件可附**。庫存後台的 On hand 儲存格是商家數完架上數量後直接改的，
      #      不存在對應的轉移單／收貨單。強制必填的結果是這個入口 100% 失敗
      #      （實測 bt3 回 `INVALID_QUANTITY_DOCUMENT`），等於功能不存在。
      # 其餘四個 name（reserved／damaged／safety_stock／quality_control）**維持必填**：
      # 它們是真正獨立的 leaf，且都由單據驅動，附文件才有稽核意義。
      LEDGER_DOCUMENT_OPTIONAL_NAMES = %w[available on_hand].freeze

      def validate_ledger_document(name, change, path, ledger_uris)
        uri = change[:ledger_document_uri]
        if name == "available"
          return [ error(path + [ "ledgerDocumentUri" ], I18n.t("errors.inventory.available_document_forbidden"), "INVALID_AVAILABLE_DOCUMENT") ] if uri.present?
        elsif LEDGER_DOCUMENT_OPTIONAL_NAMES.include?(name)
          # on_hand：帶了就照下面的 gid 檢查驗，不帶也放行（見上方裁定）
        elsif uri.blank?
          return [ error(path + [ "ledgerDocumentUri" ], I18n.t("errors.inventory.quantity_document_required"), "INVALID_QUANTITY_DOCUMENT") ]
        end
        if uri.present?
          return [ error(path + [ "ledgerDocumentUri" ], I18n.t("errors.inventory.shopify_gid_forbidden"), "INVALID") ] if uri.start_with?("gid://shopify/")

          ledger_uris << uri
        end
        []
      end

      # Guard block 內：解析 → 鎖 → CAS → 寫。回 [resource, user_errors]。
      def apply!(shop, mode, input, staff)
        name = input[:name].to_s
        leaf = LEAF_FOR.fetch(name)
        changes = Array(input[:changes])

        resolution = resolve_levels(shop, changes)
        return [ nil, resolution.fetch(:errors) ] if resolution.key?(:errors)

        resolved = resolution.fetch(:entries)

        group = nil
        errors = []
        ActsAsTenant.with_tenant(shop) do
          ActiveRecord::Base.transaction(requires_new: true) do
            # 🔴 單一查詢 ORDER BY id 上鎖：兩個併發呼叫都以升冪取得列鎖 ⇒ 無死鎖。
            #    之後的迭代照**送入順序**（position 與 CAS 錯誤路徑都要對應輸入索引，
            #    冪等指紋也對順序敏感）——鎖序與寫序是兩件事，只有鎖序需要固定。
            locked = InventoryLevel.where(shop_id: shop.id, id: resolved.map { |e| e[:level_id] }).order(:id).lock("FOR UPDATE").index_by(&:id)

            resolved.each_with_index do |entry, index|
              level = locked[entry.fetch(:level_id)]
              # 🔴 鎖外解析與 FOR UPDATE 之間列被刪（併發清理）⇒ 回 NOT_FOUND，
              #    不是 locked.fetch 的 KeyError 500（對抗審查 #14/#18）。
              if level.nil?
                errors << error([ "changes", index.to_s ], I18n.t("errors.inventory.level_not_found", item: entry.fetch(:change)[:inventory_item_id], location: entry.fetch(:change)[:location_id]), "NOT_FOUND")
                next
              end
              current = level.public_send(name == "on_hand" ? "on_hand" : leaf)
              change = entry.fetch(:change)

              # 🔴 CAS 錯誤帶 change 索引（對抗審查 #7/#15/#20：與 validate 階段的
              #    ["changes", index] 形態一致，前端才能把錯誤釘到那一列輸入）。
              if mode == "set"
                unless change[:ignore_compare_quantity] == true || change[:compare_quantity].to_i == current
                  errors << error([ "changes", index.to_s ], I18n.t("errors.inventory.compare_quantity_stale", expected: change[:compare_quantity], actual: current), "COMPARE_QUANTITY_STALE")
                  next
                end
                entry[:delta] = change[:quantity].to_i - current
              else
                cas = change[:change_from_quantity]
                unless cas.nil? || cas.to_i == current
                  errors << error([ "changes", index.to_s ], I18n.t("errors.inventory.change_from_quantity_stale", expected: cas, actual: current), "CHANGE_FROM_QUANTITY_STALE")
                  next
                end
                entry[:delta] = change[:delta].to_i
              end
            end
            raise ActiveRecord::Rollback if errors.any?

            # 🔴 零 delta 不落列（對抗審查 #16：set 到相同值 ⇒ 全零列讓 changesCount=1
            #    但 changes 投影為空，payload 自相矛盾；ledger 也不該累積無語義列）。
            #    group 仍建立＝該次呼叫的冪等回執；effective 可為空（changes_count=0）。
            effective = resolved.reject { |entry| entry.fetch(:delta).zero? }
            group = InventoryAdjustmentGroup.create!(
              shop_id: shop.id,
              idempotency_key: input.fetch(:idempotency_key),
              quantity_name: name,
              reason: input[:reason].to_s,
              mutation_kind: mode,
              reference_document_uri: input[:reference_document_uri],
              staff_member_id: staff&.id,
              client_source: input[:client_source] || "admin_web",
              changes_count: effective.length
            )
            # 🔴 結果值邊界（對抗審查 confirmed：兩次各 +1.5e9 單獨合法、相加炸 INT ⇒ 500）。
            #    單次 delta 邊界擋不住累積；欄位是 signed INT，結果必須在 ±quantity_result_max 內
            #    ——含投影後的 on_hand（STORED GENERATED 是六 leaf 之和，任一 leaf 合法
            #    不代表和合法）。超界回 userError（第①層），不是讓 MySQL 炸非 200。
            result_max = Limits.fetch(:inventory, :quantity_result_max)
            result_min = Limits.fetch(:inventory, :quantity_result_min)
            effective.each_with_index do |entry, index|
              level = locked.fetch(entry.fetch(:level_id))
              new_leaf = level.public_send(leaf) + entry.fetch(:delta)
              new_on_hand = level.on_hand + entry.fetch(:delta)
              if new_leaf > result_max || new_on_hand > result_max
                errors << error([ "changes", index.to_s ], I18n.t("errors.inventory.quantity_too_high", max: result_max), "INVALID_QUANTITY_TOO_HIGH")
              elsif new_leaf < result_min || new_on_hand < result_min
                errors << error([ "changes", index.to_s ], I18n.t("errors.inventory.quantity_too_low", min: result_min), "INVALID_QUANTITY_TOO_LOW")
              end
            end
            raise ActiveRecord::Rollback if errors.any?

            effective.each_with_index do |entry, index|
              InventoryAdjustment.create!(
                shop_id: shop.id,
                inventory_adjustment_group_id: group.id,
                inventory_level_id: entry.fetch(:level_id),
                leaf_delta_column(leaf) => entry.fetch(:delta),
                ledger_document_uri: entry.fetch(:change)[:ledger_document_uri],
                position: index
              )
              level = locked.fetch(entry.fetch(:level_id))
              level.update!(leaf => level.public_send(leaf) + entry.fetch(:delta))
            end
          end
        end
        [ group, errors ]
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => collision
        # 🔴 D44：Guard 的 24h TTL 讓位重跑後，group 的**永久**唯一索引會撞舊列
        #    （對抗審查以實跑 repro 證實：不接住＝該 key 被毒化成永久 5xx）。
        #    不靜默 replay 舊 group——TTL 過期後指紋已失，參數可能不同，
        #    回舊結果是在冒充成功。fail-closed：回 userError 請客戶端換新鍵。
        raise unless collision.message.match?(/idempotency.key|uq_inventory_adjustment_groups_idem_key/i)

        [ nil, [ error(nil, I18n.t("errors.inventory.key_already_used"), "IDEMPOTENCY_KEY_ALREADY_USED") ] ]
      end

      def leaf_delta_column(leaf) = :"#{leaf}_delta"

      # GID → level id；查無（含跨店）回 NOT_FOUND（不回 ACCESS_DENIED——那是資源枚舉旁路）。
      def resolve_levels(shop, changes)
        entries = changes.map do |change|
          item_id = change[:inventory_item_id].to_s[ITEM_GID, 1].to_i
          loc_id = change[:location_id].to_s[LOCATION_GID, 1].to_i
          level = ActsAsTenant.with_tenant(shop) { InventoryLevel.find_by(shop_id: shop.id, inventory_item_id: item_id, location_id: loc_id) }
          if level.nil?
            return { errors: [ error([ "changes" ], I18n.t("errors.inventory.level_not_found", item: item_id, location: loc_id), "NOT_FOUND") ] }
          end

          { level_id: level.id, change: change }
        end
        { entries: entries }
      end

      def deep_stringify(input)
        JSON.parse(JSON.generate(input))
      end

      def error(field, message, code)
        { field: field, message: message, code: code }
      end
    end
  end
end
