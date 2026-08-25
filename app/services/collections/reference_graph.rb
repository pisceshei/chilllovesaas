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
  # ④🔴 **環在寫入層就被拒**（2026-08-26 第七輪 L1，`reaches?` ＋ `SaveCollection`）：
  #   自引（J5）之外，**任何長度的環**一律 INVALID。理由是 J5 那句話的一般化——
  #   「A 排除 B」讀的是 B 的**物化成員**，所以它是一個**反單調**函數 a := ¬b。
  #   奇數長度的環是奇數次反單調的合成 ⇒ **沒有不動點**，成員週期震盪；
  #   而第六輪的反向傳播（K8）以「本輪成員有沒有變」為傳播條件，震盪的每一步都「有變」
  #   ⇒ 無界的 RebuildJob 鏈、無界的 `collections/update` outbox（EXTERNAL，會外發 webhook），
  #   而兜底 rake 自己跑一輪就是新的震盪源。實測 n=3／n=5 永不終止（週期 6），
  #   n=2／n=4 各 1／2 個 job 就停——偶數環是兩次反單調的合成＝單調，有不動點。
  #   ⇒ 判準不是「偶數放行奇數拒收」（那只是碰巧收斂，答案仍取決於起始狀態），
  #   而是**全部拒收**：環在這個語義下沒有一個「對」的答案可言。
  #   本模組因此在正常資料上不會遇到環；`visiting` 標記只為**既有資料**（守衛上線前
  #   建立的）留一條不無窮迴圈的路。
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

    # 能沿著 exclusion 引用鏈走到 `target_id` 的**全部**系列（＝target 的祖先集合）。
    # 🔴 一次算完，取代「每條規則各跑一次 `reaches?`」（2026-08-26 第八輪 M3）：
    #   `reaches?` 每訪問一個節點打一次 DB，而 `normalize_rule` 對**每一條** collection
    #   型規則各叫一次、跨規則零記憶化 ⇒ 上限相乘（每系列 60 條規則 × 每店 5000 個
    #   系列）可在同步請求路徑上打出數十萬次查詢。本方法逐層批次查（每層一次 IN 查詢），
    #   呼叫端算一次、所有規則共用。
    #   判準等價：「加 current→referenced 這條邊會成環」⇔「referenced 走得回 current」
    #   ⇔ `referenced ∈ ancestors(current)`。
    # @return [Set<Integer>]
    def ancestors(shop, target_id)
      seen = Set.new
      frontier = [ target_id ]
      until frontier.empty?
        parents = CollectionSourceRule
                  .joins(:source)
                  .where(shop_id: shop.id, block: "exclusion", condition_type: "collection",
                         value_int: frontier)
                  .distinct.pluck("collection_sources.collection_id")
        frontier = parents.reject { |id| seen.include?(id) }
        seen.merge(frontier)
      end
      seen
    end

    # `from_id` 能不能沿著 exclusion 引用鏈走到 `target_id`？（迭代，不遞迴。）
    # 用途＝寫入層的環偵測：要加「current 排除 referenced」這條邊之前，
    # 先問「referenced 走得回 current 嗎」——走得回就是環。
    # @return [Boolean]
    def reaches?(shop, from_id, target_id)
      return true if from_id == target_id

      seen = Set.new([ from_id ])
      stack = [ from_id ]
      until stack.empty?
        current = stack.pop
        next_ids = CollectionSourceRule
                   .joins(:source)
                   .where(shop_id: shop.id, block: "exclusion", condition_type: "collection")
                   .where(collection_sources: { collection_id: current })
                   .pluck(:value_int).compact
        next_ids.each do |nxt|
          return true if nxt == target_id
          next if seen.include?(nxt)

          seen << nxt
          stack.push(nxt)
        end
      end
      false
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
