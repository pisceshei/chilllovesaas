# frozen_string_literal: true

# 包 32：Markets 資料層四表＋market_regions（docs/research/29 §1.4；docs/specs/67 §C.8）。
#
# 表清單與六步方案（docs/plans/2026-08-31-W6下半與結帳線-六步方案.md 步 1）的「四表」對照：
#   markets／market_web_presences／market_web_presence_locales／domains ＝ 工作卡四表；
#   `market_regions` 是第五張——29 §1.4 明列它獨立成表（unique [market_id, country_code]），
#   且 `url_prefix()` 的 `region_of(market)` 與 lineage 推導都要讀它，缺了四表就接不起來。
#
# 🔴 鐵律 2：五張全是業務資料，全帶 shop_id、複合索引以 shop_id 開頭。
# 🔴 「恰一個」不變量一律用**生成欄位＋唯一索引**模擬部分唯一索引
#    （同 shop_locales.source_guard 的手法，67 §C.8(b) 明文指定）：
#      markets.primary_guard      —— 每店恰一個 primary market（29 §1.1「不可刪除」在 model 層擋）
#      domains.primary_guard      —— 每店恰一個 primary domain（實測：Domains 列表恰一個 Primary 徽章）
#      mwpl.default_guard         —— 每個 presence 恰一個預設 locale（67 §C.8(b)）
class CreateMarketsFoundation < ActiveRecord::Migration[8.1]
  def change
    create_table :markets, comment: "市場（29 §1.1）：conditions 決定命中；parent 由推導不由欄位" do |t|
      t.bigint :shop_id, null: false
      t.string :name, null: false
      t.string :handle, limit: 255, null: false
      t.string :status, limit: 16, null: false, default: "active",
               comment: "active|draft（實測 2026-08-31：New market 表單原生 select 恰兩值 DRAFT/ACTIVE）"
      t.string :market_type, limit: 32, null: false, default: "region",
               comment: "region|company_location|location|channel|none（29 §1.1 MarketType；" \
                        "實測 Market conditions 四類＝Regions/POS locations/Company locations/Channels）"
      t.boolean :is_primary, null: false, default: false,
                comment: "primary market：恰含一國、不可刪（29 §1.1）。29 原文欄名 primary＝MySQL 保留字，改 is_primary"
      t.bigint :derived_parent_market_id,
               comment: "🔴 推導快取不是權威欄位（29 §1.5(a)）：conditions 變更即重算；不得手動指定"
      t.virtual :primary_guard, type: :integer, as: "if(`is_primary`,1,NULL)", stored: true
      t.timestamps

      t.index %i[shop_id handle], unique: true, name: "uq_markets_handle"
      t.index %i[shop_id primary_guard], unique: true, name: "uq_markets_single_primary"
      t.index %i[shop_id status], name: "ix_markets_status"
      t.index %i[shop_id id], unique: true, name: "uq_markets_tenant_id"
    end

    create_table :market_regions, comment: "市場的 region conditions（29 §1.4）：active 市場不得重疊（model 層驗證）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :market_id, null: false
      t.string :country_code, limit: 2, null: false, comment: "ISO 3166-1 alpha-2，大寫"
      t.timestamps

      t.index %i[shop_id market_id country_code], unique: true, name: "uq_market_regions_country"
      t.index %i[shop_id country_code], name: "ix_market_regions_by_country",
              comment: "「這個國家屬於哪些市場」——active 重疊驗證與 buyer 命中都走這裡"
    end

    create_table :domains, comment: "網域（實測 2026-08-31 Settings→Domains）：host→shop 解析的權威表（步 2 消費）" do |t|
      t.bigint :shop_id, null: false
      t.string :host, limit: 253, null: false, comment: "小寫 FQDN，不含 scheme／port"
      t.string :domain_type, limit: 16, null: false, default: "primary",
               comment: "primary|redirect|alias（實測 Change domain type 對話恰三值，逐字 Primary/Redirecting/Alias domain）"
      t.string :status, limit: 16, null: false, default: "active",
               comment: "pending|active（本尊列表 Status=Connected；DNS 驗證 ops 隨 bt3 配套，v1 先兩值）"
      t.virtual :primary_guard, type: :integer, as: "if(`domain_type` = _utf8mb4'primary',1,NULL)", stored: true
      t.timestamps

      # 🔴 host 全域唯一（**不**以 shop_id 開頭是刻意的）：兩家店不得認領同一 host，
      #    且步 2 的 host→shop 解析正是用這條索引反查租戶——它是跨租戶入口，不是租內查詢。
      t.index [ :host ], unique: true, name: "uq_domains_host"
      t.index %i[shop_id primary_guard], unique: true, name: "uq_domains_single_primary"
      t.index %i[shop_id id], unique: true, name: "uq_domains_tenant_id"
    end

    create_table :market_web_presences,
                 comment: "市場的網站呈現（29 §1.2）：domain XOR subfolder；沿 lineage 累加繼承（additive）" do |t|
      t.bigint :shop_id, null: false
      t.bigint :market_id, null: false
      t.bigint :domain_id, comment: "獨立網域／子網域策略時指向 domains；與 subfolder_suffix 互斥"
      t.string :subfolder_suffix, limit: 8,
               comment: "子資料夾策略的識別字（小寫）；多國市場它兼任前綴 region 來源（67 §F.1(b-2) 暫案 C，V-225）"
      t.string :default_shop_locale, limit: 35, null: false,
               comment: "該 presence 的預設 locale（29 §1.4 欄名沿用）；mwpl.is_market_default 與它同一真相（67 §C.8(b)）"
      t.timestamps

      t.index %i[shop_id market_id], name: "ix_mwp_market"
      t.index %i[shop_id domain_id subfolder_suffix], name: "ix_mwp_domain_suffix"
      t.index %i[shop_id id], unique: true, name: "uq_mwp_tenant_id"
      # 29 §1.2 的 XOR（check constraint 明文）：恰一邊有值。
      t.check_constraint "(`domain_id` IS NULL) <> (`subfolder_suffix` IS NULL)", name: "ck_mwp_domain_xor_subfolder"
    end

    create_table :market_web_presence_locales,
                 comment: "per-market 語言白名單（67 §C.8）。🔴 粒度是 presence 不是 market：" \
                          "市場的開放語言＝resolved presences 的聯集，任何 UPDATE ... WHERE market_id 形態的寫入都是 bug" do |t|
      t.bigint :shop_id, null: false
      t.bigint :market_web_presence_id, null: false
      t.string :locale_tag, limit: 35, null: false
      t.integer :position, null: false, default: 0, comment: "切換器顯示順序（商家唯一的排序控制點，鐵律 7）"
      t.boolean :is_market_default, null: false, default: false,
                comment: "＝(locale_tag == presence.default_shop_locale)；為進複合唯一索引而物化（67 §C.8(b)）"
      t.boolean :open_to_buyers, null: false, default: true, comment: "白名單開關本身（67 §A.5）"
      t.datetime :closed_at, comment: "關閉時點——關閉是狀態轉換不是刪除（67 §C.8：404 與失效掛鉤要用）"
      t.virtual :default_guard, type: :integer, as: "if(`is_market_default`,1,NULL)", stored: true
      t.timestamps

      t.index %i[shop_id market_web_presence_id locale_tag], unique: true, name: "uq_mwpl_locale"
      t.index %i[shop_id locale_tag], name: "ix_mwpl_by_locale",
              comment: "「這個語言開給了哪些市場」（關語言前的影響評估，67 §C.8）"
      t.index %i[shop_id market_web_presence_id default_guard], unique: true, name: "uq_mwpl_single_default"
    end

    # 新建空表上的 FK：無既有列可驗（倉內慣例同 price_lists／carts 遷移）。
    safety_assured do
      add_foreign_key :markets, :shops, name: "fk_markets_shop"
      add_foreign_key :market_regions, :markets, column: :market_id,
                                                 name: "fk_market_regions_market", on_delete: :cascade
      add_foreign_key :domains, :shops, name: "fk_domains_shop"
      add_foreign_key :market_web_presences, :markets, column: :market_id,
                                                       name: "fk_mwp_market", on_delete: :cascade
      # 網域被 presence 引用時不得刪（restrict）：先改 presence 再刪網域，不做靜默連鎖。
      add_foreign_key :market_web_presences, :domains, column: :domain_id, name: "fk_mwp_domain"
      # presence 預設 locale 必須是店內語言（restrict：刪 shop_locale 前先改預設）。
      add_foreign_key :market_web_presences, :shop_locales,
                      column: %i[shop_id default_shop_locale], primary_key: %i[shop_id locale_tag],
                      name: "fk_mwp_default_locale"
      add_foreign_key :market_web_presence_locales, :market_web_presences,
                      column: :market_web_presence_id, name: "fk_mwpl_presence", on_delete: :cascade
      # 🔴 這條 FK 就是「③ ⊆ ②」不變量的執法點（67 §C.8）：白名單只能開**已啟用**的語言。
      #    指向 shop_locales 不是 platform_locales——指錯目標，商家能把未啟用語言開給市場，
      #    前台切換器就會出現一個沒有任何譯文的語言。
      add_foreign_key :market_web_presence_locales, :shop_locales,
                      column: %i[shop_id locale_tag], primary_key: %i[shop_id locale_tag],
                      name: "fk_mwpl_shop_locale"
    end
  end
end
