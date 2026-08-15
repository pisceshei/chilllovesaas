# frozen_string_literal: true

require "rails_helper"

# `Types::MutationType` 建了但**刻意沒有掛上** `ChillloveSchema`。
#
# 🔴 這一檔存在的理由：一個「刻意沒做」的東西，如果沒有測試釘住，
# 下一輪就會被當成漏做而順手補上——而補上它的人不會知道
# `enforce_idempotency_contract!` **只檢查 key 有沒有帶、不做去重**。
# 本 PR 一支 mutation 都不出，所以沒有任何東西獲得虛假的安全感；
# 掛上 root 的那一刻這個保護就沒了。
RSpec.describe "Mutation root 尚未啟用" do
  it "ChillloveSchema 沒有 mutation root" do
    expect(ChillloveSchema.mutation).to be_nil
  end

  it "schema SDL 不含 Mutation 型別，也不含 clientMutationId" do
    sdl = ChillloveSchema.to_definition
    expect(sdl).not_to include("type Mutation")
    expect(sdl).not_to include("clientMutationId")
  end

  it "Types::MutationType 本身是空的（掛上去之前要先補 claim/replay）" do
    expect(Types::MutationType.fields).to be_empty
  end

  # 解鎖條件寫進斷言，讓改動它的人一定會讀到。
  it "解鎖條件：第一支真 mutation 落地時，同批處理 claim/replay" do
    source = File.read(Rails.root.join("app/graphql/types/mutation_type.rb"), encoding: "UTF-8")
    expect(source).to include("claim/replay")
    expect(source).to include("虛假的安全感")
  end
end
