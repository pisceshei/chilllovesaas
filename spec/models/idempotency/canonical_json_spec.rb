# frozen_string_literal: true

require "rails_helper"

# 五條規則（11 §2.1(d)）各至少一條斷言，並各配一條**反向**斷言
# ——「規則生效」與「規則沒有過度生效」是兩件事。
RSpec.describe Idempotency::CanonicalJson do
  describe "① 物件 key 遞迴字典序排序" do
    it "頂層欄位順序不影響指紋" do
      a = { title: "T", handle: "h", status: "draft" }
      b = { status: "draft", title: "T", handle: "h" }
      expect(described_class.fingerprint(a)).to eq(described_class.fingerprint(b))
    end

    it "巢狀欄位順序也不影響（遞迴）" do
      a = { product: { title: "T", seo: { title: "S", description: "D" } } }
      b = { product: { seo: { description: "D", title: "S" }, title: "T" } }
      expect(described_class.fingerprint(a)).to eq(described_class.fingerprint(b))
    end

    it "Symbol 與 String 鍵視為同一個" do
      expect(described_class.fingerprint({ title: "T" })).to eq(described_class.fingerprint({ "title" => "T" }))
    end

    # 反向：值不同就一定不同指紋（排序不得把不同請求算成同一個）
    it "值不同 ⇒ 指紋不同" do
      expect(described_class.fingerprint({ title: "A" })).not_to eq(described_class.fingerprint({ title: "B" }))
    end
  end

  describe "② 移除 null 欄位（「沒傳」與「傳 null」是同一件事）" do
    it "顯式 null 與省略等價" do
      expect(described_class.fingerprint({ title: "T", vendor: nil }))
        .to eq(described_class.fingerprint({ title: "T" }))
    end

    it "巢狀的 null 也移除" do
      expect(described_class.fingerprint({ seo: { title: "S", description: nil } }))
        .to eq(described_class.fingerprint({ seo: { title: "S" } }))
    end

    # 反向：空字串不是 null，不得被移除
    it "空字串與 null 不等價" do
      expect(described_class.fingerprint({ vendor: "" }))
        .not_to eq(described_class.fingerprint({ vendor: nil }))
    end

    # 反向：false 不是 null
    it "false 與 null 不等價" do
      expect(described_class.fingerprint({ taxable: false }))
        .not_to eq(described_class.fingerprint({ taxable: nil }))
    end
  end

  describe "③ 陣列保持原順序（🔴 順序有語義）" do
    it "順序不同 ⇒ 指紋不同" do
      a = { variants: [ { sku: "A" }, { sku: "B" } ] }
      b = { variants: [ { sku: "B" }, { sku: "A" } ] }
      expect(described_class.fingerprint(a)).not_to eq(described_class.fingerprint(b))
    end

    it "陣列元素內部的 key 仍然排序" do
      a = { variants: [ { sku: "A", price: 100 } ] }
      b = { variants: [ { price: 100, sku: "A" } ] }
      expect(described_class.fingerprint(a)).to eq(described_class.fingerprint(b))
    end
  end

  describe "④ 數字一律整數 cents（鐵律 3）" do
    it "遇到 Float 直接 raise——那代表上游漏了單位邊界" do
      expect { described_class.fingerprint({ price: 14.80 }) }
        .to raise_error(TypeError, /浮點數/)
    end

    it "巢狀的 Float 也 raise" do
      expect { described_class.fingerprint({ variants: [ { price: 1.0 } ] }) }
        .to raise_error(TypeError, /浮點數/)
    end

    it "整數正常" do
      expect { described_class.fingerprint({ price_cents: 148_000 }) }.not_to raise_error
    end

    # 負數是合法的（65 §A.7：型別層不驗正負）
    it "負整數不 raise（退款差額、撤銷）" do
      expect { described_class.fingerprint({ amount_cents: -500 }) }.not_to raise_error
    end
  end

  describe "⑤ 不含 idempotencyKey 本身" do
    it "camelCase 與 snake_case 兩種寫法都排除" do
      base = described_class.fingerprint({ title: "T" })
      expect(described_class.fingerprint({ title: "T", idempotencyKey: "k-1" })).to eq(base)
      expect(described_class.fingerprint({ title: "T", idempotency_key: "k-2" })).to eq(base)
    end

    # 🔴 反向：若沒排除，指紋會恆等於自己，永遠偵測不到參數不符。
    it "換一把 key、其餘參數相同 ⇒ 指紋相同（這正是偵測 mismatch 的前提）" do
      expect(described_class.fingerprint({ title: "T", idempotencyKey: "k-1" }))
        .to eq(described_class.fingerprint({ title: "T", idempotencyKey: "k-2" }))
    end

    it "同一把 key、參數不同 ⇒ 指紋不同（可偵測 mismatch）" do
      expect(described_class.fingerprint({ title: "A", idempotencyKey: "k" }))
        .not_to eq(described_class.fingerprint({ title: "B", idempotencyKey: "k" }))
    end

    # 巢狀的同名欄位**不排除**——它不是那個 key。
    it "巢狀的 idempotencyKey 欄位不排除（它不是頂層那把 key）" do
      expect(described_class.fingerprint({ meta: { idempotencyKey: "x" } }))
        .not_to eq(described_class.fingerprint({ meta: {} }))
    end
  end

  describe "指紋格式" do
    it "是 64 字元的十六進位字串（對得上 request_digest CHAR(64)）" do
      expect(described_class.fingerprint({ a: 1 })).to match(/\A[0-9a-f]{64}\z/)
    end
  end
end
