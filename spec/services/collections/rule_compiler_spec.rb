# frozen_string_literal: true

require "rails_helper"

# 第 11 包：條件編譯器。逐型 SQL 形態＋注入安全（純編譯，不落庫的格不碰 DB）。
RSpec.describe Collections::RuleCompiler do
  # 純編譯測試不碰 DB，但 acts_as_tenant 連 Model.new 都要租戶 ⇒ 給一個未持久化的殼。
  around { |example| ActsAsTenant.with_tenant(Shop.new(id: 0)) { example.run } }

  # 不落庫的 source/rule 構造器（編譯器只讀屬性）。
  def source(inclusion_match: "all", exclusion_match: nil, rules: [])
    src = CollectionSource.new(inclusion_match:, exclusion_match:, source_type: "conditions")
    allow(src).to receive(:rules).and_return(rules)
    src
  end

  def rule(block: "inclusion", type:, relation:, text: nil, cents: nil, int: nil)
    CollectionSourceRule.new(block:, condition_type: type, relation:,
                             value_text: text, value_cents: cents, value_int: int)
  end

  describe "字串條件" do
    it "eq 是等值、contains 是 LIKE 子字串" do
      sql = described_class.where_sql(source(rules: [ rule(type: "product_title", relation: "eq", text: "Rose") ]))
      expect(sql).to include("p.title = 'Rose'")

      sql = described_class.where_sql(source(rules: [ rule(type: "product_title", relation: "contains", text: "玫瑰") ]))
      expect(sql).to include("p.title LIKE '%玫瑰%'")
    end

    it "🔴 注入面：條件值裡的引號被跳脫（值只能經綁定）" do
      sql = described_class.where_sql(source(rules: [
        rule(type: "product_vendor", relation: "eq", text: "O'Reilly'; DROP TABLE products;--")
      ]))
      expect(sql).to include("p.vendor = 'O\\'Reilly\\'; DROP TABLE products;--'")
      expect(sql).not_to match(/DROP TABLE(?!.*')/)   # 只存在於字串字面內
    end

    it "🔴 contains 的 % 與 _ 必須跳脫（商家輸入 50% 不得變萬用字元）" do
      sql = described_class.where_sql(source(rules: [
        rule(type: "product_title", relation: "contains", text: "50%")
      ]))
      expect(sql).to include("LIKE '%50\\\\%%'")
    end

    it "variant_title 走 EXISTS（變體層字串）" do
      sql = described_class.where_sql(source(rules: [ rule(type: "variant_title", relation: "eq", text: "50ml") ]))
      expect(sql).to include("EXISTS (SELECT 1 FROM product_variants v")
      expect(sql).to include("v.title = '50ml'")
    end
  end

  describe "🔴 tag 條件＝集合運算（13 §F4.3）" do
    it "includes ＝ tag_key 等值 EXISTS，**不是** LIKE" do
      sql = described_class.where_sql(source(rules: [ rule(type: "product_tag", relation: "includes", text: "Red_New") ]))
      expect(sql).to include("pt.tag_key = 'red-new'")   # 與寫入端同一支 Tags::Normalize
      expect(sql).not_to include("LIKE")
    end

    it "does_not_include ＝ NOT EXISTS" do
      sql = described_class.where_sql(source(rules: [ rule(type: "product_tag", relation: "does_not_include", text: "red") ]))
      expect(sql).to include("NOT EXISTS")
    end

    it "🔴 多 tag 條件（all）＝各自一個 EXISTS，不併 IN（IN＝OR 語義）" do
      sql = described_class.where_sql(source(rules: [
        rule(type: "product_tag", relation: "includes", text: "red"),
        rule(type: "product_tag", relation: "includes", text: "new")
      ]))
      expect(sql.scan("EXISTS (SELECT 1 FROM product_tags").length).to eq(2)
      expect(sql).not_to include("IN (")
    end
  end

  describe "金額與數值（任一變體基準——V-58 已結案的官方語義）" do
    it "variant_price 用 value_cents 對 price_cents（鐵律 3）" do
      sql = described_class.where_sql(source(rules: [ rule(type: "variant_price", relation: "gt", cents: 12_800) ]))
      expect(sql).to include("v.price_cents > ")
      expect(sql).to include("12800")
      expect(sql).not_to include("128.0")
    end

    it "缺 value_cents 一律 Unsupported（不收十進位字串的旁路）" do
      expect {
        described_class.where_sql(source(rules: [ rule(type: "variant_price", relation: "gt", text: "128.00") ]))
      }.to raise_error(described_class::Unsupported, /value_cents/)
    end

    it "🔴 compare_at 的 is_set＝**ALL variants**（NOT EXISTS 缺值變體），不是 any-variant" do
      sql = described_class.where_sql(source(rules: [ rule(type: "variant_compare_at_price", relation: "is_set") ]))
      expect(sql).to include("NOT EXISTS")
      expect(sql).to include("compare_at_price_cents IS NULL")
      # 還要求至少一個變體（無變體商品不匹配）。
      expect(sql.scan("EXISTS").length).to be >= 2
    end

    it "is_not_set＝存在缺值變體（any-variant，與其他數值條件同基準）" do
      sql = described_class.where_sql(source(rules: [ rule(type: "variant_compare_at_price", relation: "is_not_set") ]))
      expect(sql).to start_with("(EXISTS")
      expect(sql).to include("IS NULL")
    end

    it "variant_inventory＝跨倉合計對 value_int" do
      sql = described_class.where_sql(source(rules: [ rule(type: "variant_inventory", relation: "lt", int: 5) ]))
      expect(sql).to include("SUM(il.available)")
      # Rails 8.1 mysql2 adapter 對 Integer 也產生帶引號常量（實測 sanitize_sql_array
      # ["x > ?", 5] ⇒ "x > '5'"）；MySQL 對常量側只折算一次，語義與索引皆不受影響。
      expect(sql).to include("< '5'")
    end
  end

  describe "區塊語義（per-source 相減＝membership_formula）" do
    it "exclusion 併進 AND NOT (…)" do
      sql = described_class.where_sql(source(rules: [
        rule(type: "product_type", relation: "eq", text: "香水"),
        rule(block: "exclusion", type: "product_tag", relation: "includes", text: "clearance")
      ]))
      expect(sql).to include("AND NOT (")
    end

    it "inclusion any ⇒ OR；exclusion 預設 all ⇒ AND" do
      sql = described_class.where_sql(source(inclusion_match: "any", rules: [
        rule(type: "product_type", relation: "eq", text: "香水"),
        rule(type: "product_type", relation: "eq", text: "蠟燭"),
        rule(block: "exclusion", type: "product_tag", relation: "includes", text: "a"),
        rule(block: "exclusion", type: "product_vendor", relation: "eq", text: "X")
      ]))
      inclusion_part, exclusion_part = sql.split("AND NOT")
      expect(inclusion_part).to include(" OR ")
      expect(exclusion_part).to include(" AND ")
    end

    it "🔴 exclusion 區塊拒收 inclusion 專屬型別（值域是「哪個區塊有哪些欄位」）" do
      expect {
        described_class.where_sql(source(rules: [
          rule(type: "product_title", relation: "eq", text: "x"),
          rule(block: "exclusion", type: "variant_price", relation: "gt", cents: 1)
        ]))
      }.to raise_error(described_class::Unsupported, /exclusion 不支援 variant_price/)
    end

    it "空 inclusion ⇒ nil（該來源貢獻空集合，不是全集）" do
      expect(described_class.where_sql(source(rules: []))).to be_nil
      expect(described_class.where_sql(source(rules: [
        rule(block: "exclusion", type: "product_tag", relation: "includes", text: "a")
      ]))).to be_nil
    end
  end

  describe "fail-closed" do
    it "未知型別／未知 relation 一律 Unsupported，不靜默跳過" do
      expect {
        described_class.where_sql(source(rules: [ rule(type: "metafield_boolean", relation: "eq", text: "1") ]))
      }.to raise_error(described_class::Unsupported)
      expect {
        described_class.where_sql(source(rules: [ rule(type: "product_title", relation: "regex", text: "x") ]))
      }.to raise_error(described_class::Unsupported)
    end
  end

  describe "relations_for（runtime query 的資料源）" do
    it "每個 v1 支援型別都有非空 relation 集合與 default" do
      described_class::INCLUSION_TYPES.each do |type|
        expect(described_class.relations_for(type)).not_to be_empty, type
        expect(described_class.default_relation(type)).to be_present, type
      end
    end

    it "tripwire：RELATIONS 的鍵涵蓋全部 INCLUSION_TYPES ∪ EXCLUSION_TYPES" do
      expect(described_class::RELATIONS.keys)
        .to match_array((described_class::INCLUSION_TYPES + described_class::EXCLUSION_TYPES).uniq)
    end
  end

  describe "🔴 否定運算子的 NULL-guard（2026-08-26 審查 F1）" do
    it "not_eq／not_contains 對可空欄帶 OR IS NULL——未設定＝「不是那個值」" do
      # SQL 三值邏輯：`NULL <> 'x'`＝NULL ⇒ 沒有 guard 時未設定類型的商品被靜默剔除，
      # 而同功能的 tag does_not_include（NOT EXISTS）卻納入無標籤商品——兩個 is-not 打架。
      sql = described_class.where_sql(source(rules: [ rule(type: "product_type", relation: "not_eq", text: "香水") ]))
      expect(sql).to include("(p.product_type <> '香水' OR p.product_type IS NULL)")

      sql = described_class.where_sql(source(rules: [ rule(type: "product_vendor", relation: "not_contains", text: "acme") ]))
      expect(sql).to include("(p.vendor NOT LIKE '%acme%' OR p.vendor IS NULL)")
    end

    it "肯定運算子不帶 guard（NULL 不等於任何值＝正確不命中）" do
      sql = described_class.where_sql(source(rules: [ rule(type: "product_type", relation: "eq", text: "香水") ]))
      expect(sql).to include("p.product_type = '香水'")
      expect(sql).not_to include("IS NULL")
    end
  end

  describe "🔴 G2（2026-08-26 收斂輪）：可空數值欄的否定運算子同樣要 NULL-guard" do
    it "variant_compare_at_price 的 not_eq 帶 OR IS NULL" do
      # compare_at_price_cents 可空，且是編譯器涵蓋欄位中唯一「可空 × 允許 not_eq」的格。
      # 少了 guard，「比價不等於 X」會把沒設過比價的商品靜默剔除——與同檔的
      # is_not_set（把 NULL 當未設定納入）自相矛盾。
      sql = described_class.where_sql(source(rules: [
        rule(type: "variant_compare_at_price", relation: "not_eq", cents: 19_800)
      ]))
      # Integer 綁定產生帶引號常量＝本檔既有記載的 Rails 8.1 mysql2 行為（常量側折算一次）。
      expect(sql).to include("(v.compare_at_price_cents <> '19800' OR v.compare_at_price_cents IS NULL)")
    end

    it "比較型 relation（gt／lt）不帶 guard——NULL 不大於也不小於任何值" do
      sql = described_class.where_sql(source(rules: [
        rule(type: "variant_compare_at_price", relation: "gt", cents: 100)
      ]))
      expect(sql).to include("v.compare_at_price_cents > '100'")
      expect(sql).not_to include("IS NULL")
    end
  end
end
