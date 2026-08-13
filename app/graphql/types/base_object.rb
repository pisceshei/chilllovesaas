# GraphQL schema type 的 namespace。
module Types
  # CHILL LOVE GraphQL output type 的抽象基底。
  #
  # 子類只宣告 API contract，不直接跨 tenant 查資料。見
  # docs/research/28 §0.2–0.3、docs/specs/12 F4。
  class BaseObject < GraphQL::Schema::Object
  end
end
