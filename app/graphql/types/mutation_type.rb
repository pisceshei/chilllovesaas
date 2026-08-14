# GraphQL schema type 的 namespace。
module Types
  # Admin GraphQL 的 mutation root。
  #
  # 🔴 **本型別目前是空的，而且刻意沒有掛上 `ChillloveSchema`**（見 `mutation_root_guard_spec`）。
  #
  # 為什麼建了卻不掛：本 PR 交付的是**寫入路徑的地基**（`BaseMutation`／
  # `DisplayableError`／錯誤碼池／`UserErrors::Path`／冪等清單讀取器），
  # 一支具體的 mutation 都不出。掛一個空的 mutation root 上去會讓 schema
  # 多出一個 `Mutation` 型別而裡面什麼都沒有——對客戶端是雜訊，
  # 對之後的人是「看起來已經可以寫 mutation 了」的錯誤訊號。
  #
  # 🔴 更重要的是：`BaseMutation#enforce_idempotency_contract!` **只檢查 key 有沒有帶，
  # 不做去重**。claim/replay 狀態機刻意延後（四個未決點見
  # `docs/worklog/2026-08-15-mutation寫入地基.md`）。**本 PR 一支 mutation 都不出，
  # 所以沒有任何東西會因此獲得虛假的安全感**——這是「不掛 root」的實質理由。
  #
  # 掛上去的條件：第一支真正的 mutation 落地時，同批處理 claim/replay。
  #
  # @see docs/research/28-api-contract.md §0.3.3
  class MutationType < BaseObject
    graphql_name "Mutation"
    description "Admin API 的寫入入口（尚未啟用）。"

    # graphql-ruby 對「沒有欄位的 object type」會警告，並預告未來版本改成 raise。
    # 明示宣告，而不是靠「反正沒掛上 schema 所以不會被驗證」——
    # 那個前提在有人把它掛上去的那一刻就不成立了。
    has_no_fields(true)
  end
end
