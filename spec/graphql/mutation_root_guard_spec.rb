# frozen_string_literal: true

require "rails_helper"

# mutation root 的形狀守衛（2026-08-23 由「刻意未掛」反轉為「已掛載」）。
#
# 掛載的解鎖條件——「第一支真正的 mutation 落地時，同批處理 claim/replay」——
# 已由 PR（productSet ＋ Idempotency::Guard ＋ 表形對齊遷移）滿足；
# 本檔改守掛載後**不得回退**的形狀。
RSpec.describe "Mutation root" do
  it "已掛上 schema（claim/replay 同批落地後的狀態）" do
    expect(ChillloveSchema.mutation).to eq(Types::MutationType)
  end

  it "SDL 含 Mutation 型別與 productSet 欄位" do
    sdl = ChillloveSchema.to_definition
    expect(sdl).to include("type Mutation")
    expect(sdl).to include("productSet(")
  end

  # 🔴 這條從未掛載時期**原樣保留**：不得繼承 RelayClassicMutation——
  # 本尊 Admin API 沒有 clientMutationId，schema 形狀是客戶端寫死的東西。
  it "SDL 不含 clientMutationId（不得用 RelayClassicMutation）" do
    expect(ChillloveSchema.to_definition).not_to include("clientMutationId")
  end

  it "mutation root 的每個欄位都有對應的 Mutations:: resolver" do
    Types::MutationType.fields.each_value do |field|
      expect(field.mutation).to be < Mutations::BaseMutation
    end
  end
end
