# frozen_string_literal: true

module Idempotency
  # claim/replay 狀態機（docs/specs/11 §2.1）——mutation 的冪等唯一入口。
  #
  # ## 用法
  #
  #     outcome = Idempotency::Guard.with(
  #       shop: shop, key: key, mutation_name: "productSet", input: input_hash
  #     ) do
  #       product = ...  # 業務 transaction
  #       [ product, user_errors ]   # block 回傳 [結果物件, userErrors 陣列]
  #     end
  #     case outcome
  #     in { replayed: true, resource: } ...   # 回放：由 resource 重跑 serializer
  #     in { resource:, user_errors: }  ...    # 首次執行的結果原樣往外遞
  #
  # ## 🔴 claim 在業務 transaction **外**（2026-08-23 裁定，未決點 2 的解）
  #
  # 兩個理由，缺一都不成立：
  #   ① InnoDB 下若 claim INSERT 未 commit 就進業務 transaction，第二個同 key
  #      請求的 INSERT 會**卡在唯一索引的鎖上等待**直到第一個 commit/rollback——
  #      並發重試得到的是 lock wait（最長 innodb_lock_wait_timeout 秒），
  #      不是 11 §2.1(b) 要求的**立即** `IDEMPOTENCY_CONCURRENT_REQUEST`。
  #   ② `failed` 列必須在業務 rollback 之後**仍然存在**，(b) 表的
  #      「failed＝視為未執行、同 key 可重試」才有記錄可查；
  #      claim 在 transaction 內 ⇒ rollback 連 processing 列一起消失，
  #      每次失敗都退化成「無此 key」，狀態機少了一態。
  #
  # ## 🔴 業務失敗（非空 userErrors）記 `failed`（未決點 5 的裁定）
  #
  # 本尊只說回放「由當前 DB 狀態重建」，沒說業務失敗算不算成功。本專案定義：
  # **非空 userErrors ⇒ 什麼都沒 commit ⇒ 依 (b) 表記 `failed`（同 key 可重試）**。
  # 這與「succeeded 必有 result_ref 可重建」自洽——業務失敗沒有結果物件，
  # 想快取也沒有東西可指。裁定全文見 docs/dev/m1-product-set-foundation.md。
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
      # @param shop [Shop] 當前租戶
      # @param key [String] 呼叫端的冪等鍵
      # @param mutation_name [String] GraphQL mutation 名（稽核＋mismatch 偵測）
      # @param input [Hash] 用於指紋的輸入（CanonicalJson 正規化後 SHA256）
      # @yieldreturn [Array(Object, Array)] `[結果物件, userErrors]`；
      #   userErrors 非空時視為業務失敗，結果物件應為 nil
      # @return [Hash] `{ replayed:, resource:, user_errors: }`
      # @raise [Conflict] processing 撞車或同 key 不同參數
      # @note 副作用：對 idempotency_keys 寫入 claim 列並更新其狀態
      #   （皆在業務 transaction 外，理由見模組註釋）。
      # @see docs/specs/11-production-baseline.md §2.1(b)
      def with(shop:, key:, mutation_name:, input:)
        fingerprint = CanonicalJson.fingerprint(input)
        record = claim!(shop:, key:, mutation_name:, fingerprint:)
        return replay(record) if record.state == "succeeded"

        run_and_settle(record) { yield }
      end

      private

      # 搶佔或分流既有列。
      #
      # @return [IdempotencyKey] 可執行的 processing 列（新建或過期重置）
      # @raise [Conflict] processing 撞車／指紋不符
      def claim!(shop:, key:, mutation_name:, fingerprint:)
        create_claim(shop:, key:, mutation_name:, fingerprint:)
      rescue ActiveRecord::RecordNotUnique
        existing = ActsAsTenant.with_tenant(shop) do
          IdempotencyKey.find_by!(key: key)
        end
        settle_existing(existing, shop:, key:, mutation_name:, fingerprint:)
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
      def settle_existing(existing, shop:, key:, mutation_name:, fingerprint:)
        if existing.expired?
          # 過 TTL ⇒ 視為全新操作：舊列讓位（同 key 重新 claim）。
          existing.destroy!
          return create_claim(shop:, key:, mutation_name:, fingerprint:)
        end

        # 🔴 failed 分流在指紋比對**之前**：11 §2.1(b) 對 failed 的語義是
        #    「視為未執行，允許以同一把 key 重試」——重試的正是**修正後的參數**，
        #    先比指紋會把每一次修正都判成 MISMATCH，讓「同 key 重試」形同虛設。
        #    視為未執行 ⇒ 指紋隨新嘗試重置。
        if existing.state == "failed"
          existing.update!(state: "processing", mutation_name:, params_fingerprint: fingerprint)
          return existing
        end

        if existing.mutation_name != mutation_name ||
           existing.params_fingerprint != fingerprint
          raise Conflict.new(
            "IDEMPOTENCY_KEY_PARAMETER_MISMATCH",
            "同一把冪等鍵先前用於不同的參數（#{existing.mutation_name}）。請修正參數或改用新的 key。"
          )
        end

        if existing.state == "processing"
          raise Conflict.new(
            "IDEMPOTENCY_CONCURRENT_REQUEST",
            "同一把冪等鍵的另一個請求正在處理中，請稍後以同一把 key 重試。"
          )
        end

        existing # succeeded ⇒ 呼叫端走回放
      end

      # 回放：由 result_ref 重新載入物件；物件已被刪除 ⇒ 回網域性 NOT_FOUND
      # 語義（「原請求成功，但關聯資料隨後被刪除」，11 §2.1(b) 最後一列）。
      def replay(record)
        resource = record.resource_type&.constantize&.find_by(id: record.resource_id)
        { replayed: true, resource:, user_errors: [] }
      end

      def run_and_settle(record)
        resource, user_errors = yield

        if user_errors.present?
          record.update!(state: "failed", resource_type: nil, resource_id: nil)
        else
          record.update!(
            state: "succeeded",
            resource_type: resource.class.name,
            resource_id: resource.id
          )
        end
        { replayed: false, resource:, user_errors: user_errors || [] }
      rescue StandardError
        # 例外（基礎設施或程式錯誤）同樣記 failed——(b) 表：同 key 可重試。
        record.update!(state: "failed", resource_type: nil, resource_id: nil)
        raise
      end
    end
  end
end
