# frozen_string_literal: true

require "spec_helper"
require "yaml"

# PR-1 的 schema 對齊：對**原始碼**（migration 與 schema.rb）做不變量斷言，
# 與 `spec/models/product_variant_spec.rb` 對**執行期資料庫**的斷言互補。
#
# 為什麼兩邊都要：執行期斷言證明「現在這個 DB 是對的」，原始碼斷言證明
# 「任何人重跑一次 migration 也會得到同一個 DB」。M0 的
# `spec/migrations/m0_core_schema_spec.rb` 是同一個形態。
RSpec.describe "PR-1 schema alignment source invariants" do
  ROOT = File.expand_path("../..", __dir__)
  SKU_MIGRATION = "db/migrate/20260815000000_relax_product_variant_sku_index.rb"

  # 🔴 `uq_product_variants_sku` **唯一的合法出現處**＝上面那支 migration 的 `down`
  # （回滾必須重建它，否則 migration 不可逆）。掃全庫時必須明列排除它，
  # 否則這條斷言會被它要保護的那支 migration 自己判紅——而實作者最省事的修法
  # 是把斷言縮成「只掃 db/schema.rb」，於是「防止有人在別處重建」這個守備範圍
  # 在第一天就被拆掉，且拆掉的理由不會出現在任何 worklog 裡。
  # （比照 `scripts/check-tenant-isolation.rb` 的白名單形態：排除清單用具名常數，
  #   改動它一定會出現在 diff 裡。）
  #
  # 🔴 逐項寫理由，不寫「測試檔一律排除」——那樣的話有人在 factory 裡
  # 重建唯一索引就掃不到了。每一項都必須是「提到它是為了證明它不該存在」。
  UQ_SKU_ALLOWED_PATHS = {
    SKU_MIGRATION => "down 必須重建它，否則 migration 不可逆",
    "spec/migrations/pr1_schema_alignment_spec.rb" => "本檔，斷言它不得出現",
    "spec/models/product_variant_spec.rb" => "斷言執行期 DB 不再有這個索引名"
  }.freeze

  describe "SKU 索引降級（63 §L-1 / limits.yml:2504）" do
    let(:schema) { File.read(File.join(ROOT, "db/schema.rb"), encoding: "UTF-8") }
    let(:migration) { File.read(File.join(ROOT, SKU_MIGRATION), encoding: "UTF-8") }

    it "db/schema.rb 的 product_variants 帶非唯一的 ix_product_variants_sku" do
      block = schema[/create_table "product_variants".*?\n  end\n/m]
      expect(block).not_to be_nil
      expect(block).to include(%(t.index ["shop_id", "sku"], name: "ix_product_variants_sku"))
      expect(block).not_to include("uq_product_variants_sku")
    end

    it "db/schema.rb 全檔不得再出現 uq_product_variants_sku" do
      expect(schema).not_to include("uq_product_variants_sku")
    end

    it "全庫只有那支 migration 的 down 可以提到 uq_product_variants_sku" do
      hits = Dir.glob(File.join(ROOT, "{app,lib,db,spec,scripts,config}/**/*.{rb,yml,yaml}"))
                .reject { |path| path.include?("node_modules") }
                .select { |path| File.read(path, encoding: "UTF-8").include?("uq_product_variants_sku") }
                .map { |path| path.delete_prefix("#{ROOT}/").tr("\\", "/") }

      unexpected = hits - UQ_SKU_ALLOWED_PATHS.keys
      expect(unexpected).to be_empty,
        "以下檔案重新引入了 uq_product_variants_sku：#{unexpected.join(', ')}"
    end

    it "白名單裡的每一個路徑都真的存在（防止清單腐化成願景清單）" do
      # 🔴 這條的由來：CLAUDE.md 鐵律 2 的組織層白名單曾經寫成「還沒建的表」，
      # 於是規則與 CI 腳本各跑各的。白名單是**安全邊界**，它必須寫實際存在的東西。
      missing = UQ_SKU_ALLOWED_PATHS.keys.reject { |path| File.exist?(File.join(ROOT, path)) }
      expect(missing).to be_empty, "白名單指向不存在的檔案：#{missing.join(', ')}"
    end

    it "migration 的 down 確實重建唯一索引（可逆性）" do
      down = migration[/def down.*?\n  end\n/m]
      expect(down).to include(%(name: "uq_product_variants_sku", unique: true))
    end

    it "不包 safety_assured（strong_migrations 的索引檢查只在 PostgreSQL 上 raise）" do
      # 覆核依據：strong_migrations 2.8.0 的 check_add_index / check_remove_index
      # 兩個 raise 分支都在 `postgresql?` 之內；我方是 MySQL 8 ⇒ 不需要 safety_assured。
      # 🔴 反過來說，**用到 `execute` 的 migration 一定要包**（check_execute 是無條件 raise）。
      expect(migration).not_to include("safety_assured")
    end
  end

  describe "limits.yml 與實作一致" do
    let(:limits) { YAML.safe_load_file(File.join(ROOT, "config/limits.yml"), aliases: true) }

    # 🔴 鍵在 `catalog_flow:` 底下不是 `product:` 底下——我第一版猜成 `product`，
    # 斷言拿到 nil 而不是 false，**而 `nil` 與 `false` 在「不是唯一」這件事上讀起來一樣**。
    # 這正是鐵律 6 要防的：引用上限值時猜路徑，猜錯了看起來還像對的。
    it "sku_unique_per_shop 宣告為 false（本 PR 讓實作追上這條既有宣告）" do
      expect(limits.dig("catalog_flow", "sku_unique_per_shop")).to be(false)
      expect(limits.dig("catalog_flow", "sku_owner")).to eq("inventory_item")
      expect(limits.dig("catalog_flow", "sku_duplicate_action")).to eq("warn_not_block")
    end
  end

  describe "docs/specs/11 的 SKU 例子已修（63 §L-1）" do
    let(:baseline) { File.read(File.join(ROOT, "docs/specs/11-production-baseline.md"), encoding: "UTF-8") }

    it "§2 第 1 點與 §3 第 3 點都不再把 SKU 當唯一索引的例子" do
      # 只檢查「主文」——批註裡逐字引用原文是刻意的（防回退），不算違反。
      body = baseline.gsub(/<!--.*?-->/m, "")
      expect(body).not_to match(/唯一性（[^）]*SKU/)
      expect(body).not_to match(/擋住重複（[^）]*SKU/)
    end
  end
end
