# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shop, type: :model do
  # ── 建店必帶預設管道（88 §4／§5 #1）─────────────────────────────────────
  describe "建立時自動建立 online_store publication" do
    it "新店立刻就有線上商店管道" do
      shop = create(:shop)

      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      expect(publication).to be_present
      expect(publication.shop_id).to eq(shop.id)
      expect(publication.name).to eq("線上商店")
    end

    it "帶 88 §2.1 規定的預設值" do
      shop = create(:shop)

      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      # auto_publish 預設 true：本尊「新增管道時既有商品自動可用，不要就得逐一移除」。
      expect(publication.auto_publish).to be(true)
      # 線上商店支援排程發布（Shop 管道才是 false，82 §0.2）。
      expect(publication.supports_future_publishing).to be(true)
      # 🔴 **2026-08-26 S0 反轉的斷言**：原本這裡斷言 `catalog_id` 為 nil，
      #   註釋寫「catalog 是第三層，M5 才建」。實測本尊**每個 publication 都有 catalog**
      #   （`docs/research/82` §9.5b／§10.3 兩次抓包）⇒ 恆為 nil 的第三層等於三層 AND
      #   永遠 no-op。使用者 2026-08-26 裁定方案 D 後，建店即建 catalog。
      # ⚠️ 這幾格必須包 `with_tenant`：`SalesCatalog` 也宣告 `acts_as_tenant`，
      #   而 `require_tenant = true` ⇒ 在租戶外載入這個關聯會拋 `NoTenantSet`
      #   （不是回 nil）。這是 fail-closed，本身就是鐵律 2 要的行為。
      ActsAsTenant.with_tenant(shop) do
        expect(publication.sales_catalog).to be_present
        expect(publication.sales_catalog.shop_id).to eq(shop.id)
        expect(publication.sales_catalog.catalog_type).to eq("app")
        expect(publication.sales_catalog.status).to eq("active")
        expect(publication.display_title).to eq("線上商店")
      end
    end

    it "本尊的五個能力旗標都有預設值（82 §10.4：線上商店六個旗標全 true）" do
      shop = create(:shop)

      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      expect(publication.supports_bundles).to be(true)
      expect(publication.supports_combined_listings).to be(true)
      expect(publication.supports_variant_fixed_bundles).to be(true)
      expect(publication.supports_subscriptions).to be(true)
      expect(publication.supports_publication_for_unlisted_products).to be(true)
      # 🔴 建店當下沒有進行中的發布操作 ⇒ NULL。本尊 ResourceOperationStatus 恰三值，
      #   「沒有操作」不是其中之一（不得落成 "none"）。
      expect(publication.operation_status).to be_nil
      expect(publication.operation_in_progress?).to be(false)
    end

    it "只建一個管道，不多建" do
      shop = create(:shop)

      count = ActsAsTenant.with_tenant(shop) { Publication.count }
      expect(count).to eq(1)
    end

    it "兩間店各有自己的管道，且互不可見（鐵律 2）" do
      first = create(:shop)
      second = create(:shop)

      first_pub = ActsAsTenant.with_tenant(first) { Publication.online_store }
      second_pub = ActsAsTenant.with_tenant(second) { Publication.online_store }

      expect(first_pub.id).not_to eq(second_pub.id)
      ActsAsTenant.with_tenant(first) { expect(Publication.count).to eq(1) }
      ActsAsTenant.with_tenant(second) { expect(Publication.count).to eq(1) }
    end

    # 🔴 這一條釘住的是 `dependent: :destroy` 的選擇。
    # 本 model 另外三個關聯都用 `restrict_with_error`，照抄看起來合慣例——
    # 但 after_create 之後每一間店恆有一列 publication，用 restrict 的話
    # **連一間空店都永遠刪不掉**，而且沒有任何既有測試會因此變紅。
    it "空店可以刪除（publication 不得變成刪不掉的理由）" do
      shop = create(:shop)

      expect { shop.destroy }.to change { Shop.count }.by(-1)
      expect(shop.destroyed?).to be(true)
      expect(Publication.unscoped.where(shop_id: shop.id).count).to eq(0)
    end

    # 🔴 這一條釘住 `around_destroy :within_own_tenant`。
    # 沒有它時，在**別間店**的租戶 context 下刪店，`dependent: :destroy` 的
    # default scope 會把 publication 過濾成 0 列 ⇒ 一列都沒刪掉，
    # 而 `destroy` **回報成功**——「回報成功但什麼都沒做」，比直接炸危險得多。
    it "在別的租戶 context 下刪店，仍然把自己的 publication 一起刪掉" do
      other = create(:shop)
      shop = create(:shop)

      ActsAsTenant.with_tenant(other) { expect(shop.destroy).to be_truthy }

      expect(Publication.unscoped.where(shop_id: shop.id).count).to eq(0)
      expect(described_class.exists?(shop.id)).to be(false)
      # 別間店的管道不得被波及。
      expect(Publication.unscoped.where(shop_id: other.id).count).to eq(1)
    end

    it "沒有任何租戶 context 也刪得掉（呼叫端不需要先設租戶）" do
      shop = create(:shop)

      ActsAsTenant.without_tenant { expect(shop.destroy).to be_truthy }
      expect(Publication.unscoped.where(shop_id: shop.id).count).to eq(0)
    end

    # 建店失敗時不該留下孤兒 publication——after_create 在同一個 transaction 內。
    it "建店失敗時不留下孤兒 publication" do
      before_count = Publication.unscoped.count

      expect {
        described_class.create!(name: "壞店", subdomain: "INVALID SUBDOMAIN!", status: "active")
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(Publication.unscoped.count).to eq(before_count)
    end
  end

  # ── 關聯宣告與 schema 一致（2026-08-15 發現的活缺陷）────────────────────────
  #
  # 🔴 `20260814000000`（身分表升組織層）從 `staff_members`／`sessions`／`roles`
  # 拆掉了 `shop_id`，卻沒有同步改 `Shop` 的 `has_many` 宣告 ⇒ 三者都會生出
  # `WHERE staff_members.shop_id = ?`，實跑一律 `Unknown column`，
  # 而 **`Shop#destroy` 因此完全不能用**。
  # 在此之前**沒有任何測試發現**——全庫沒有一條測試呼叫過 `shop.destroy` 或這三個關聯。
  describe "關聯宣告與 schema 一致" do
    it "每一個 has_many 都能真的查詢（宣告不得指向已被拆掉的欄位）" do
      shop = create(:shop)

      ActsAsTenant.with_tenant(shop) do
        described_class.reflect_on_all_associations(:has_many).each do |reflection|
          expect { shop.public_send(reflection.name).count }
            .not_to raise_error, "關聯 #{reflection.name} 查詢失敗"
        end
      end
    end

    it "staff 透過 user_store_assignments 關聯，不是直接掛 shop_id" do
      shop = create(:shop)
      staff = ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:) }

      expect(shop.staff_members).to include(staff)
      expect(described_class.reflect_on_association(:staff_members).through_reflection.name)
        .to eq(:user_store_assignments)
    end

    it "還有人在的店不得刪除（原本 restrict_with_error 的意圖改由指派關係承載）" do
      shop = create(:shop)
      ActsAsTenant.with_tenant(shop) { create(:staff_member, shop:) }

      expect(shop.destroy).to be(false)
      expect(shop.errors[:base]).to be_present
      expect(described_class.exists?(shop.id)).to be(true)
    end

    it "sessions 與 roles 不再是 Shop 的下屬集合（兩者已升組織層）" do
      expect(described_class.reflect_on_association(:sessions)).to be_nil
      expect(described_class.reflect_on_association(:roles)).to be_nil
    end
  end

  # ── 建店流程的每一條路徑都要涵蓋（這正是掛在 model callback 的理由）────────
  describe "涵蓋範圍" do
    it "透過 without_tenant 建店（seeds 的形態）也會建管道" do
      # db/seeds.rb 用 `ActsAsTenant.without_tenant { Shop.find_or_create_by! }`。
      # 🔴 `with_tenant` 只換 current_tenant、不動 unscoped 旗標，
      # 所以 callback 在 without_tenant 區塊內巢狀使用是安全的——
      # 這條 spec 就是那個判斷的證據。
      shop = ActsAsTenant.without_tenant { create(:shop) }

      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      expect(publication).to be_present
      expect(publication.shop_id).to eq(shop.id)
    end

    it "在別的租戶 context 下建店，管道仍掛在新店而不是當前租戶" do
      other = create(:shop)

      shop = ActsAsTenant.with_tenant(other) { create(:shop) }

      publication = ActsAsTenant.with_tenant(shop) { Publication.online_store }
      expect(publication.shop_id).to eq(shop.id)
      ActsAsTenant.with_tenant(other) { expect(Publication.count).to eq(1) }
    end
  end
end
