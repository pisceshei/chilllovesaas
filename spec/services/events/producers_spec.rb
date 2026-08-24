# frozen_string_literal: true

require "rails_helper"

# 第 19 包 §6-4：兩個產生端的事件面（payload 形、同 transaction、合併窗、availability 邊界）。
RSpec.describe "事件產生端" do
  let!(:shop) { create(:shop, subdomain: "ev-producer-shop") }

  def outbox(topic)
    ActsAsTenant.without_tenant { EventOutbox.where(topic:).order(:id) }
  end

  describe "Catalog::SaveProduct（§4.5(a)）" do
    def save!(input)
      ActsAsTenant.with_tenant(shop) { Catalog::SaveProduct.call(shop:, input:) }
    end

    it "payload 帶 resource_version／changed_fields（63 §C.2 形；只有欄位名沒有值）" do
      result = save!({ title: "帽T", variants: [ { price: "128.00" } ] })
      expect(result.user_errors).to eq([])
      event = outbox(Events::Topics::PRODUCTS_CREATE).sole
      payload = event.payload
      expect(payload["resource_version"]).to eq(result.product.lock_version)
      expect(payload["changed_fields"]).to be_an(Array)
      expect(payload["changed_fields"]).to include("title")
      expect(payload["changed_fields"]).not_to include("updated_at", "lock_version")
      # 紀律 1：欄位名不是值——payload 裡不得出現 title 的字串值
      expect(payload.to_json).not_to include("帽T")
    end

    it "status 變更走 StatusTransition：對外事件帶 status_transition＋補一筆內部 publication.changed" do
      created = save!({ title: "外套", variants: [ { price: "99.00" } ] })
      product = created.product
      result = save!({ id: "gid://chilllove/Product/#{product.id}", title: "外套", status: "ACTIVE", lock_version: product.lock_version, variants: [ { price: "99.00" } ] })
      expect(result.user_errors).to eq([])

      update_event = outbox(Events::Topics::PRODUCTS_UPDATE).sole
      expect(update_event.payload["status_transition"]).to eq({ "from" => "draft", "to" => "active" })

      pub = outbox(Events::Topics::PRODUCT_PUBLICATION_CHANGED).sole
      expect(pub.payload["status_transition"]).to eq({ "from" => "draft", "to" => "active" })
      expect(pub.payload["resource_version"]).to eq(result.product.lock_version)
    end

    it "status 未變更 ⇒ 不產 publication.changed（StatusTransition 不被誤觸）" do
      created = save!({ title: "毛衣", variants: [ { price: "77.00" } ] })
      save!({ id: "gid://chilllove/Product/#{created.product.id}", title: "毛衣改名", lock_version: created.product.lock_version, variants: [ { price: "77.00" } ] })
      expect(outbox(Events::Topics::PRODUCT_PUBLICATION_CHANGED)).to be_empty
    end
  end

  describe "Inventory::Adjust（§4.5(b)）" do
    let!(:variant) { ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:) } }
    let!(:item) { ActsAsTenant.with_tenant(shop) { variant.inventory_item } }
    let!(:location) { Location.unscoped.where(shop_id: shop.id).first! }
    let!(:level) { ActsAsTenant.without_tenant { item.inventory_levels.first! } }

    def adjust!(name:, delta:, key: SecureRandom.uuid)
      # ledgerDocumentUri：available 不得帶、其他 name 必帶（adjust.rb 檔頭規則）
      doc = name == "available" ? nil : "https://docs.example.com/damage-report.pdf"
      ActsAsTenant.with_tenant(shop) do
        Inventory::Adjust.call(shop:, mode: "adjust", input: {
          name:, reason: "correction", idempotency_key: key,
          changes: [ {
            inventory_item_id: "gid://chilllove/InventoryItem/#{item.id}",
            location_id: "gid://chilllove/Location/#{location.id}",
            delta: delta,
            ledger_document_uri: doc
          }.compact ]
        })
      end
    end

    it "事件與業務寫入同 transaction（鐵律 5）：成功一筆 inventory.adjusted、payload 無餘額值" do
      result = adjust!(name: "damaged", delta: 3)
      expect(result.user_errors).to eq([])
      event = outbox(Events::Topics::INVENTORY_ADJUSTED).sole
      payload = event.payload
      expect(payload["inventory_item_id"]).to eq(item.id)
      expect(payload["location_id"]).to eq(location.id)
      expect(payload.dig("adjustment", "quantity_name")).to eq("damaged")
      expect(payload.dig("adjustment", "delta")).to eq(3)
      expect(payload.dig("adjustment", "ledger_id")).to be_present
      expect(payload["availability_flipped"]).to eq(false)
      # 防線④：不帶數量餘額（只有 delta），damaged 調整後的餘額不得入 payload
      expect(payload.keys).not_to include("on_hand", "available", "quantity")
    end

    it "驗證失敗 rollback ⇒ 事件一併消失（反向案例）" do
      huge = Limits.fetch(:inventory, :quantity_result_max)
      result = adjust!(name: "available", delta: huge + 1)
      expect(result.user_errors.map { |e| e[:code] }).to include("INVALID_QUANTITY_TOO_HIGH")
      expect(outbox(Events::Topics::INVENTORY_ADJUSTED)).to be_empty
    end

    describe "availability_flipped 三態（>0→≤0／≤0→>0／>0→>0）" do
      it "available 從 0 升到正 ⇒ flipped=true 且 dedupe_key=NULL（豁免不併）" do
        adjust!(name: "available", delta: 5)
        event = outbox(Events::Topics::INVENTORY_ADJUSTED).sole
        expect(event.payload["availability_flipped"]).to eq(true)
        expect(event.dedupe_key).to be_nil
      end

      it "正值內變動 ⇒ flipped=false 且 dedupe_key 有值（可併）" do
        adjust!(name: "available", delta: 5)
        adjust!(name: "available", delta: 2)
        flipped, unflipped = outbox(Events::Topics::INVENTORY_ADJUSTED).partition { |e| e.payload["availability_flipped"] }
        expect(flipped.sole.dedupe_key).to be_nil
        expect(unflipped.sole.dedupe_key).to match(/\Ainv:#{item.id}:#{location.id}:\d+\z/)
      end

      it "降到 0 ⇒ flipped=true（售罄邊界，63 §C.6 豁免的存在理由）" do
        adjust!(name: "available", delta: 5)
        adjust!(name: "available", delta: -5)
        events = outbox(Events::Topics::INVENTORY_ADJUSTED).to_a
        expect(events.last.payload["availability_flipped"]).to eq(true)
      end
    end

    describe "合併窗（63 §C.6）" do
      it "同 (item, location) 窗內非豁免筆併成一列：coalesced_count 累加、payload 為最新" do
        adjust!(name: "damaged", delta: 1)
        adjust!(name: "damaged", delta: 2)
        adjust!(name: "damaged", delta: 3)
        events = outbox(Events::Topics::INVENTORY_ADJUSTED).to_a
        expect(events.size).to eq(1)
        expect(events.sole.coalesced_count).to eq(3)
        expect(events.sole.payload.dig("adjustment", "delta")).to eq(3)
      end

      it "published 後同 key 開新列（release-on-terminal，不 upsert 到已發布列）" do
        adjust!(name: "damaged", delta: 1)
        Events::Relay.drain!
        adjust!(name: "damaged", delta: 2)
        events = outbox(Events::Topics::INVENTORY_ADJUSTED).to_a
        expect(events.size).to eq(2)
        expect(events.first.status).to eq("published")
        expect(events.last.status).to eq("pending")
        expect(events.last.coalesced_count).to eq(1)
      end

      it "ledger 永不合併（紅線 3）：三次呼叫＝三列 group、三列 ledger，被併的只有事件" do
        3.times { adjust!(name: "damaged", delta: 1) }
        ActsAsTenant.without_tenant do
          expect(InventoryAdjustmentGroup.count).to eq(3)
          expect(InventoryAdjustment.count).to eq(3)
          expect(EventOutbox.where(topic: Events::Topics::INVENTORY_ADJUSTED).count).to eq(1)
        end
      end
    end
  end
end
