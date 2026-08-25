# frozen_string_literal: true

module Collections
  # 智慧系列之間的**引用關係圖**（第 11 包；2026-08-26 第六輪 K1／K2 的結構性修法）。
  #
  # ①這是什麼：exclusion 的 `collection` 型條件讓系列 A 的成員資格依賴系列 B 的
  #   **物化列**（`RuleCompiler#compile_collection_exclusion` 讀 `collection_memberships`，
  #   不是重算 B 的規則——V-140 的裁定）。於是「先算誰」會改變答案，而且
  #   「B 變了誰要跟著重算」也不是自動的。這兩件事以前散在三條路徑各寫一份，
  #   三次審查抓到三次不一致 ⇒ 收斂成這一支，**三條路徑都只准用它**。
  #
  # ②🔴 為什麼必須是**一份**實作（本包最貴的教訓，逐輪記在 worklog）：
  #   求值路徑有三條——`ResyncProduct`（商品事件的增量）、`Rebuild`（規則編輯後的
  #   單系列全量）、`catalog:rebuild:collections`（兜底全量）。前幾輪每次只改其中
  #   一條，另外兩條就與它分岔：
  #     G4／H5／J3 改 resync 的順序（三次都只改 resync）；
  #     K2 發現兜底 rake 仍照 id 序 ⇒ **同一份規則，resync 給 A=[]、rake 給 A=[商品]**，
  #       正是 H4「成員集合取決於最後跑的是哪一支引擎」那個根因被重新打開；
  #     K8 發現規則編輯路徑（`enqueue_rebuild` 只排自己那一個系列）**完全沒有**
  #       反向傳播 ⇒ B 改了、引用 B 的 A 永遠不重算，且無自癒路徑。
  #   ⇒ 判準只有這一支：`topological`（先算誰）＋`referrers`（誰要跟著重算）。
  #
  # ③🔴 **不用遞迴**（K1，實跑重現）：初版拓樸排序是 lambda 遞迴，DFS 深度＝引用鏈
  #   長度，而 `limits.collection.max_smart_collections_per_shop` 允許 5000 個系列
  #   ⇒ 鏈長約 1100 就 `SystemStackError`。它**不是 `StandardError`**，
  #   `Events::Relay` 的兩處 rescue 都只接 `StandardError` ⇒ 例外穿透投遞迴圈：
  #   該事件 `attempts` 永不遞增、永不進 dead-letter，`locked_at` 逾時被回收後再炸
  #   （永久毒丸），且同一批 `claim_batch` 內**其他商店**的事件一起不投遞。
  #   ⇒ 本檔一律用**顯式堆疊**的迭代 DFS，深度只受記憶體限制。
  #
  # ④環（A⇄B、A→B→C→A）沒有拓樸序：以穩定順序打破，登記 P11-B10、由 rake 兜底。
  #   自我引用（A 排除 A）在寫入層就被拒（J5），這裡不會遇到。
  module ReferenceGraph
    module_function

    # @param shop [Shop]
    # @param ids [Array<Integer>] 候選系列 id
    # @return [Hash{Integer => Array<Integer>}] collection_id => 它引用的 collection id
    def edges(shop, ids)
      return {} if ids.empty?

      CollectionSourceRule
        .joins(:source)
        .where(shop_id: shop.id, block: "exclusion", condition_type: "collection")
        .where(collection_sources: { collection_id: ids })
        .pluck("collection_sources.collection_id", :value_int)
        .each_with_object({}) { |(from, to), acc| (acc[from] ||= []) << to if to }
    end

    # 被引用者先算的順序。回傳是 `ids` 的**排列**（不多不少，順序滿足依賴）。
    # @param shop [Shop]
    # @param ids [Array<Integer>]
    # @return [Array<Integer>]
    def topological(shop, ids)
      graph = edges(shop, ids)
      return ids if graph.empty?

      known = ids.to_set
      state = {}      # id => :visiting | :done
      ordered = []

      ids.each do |root|
        next if state[root] == :done

        # 顯式堆疊的迭代 DFS（檔頭③：不得遞迴）。
        # frame = [id, 尚未處理的依賴清單]
        stack = [ [ root, nil ] ]
        until stack.empty?
          id, pending = stack.last
          if pending.nil?
            if state[id] == :done
              stack.pop
              next
            end
            state[id] = :visiting
            pending = Array(graph[id]).sort.select { |dep| known.include?(dep) }
            stack[-1] = [ id, pending ]
          end

          dep = pending.shift
          if dep.nil?
            state[id] = :done
            ordered << id
            stack.pop
          elsif state[dep].nil?
            stack.push([ dep, nil ])
          end
          # state[dep] == :visiting ⇒ 環，跳過（檔頭④）；:done ⇒ 已排好。
        end
      end
      ordered
    end

    # 直接引用 `collection_id` 的系列（＝它變動後要跟著重算的那些）。
    # @return [Array<Integer>]
    def referrers(shop, collection_id)
      CollectionSourceRule
        .joins(:source)
        .where(shop_id: shop.id, block: "exclusion", condition_type: "collection",
               value_int: collection_id)
        .distinct.pluck("collection_sources.collection_id")
    end
  end
end
