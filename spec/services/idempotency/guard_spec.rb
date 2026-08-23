# frozen_string_literal: true

require "rails_helper"

# Guard 狀態機的單元層（request spec 只走 middleware 路徑，ambient tenant 恆等於
# shop 參數；本檔覆蓋 11 §2.1(b) 表中 request 層測不到／未測的分支——
# 對抗審查 confirmed #1／#14）。
RSpec.describe Idempotency::Guard do
  let(:shop) { create(:shop) }

  def run(key:, input: { "t" => "1" }, mutation_name: "ProductSet", &block)
    described_class.with(shop:, key:, mutation_name:, input:, &block)
  end

  def sole_record
    ActsAsTenant.with_tenant(shop) { IdempotencyKey.sole }
  end

  it "首跑成功：succeeded 與 result_ref 落款" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    outcome = run(key: "k1") { [ product, [] ] }

    expect(outcome).to eq({ replayed: false, resource: product, user_errors: [] })
    expect(sole_record).to have_attributes(
      state: "succeeded", resource_type: "Product", resource_id: product.id
    )
  end

  it "同 key 用於不同 mutation ⇒ IDEMPOTENCY_KEY_PARAMETER_MISMATCH" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    run(key: "k1") { [ product, [] ] }

    expect { run(key: "k1", mutation_name: "OtherMutation") { raise "不該執行" } }
      .to raise_error(described_class::Conflict) { |conflict|
        expect(conflict.code).to eq("IDEMPOTENCY_KEY_PARAMETER_MISMATCH")
      }
  end

  it "過 expires_at ⇒ 視為全新操作（舊列讓位、重新執行）" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    run(key: "k1") { [ product, [] ] }
    sole_record.update!(expires_at: 1.minute.ago)

    executed = false
    outcome = run(key: "k1") { executed = true; [ product, [] ] }

    expect(executed).to be(true)
    expect(outcome[:replayed]).to be(false)
    expect(sole_record.state).to eq("succeeded")
  end

  it "回放不信 ambient tenant：外層在別店 context 下仍以 shop 參數查回本店商品" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    run(key: "k1") { [ product, [] ] }

    other_shop = create(:shop)
    outcome = ActsAsTenant.with_tenant(other_shop) do
      run(key: "k1") { raise "不該執行（應回放）" }
    end

    # 依賴 ambient 的實作會在 other_shop scope 下查回 nil 而誤判「商品已刪」。
    expect(outcome).to eq({ replayed: true, resource: product, user_errors: [] })
  end

  it "回放時 result_ref 物件已刪 ⇒ resource 為 nil（呼叫端轉 NOT_FOUND）" do
    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    run(key: "k1") { [ product, [] ] }
    ActsAsTenant.with_tenant(shop) { product.destroy! }

    outcome = run(key: "k1") { raise "不該執行" }
    expect(outcome).to eq({ replayed: true, resource: nil, user_errors: [] })
  end

  # 🔴 Guard 外層 transaction 的部分寫入回滾釘（自查抓到的孤兒列事故形）：
  # block 內先寫了資料、之後回 userErrors——那筆資料必須被回滾，
  # 不得被外層 commit 成孤兒。
  it "業務失敗時 block 內的部分寫入被回滾（不留孤兒列）" do
    outcome = run(key: "k1") do
      ActsAsTenant.with_tenant(shop) do
        Product.create!(title: "孤兒候選", handle: "orphan-candidate",
                        description_html: "", status: "draft")
      end
      [ nil, [ { field: nil, message: "業務失敗", code: "INVALID" } ] ]
    end

    expect(outcome[:user_errors]).not_to be_empty
    expect(sole_record.state).to eq("failed")
    ActsAsTenant.with_tenant(shop) do
      expect(Product.where(handle: "orphan-candidate")).not_to exist
    end
  end

  it "block 拋例外 ⇒ 記 failed 並原樣拋出；同 key 可重試" do
    expect { run(key: "k1") { raise ArgumentError, "boom" } }
      .to raise_error(ArgumentError, "boom")
    expect(sole_record.state).to eq("failed")

    product = ActsAsTenant.with_tenant(shop) { create(:product, shop:) }
    outcome = run(key: "k1") { [ product, [] ] }
    expect(outcome[:replayed]).to be(false)
    expect(sole_record.state).to eq("succeeded")
  end
end
