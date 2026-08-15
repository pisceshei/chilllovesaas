# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/mutation_test_schema")

# 🔴 本檔的每一條都**真的 execute 一次**。
# 上一輪 review 抓到的第一條致命傷（`input_object_class` 在 `GraphQL::Schema::Mutation`
# 上不存在 ⇒ 類別定義期 NoMethodError）是「跑一次就會發現」的形態——
# 只讀程式碼的驗收抓不到它。
RSpec.describe Mutations::BaseMutation do
  let(:shop) { create(:shop) }

  def run(query, variables: {})
    MutationTestSchema::Schema.execute(query, variables:, context: { current_shop: shop }).to_h
  end

  describe "schema 形狀與本尊一致" do
    let(:sdl) { MutationTestSchema::Schema.to_definition }

    # 🔴 本尊的 Admin GraphQL 沒有 clientMutationId（payload 與 input 兩側都沒有）。
    # 繼承 RelayClassicMutation 會自動注入它 —— 這條斷言就是那個選擇的守衛。
    it "沒有 clientMutationId（不得繼承 RelayClassicMutation）" do
      expect(sdl).not_to include("clientMutationId")
      expect(described_class.ancestors).not_to include(GraphQL::Schema::RelayClassicMutation)
    end

    it "userErrors 是 [X!]!（非空 list of 非空）" do
      expect(sdl).to match(/userErrors: \[FixtureUserError!\]!/)
    end

    it "field 是 [String!]（list 可 null、元素非 null）" do
      expect(sdl).to match(/field: \[String!\]\n/)
    end

    it "message 是 String!" do
      expect(sdl).to match(/message: String!/)
    end

    # 🔴 本尊的 DisplayableError interface 只有兩個欄位，沒有 code。
    it "DisplayableError interface 與本尊一字不差：只有 field 與 message" do
      expect(Types::Interfaces::DisplayableError.fields.keys).to contain_exactly("field", "message")
    end
  end

  describe "payload 的 resource 欄位數量" do
    it "一般 mutation：resource ＋ userErrors" do
      payload = run(<<~GQL)
        mutation { fixtureWidgetCreate(title: "有標題") { widget { title } userErrors { field message code } } }
      GQL
      data = payload.dig("data", "fixtureWidgetCreate")
      expect(data.fetch("widget")).to eq({ "title" => "有標題" })
      expect(data.fetch("userErrors")).to eq([])
    end

    # 🔴 本尊 payload 的 resource 欄位數量**下限是 0**。
    # 這一條證明 BaseMutation 沒有把「一個 resource ＋ userErrors」寫死成契約。
    it "純副作用 mutation：payload 只有 userErrors" do
      payload = run('mutation { fixtureWidgetTouch(id: "ok") { userErrors { field message } } }')
      expect(payload["errors"]).to be_nil
      expect(payload.dig("data", "fixtureWidgetTouch", "userErrors")).to eq([])
    end
  end

  describe "userErrors 的形狀" do
    it "成功時是空陣列，不是 null" do
      payload = run('mutation { fixtureWidgetTouch(id: "ok") { userErrors { message } } }')
      expect(payload.dig("data", "fixtureWidgetTouch", "userErrors")).to eq([])
      expect(payload.dig("data", "fixtureWidgetTouch", "userErrors")).not_to be_nil
    end

    it "業務錯誤時 HTTP 層沒有 top-level errors（鐵律 4 第一層）" do
      payload = run('mutation { fixtureWidgetCreate(title: "  ") { userErrors { field message code } } }')
      expect(payload["errors"]).to be_nil
      expect(payload.dig("data", "fixtureWidgetCreate", "userErrors")).to eq(
        [ { "field" => [ "title" ], "message" => "標題不得為空白", "code" => "BLANK" } ]
      )
    end

    # 🔴 無法歸屬到欄位時是 null 不是 []（官方 draftOrderComplete 的範例逐字 "field": null）。
    it "無法歸屬的錯誤 field 為 null，不是空陣列" do
      payload = run('mutation { fixtureWidgetTouch(id: "bad") { userErrors { field message code } } }')
      error = payload.dig("data", "fixtureWidgetTouch", "userErrors", 0)
      expect(error.fetch("field")).to be_nil
      expect(error.fetch("code")).to eq("NOT_FOUND")
    end

    # 🔴 陣列索引是十進位裸字串段，平鋪在同一個一維陣列。
    it "陣列元素錯誤帶十進位索引段" do
      payload = run(<<~GQL)
        mutation { fixtureWidgetBulk(titles: ["ok", "", "also ok", ""]) { userErrors { field message } } }
      GQL
      fields = payload.dig("data", "fixtureWidgetBulk", "userErrors").map { |e| e.fetch("field") }
      expect(fields).to eq([ %w[titles 1 value], %w[titles 3 value] ])
    end
  end

  describe "錯誤碼 enum" do
    it "共用池的值全部可用，且各 mutation 是獨立的 enum type" do
      values = MutationTestSchema::ErrorCode.values.keys
      expect(values).to include(*Types::Errors::CodePools::COMMON.map(&:to_s))
      expect(values).to include(*Types::Errors::CodePools::CONCURRENCY.map(&:to_s))
      expect(values).to include("FIXTURE_ONLY")
    end

    # 🔴 CONFLICT 是折扣線專屬的輸入驗證碼，不是樂觀鎖碼（63 §L-3 以相反方向結案）。
    it "CONFLICT 不在共用池裡" do
      expect(MutationTestSchema::ErrorCode.values.keys).not_to include("CONFLICT")
      expect(Types::Errors::CodePools.shared).not_to include(:CONFLICT)
      expect(Types::Errors::CodePools::CONCURRENCY).to include(:STALE_OBJECT)
    end

    it "每個值都有中文說明（schema 是給人讀的）" do
      expect(MutationTestSchema::ErrorCode.values.values.map(&:description)).to all(be_present)
    end
  end

  describe "冪等契約檢查" do
    # 🔴 這個方法**只檢查 key 有沒有帶，不做去重**。
    # 斷言寫在這裡是為了讓下一支 mutation 的作者看到它的限度。
    it "不在強制清單裡的 mutation 不要求 key" do
      expect(MutationTestSchema::WidgetCreate.idempotency_required?).to be(false)
    end

    it "在強制清單裡的 mutation 缺 key ⇒ top-level errors 帶 IDEMPOTENCY_KEY_REQUIRED" do
      allow(MutationTestSchema::WidgetIdempotent).to receive(:idempotency_required?).and_return(true)

      payload = run("mutation { fixtureWidgetIdempotent { userErrors { message } } }")

      # 🔴 缺 key 是**契約違反**不是業務錯誤 ⇒ 走 top-level errors 而不是 userErrors。
      expect(payload.dig("errors", 0, "message")).to match(/必須提供 idempotencyKey/)
      expect(payload.dig("errors", 0, "extensions", "code")).to eq("IDEMPOTENCY_KEY_REQUIRED")
    end

    it "在強制清單裡的 mutation 有帶 key ⇒ 正常通過" do
      allow(MutationTestSchema::WidgetIdempotent).to receive(:idempotency_required?).and_return(true)

      payload = run('mutation { fixtureWidgetIdempotent(idempotencyKey: "k-1") { userErrors { message } } }')

      expect(payload["errors"]).to be_nil
      expect(payload.dig("data", "fixtureWidgetIdempotent", "userErrors")).to eq([])
    end

    it "清單來自 limits.yml，不是程式碼裡的第二份" do
      expect(Idempotency::RequiredMutations.all).to eq(Limits.fetch(:idempotency, :required_for).map(&:to_s))
      expect(Idempotency::RequiredMutations.required?("refundCreate")).to be(true)
      expect(Idempotency::RequiredMutations.required?("productCreate")).to be(false)
    end
  end
end
