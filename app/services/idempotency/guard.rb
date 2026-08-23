# frozen_string_literal: true

module Idempotency
  # claim/replay 狀態機（docs/specs/11 §2.1）——mutation 的冪等唯一入口。
  #
  # ## 用法
  #
  #     outcome = Idempotency::Guard.with(
  #       shop: shop, key: key, mutation_name: "ProductSet", input: input_hash
  #     ) do
  #       product = ...  # 業務寫入（可自帶 transaction，會併入本 Guard 的外層 transaction）
  #       [ product, user_errors ]   # block 回傳 [結果物件, userErrors 陣列]
  #     end
  #
  # ## 交易邊界（2026-08-23 裁定 D-PS1，經對抗審查修訂）
  #
  # 三段式，每段的邊界都有理由：
  #
  #   ① **claim INSERT 在業務 transaction 外**（獨立 commit）：
  #      InnoDB 下若未 commit 就進業務 transaction，第二個同 key 請求的 INSERT
  #      會卡在唯一索引的鎖上等待（最長 innodb_lock_wait_timeout 秒），
  #      不是 11 §2.1(b) 要求的**立即** `IDEMPOTENCY_CONCURRENT_REQUEST`。
  #   ② **succeeded 落款在業務 transaction 內**（與業務寫入同 commit）：
  #      idempotency_keys 與業務表在同一個 MySQL——落款放外面就有
  #      「業務已 commit、process 在落款前死掉」的窗口：列卡 processing 直到 TTL，
  #      過期被 destroy 後同 key 重試會把**已存在的商品再建一次**（重複實體，
  #      正是本機制要防的事故）。放進同一個 transaction，這個窗口不存在。
  #   ③ **failed 落款在 transaction 外**：業務失敗時 block 沒有寫入要保
  #      （SaveProduct 回 userErrors 時未動任何表）；例外時 transaction 已 rollback。
  #      failed 列必須在 rollback 後存活，(b) 表的 failed 態才有記錄可查。
  #      殘餘窗口（誠實登記）：failed 落款前 process 死掉 ⇒ 列卡 processing 到 TTL，
  #      同 key 在 TTL 內被 CONCURRENT_REQUEST 擋——方向是**防重複**而非可用性，可接受。
  #
  # ## 🔴 業務失敗（非空 userErrors）記 `failed`（D-PS2）
  #
  # 本尊只說回放「由當前 DB 狀態重建」，沒說業務失敗算不算成功。本專案定義：
  # **非空 userErrors ⇒ 什麼都沒 commit ⇒ 依 (b) 表記 `failed`（同 key 可重試）**。
  # 裁定全文見 docs/dev/m1-product-set-foundation.md。
  #
  # @see docs/specs/11-production-baseline.md §2.1
  module Guard
    # claim 衝突時拋出，承載呼叫端該回的 userError code。
    class Conflict < StandardError
      # @return [String] CONCURRENCY 池裡的 code（見 code_pools.rb）
      attr_reader :code

      def initialize(code, message)
        @code = code
        super(message)
      end
    end

    class << self
      # 以 claim/replay 包住一次寫入。
      #
      # @param shop [Shop] 當前租戶。🔴 整台狀態機**只信這個參數**，不依賴環境的
      #   `ActsAsTenant.current_tenant`——背景 job／多店迭代的呼叫者不保證
      #   ambient tenant 與 shop 一致，靠環境會在 replay 分支靜默查錯店（回 nil
      #   被誤判成「商品已刪」）或在 require_tenant 下直接 raise。
      # @param key [String] 呼叫端的冪等鍵
      # @param mutation_name [String] mutation 類別的 graphql_name（稽核＋mismatch 偵測）
      # @param input [Hash] 用於指紋的輸入（CanonicalJson 正規化後 SHA256）
      # @yieldreturn [Array(Object, Array)] `[結果物件, userErrors]`
      # @return [Hash] `{ replayed:, resource:, user_errors: }`
      # @raise [Conflict] processing 撞車或同 key 不同參數
      # @note 副作用：對 idempotency_keys 寫入 claim 列並更新其狀態（邊界見模組註釋）。
      def with(shop:, key:, mutation_name:, input:)
        fingerprint = CanonicalJson.fingerprint(input)
        record = claim!(shop:, key:, mutation_name:, fingerprint:)
        return replay(shop, record) if record.state == "succeeded"

        run_and_settle(record) { yield }
      end

      private

      # 搶佔或分流既有列。
      #
      # @param retrying [Boolean] 過期讓位後的單次重試旗標——防止兩個請求互相
      #   destroy／create 造成無界遞迴；第二次仍撞唯一索引就走正常分流。
      # @return [IdempotencyKey] 可執行的 processing 列或可回放的 succeeded 列
      # @raise [Conflict] processing 撞車／指紋不符
      def claim!(shop:, key:, mutation_name:, fingerprint:, retrying: false)
        create_claim(shop:, key:, mutation_name:, fingerprint:)
      rescue ActiveRecord::RecordNotUnique
        existing = ActsAsTenant.with_tenant(shop) do
          IdempotencyKey.find_by(key: key)
        end
        # 撞唯一索引後列又不見了＝另一請求正在過期讓位（destroy→create 之間）；
        # 依 processing 語義回 CONCURRENT，讓呼叫端退避重試，不遞迴搶。
        if existing.nil?
          raise concurrent_conflict
        end

        settle_existing(existing, shop:, key:, mutation_name:, fingerprint:, retrying:)
      end

      def create_claim(shop:, key:, mutation_name:, fingerprint:)
        ActsAsTenant.with_tenant(shop) do
          IdempotencyKey.create!(
            key:,
            mutation_name:,
            params_fingerprint: fingerprint,
            state: "processing",
            expires_at: Limits.fetch(:idempotency, :ttl_hours).hours.from_now
          )
        end
      end

      # 對既有列依 11 §2.1(b) 分流。
      #
      # 🔴 兩個會「改既有列再執行」的分支（expired 讓位、failed 重試）都必須是
      #    **原子搶佔**，不是 read-modify-write——兩個並發同 key 請求讀到同一個
      #    快照後各自 update! 會**雙雙通過**，然後各建一個商品（對抗審查
      #    confirmed #3）。原子化手段＝帶狀態條件的 UPDATE／DELETE，
      #    受影響列數 1 才算搶到；搶輸的一方按在場者語義分流。
      def settle_existing(existing, shop:, key:, mutation_name:, fingerprint:, retrying:)
        if existing.expired?
          raise concurrent_conflict if retrying

          # 原子讓位：帶 id 的 DELETE 天然冪等（兩請求同時刪，第二個刪 0 列也無妨），
          # 真正的互斥在接下來的 create 撞唯一索引時由 retrying 旗標分流。
          ActsAsTenant.with_tenant(shop) do
            IdempotencyKey.where(id: existing.id).delete_all
          end
          return claim!(shop:, key:, mutation_name:, fingerprint:, retrying: true)
        end

        # failed＝視為未執行、同 key 可重試（重試帶的正是修正後參數 ⇒ 指紋隨新嘗試
        # 重置，分流先於指紋比對）。CAS：只有把 state 從 failed 翻成 processing 的
        # 那一個請求獲得執行權。
        if existing.state == "failed"
          won = ActsAsTenant.with_tenant(shop) do
            IdempotencyKey.where(id: existing.id, state: "failed")
                          .update_all(state: "processing", mutation_name:,
                                      params_fingerprint: fingerprint,
                                      updated_at: Time.current)
          end
          raise concurrent_conflict if won.zero?

          return existing.reload
        end

        if existing.mutation_name != mutation_name ||
           existing.params_fingerprint != fingerprint
          raise Conflict.new(
            "IDEMPOTENCY_KEY_PARAMETER_MISMATCH",
            "同一把冪等鍵先前用於不同的參數（#{existing.mutation_name}）。請修正參數或改用新的 key。"
          )
        end

        raise concurrent_conflict if existing.state == "processing"

        existing # succeeded ⇒ 呼叫端走回放
      end

      # 回放：由 result_ref 重新載入物件；物件已被刪除 ⇒ 呼叫端回網域性 NOT_FOUND
      # （「原請求成功，但關聯資料隨後被刪除」，11 §2.1(b) 最後一列）。
      # 🔴 查詢釘在 shop 參數的 tenant scope 內——不信 ambient（理由見 #with）。
      def replay(shop, record)
        resource = ActsAsTenant.with_tenant(shop) do
          record.resource_type&.constantize&.find_by(id: record.resource_id)
        end
        { replayed: true, resource:, user_errors: [] }
      end

      # 執行業務 block 並落款（交易邊界 ②③，見模組註釋）。
      def run_and_settle(record)
        resource = nil
        user_errors = nil
        begin
          # requires_new: 巢狀時建 SAVEPOINT——joined 巢狀下 `raise ActiveRecord::
          # Rollback` 會被**靜默吞掉且什麼都不回滾**（Rails 已知語義），部分寫入
          # 照樣 commit。獨立呼叫時它就是一般 transaction，語義不變。
          ActiveRecord::Base.transaction(requires_new: true) do
            resource, user_errors = yield
            if user_errors.blank?
              # succeeded 與業務寫入同 commit——落款本身失敗 ⇒ 整包 rollback，
              # 列留在 processing（方向是防重複實體，不是可用性）。
              record.update!(
                state: "succeeded",
                resource_type: resource.class.name,
                resource_id: resource.id
              )
            else
              # 🔴 業務失敗必須顯式 rollback：block 內（如 SaveProduct）自己的
              # `transaction do` 併入本外層後，其「rescue 例外回 userErrors」路徑
              # **不再**觸發真正的 rollback——沒有這一行，變體 INSERT 失敗前已寫入
              # 的 product 列會被外層 commit 成孤兒（對抗審查後自查抓到）。
              raise ActiveRecord::Rollback
            end
          end
        rescue StandardError
          # 例外 ⇒ transaction 已 rollback（含 succeeded 落款）⇒ 記 failed 供同 key 重試。
          # failed 落款自身再失敗就讓列留在 processing（同上，防重複優先）。
          mark_failed(record)
          raise
        end

        mark_failed(record) if user_errors.present?
        { replayed: false, resource:, user_errors: user_errors || [] }
      end

      def mark_failed(record)
        record.update!(state: "failed", resource_type: nil, resource_id: nil)
      rescue StandardError
        nil # 列留在 processing；TTL 之後照 (b) 表視為全新操作
      end

      def concurrent_conflict
        Conflict.new(
          "IDEMPOTENCY_CONCURRENT_REQUEST",
          "同一把冪等鍵的另一個請求正在處理中，請稍後以同一把 key 重試。"
        )
      end
    end
  end
end
