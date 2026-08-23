# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL 的 mutation root。
  #
  # 🔴 **本型別自 2026-08-23 起掛上 `ChillloveSchema`**——解鎖條件
  # 「第一支真正的 mutation 落地時，同批處理 claim/replay」已由本批滿足：
  # `Mutations::ProductSet` ＋ `Idempotency::Guard`（11 §2.1 狀態機）＋
  # `idempotency_keys` 表形對齊遷移，三者同一個 PR 交付。
  #
  # 歷史（保留給讀 blame 的人）：掛載前它刻意空置且不掛 schema，因為
  # `enforce_idempotency_contract!` 只檢查 key 有沒有帶、不做去重——
  # 掛一個沒有 claim/replay 的 mutation root 會給下一位作者**虛假的安全感**。
  # 那個保護消失的條件就是本次交付的內容；guard spec
  # （spec/graphql/mutation_root_guard_spec.rb）已同批反轉成掛載後的斷言。
  #
  # 🔴 新增 mutation 的義務（① 有 CI 擋；②③ 靠 review——尚無機械斷言，誠實標示）：
  #   ① `resolve` 開頭呼叫 `enforce_idempotency_contract!`（graphql-ruby 無
  #      around hook，忘了呼叫沒有 runtime 機制會發現——由
  #      `spec/graphql/mutation_idempotency_call_spec.rb` 靜態掃描兜底）；
  #   ② 建立型 mutation 進 `limits.idempotency` 對應清單（判準：重放會不會
  #      憑空多出實體或一筆錢）；
  #   ③ 專屬 error code enum ＋ error object type（鐵律 4：code 一律有值）。
  #
  # @see docs/research/28-api-contract.md §0.3.3
  # @see docs/dev/m1-product-set-foundation.md
  class MutationType < BaseObject
    graphql_name "Mutation"
    description "Admin API 的寫入入口。"

    field :product_set, mutation: Mutations::ProductSet,
      description: "商品全樹宣告式 upsert（admin 商品頁 SaveBar 的唯一寫入映射，63 §B.4）。"
    field :staff_locale_update, mutation: Mutations::StaffLocaleUpdate,
      description: "更新目前員工的 admin 介面語言（67 §E.1；ML-1）。"
    field :collection_set, mutation: Mutations::CollectionSet,
      description: "商品系列全樹宣告式 upsert（ML-3；與 productSet 對稱）。"
    # ML-4：語言集合是**資料**——這三支只動 shop_locales 的列，不建表、不 migration。
    field :shop_locale_enable, mutation: Mutations::ShopLocaleEnable,
      description: "為本店啟用一個內容語言（67 §A.2）。"
    field :shop_locale_update, mutation: Mutations::ShopLocaleUpdate,
      description: "更新已啟用語言的發布狀態與排序。"
    field :shop_locale_disable, mutation: Mutations::ShopLocaleDisable,
      description: "停用一個內容語言（保留譯文）。"
  end
end
