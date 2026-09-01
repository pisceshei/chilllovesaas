# frozen_string_literal: true

require "rails_helper"

# 第 3 包：cache stamp 欄與其寫入接線。
#
# 🔴 stamp 欄的失敗形態是**靜默的**：欄位在、沒人 bump ⇒ 第 33 包的頁級快取
#   key 永遠不變 ⇒ 前台永遠顯示舊圖舊價，而且沒有任何錯誤。所以本檔逐一釘住
#   「每一個會改變前台呈現的寫入路徑都 bump 了對的欄」。
RSpec.describe Catalog::CacheStamps do
  let(:shop) { create(:shop, subdomain: "stamp-shop") }

  def db_row(table, id, *cols)
    ActiveRecord::Base.connection.select_one(
      "SELECT #{cols.join(', ')} FROM #{table} WHERE id = #{Integer(id)}"
    )
  end

  def make_file!
    key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
    Storage::LocalDisk.write(key, StringIO.new("BYTES"))
    StoredFile.create!(filename: "s-#{SecureRandom.hex(3)}.png", content_type: "image/png",
                       byte_size: 5, checksum: SecureRandom.hex(32), storage_key: key,
                       status: "ready", width: 100, height: 80)
  end

  describe "schema ↔ limits 的機械連動" do
    it "🔴 cache_stamp_sources 的每一個來源都解析得到真實欄位（或在已知未建清單裡）" do
      # 這條測試的目的：有人往 limits 加一個維度而**忘了建欄**時要當場紅，
      # 而不是等第 33 包上線後陷入「快取 key 引用不存在的欄」。
      # 🔴 known_pending 不只是登記——每一項綁它的**未來表**，表一建、這裡就紅
      #   （審查 DOC-3：第一版只斷言「∈ 清單」，第 32 包建表時什麼都不會轉紅，
      #   handoff 的「強制回頭對帳」是機械上不成立的宣稱）。
      # S10（D76）：price_lists 已建、來源已改帶前綴寫法 ⇒ 自本清單移除（絆線完成使命）。
      # 包 32（2026-08-31）：markets 已建、market_settings_version 改為 markets.updated_at ⇒ 同前例移除。
      # 🔴 機制保留：未來加規劃中來源時照樣「登記未來表」，不得只斷言 ∈ 清單。
      known_pending = {}
      Limits.fetch(:catalog_flow, :cache_stamp_sources).each do |source|
        src = source.to_s
        if src.include?(".")
          table, column = src.split(".", 2)
          expect(ActiveRecord::Base.connection.column_exists?(table, column))
            .to be(true), "#{src} 在 schema 找不到欄位"
        else
          expect(known_pending).to have_key(src),
            "#{src} 不帶表前綴又不在已知未建清單——請建欄或登記"
          expect(ActiveRecord::Base.connection.table_exists?(known_pending.fetch(src)))
            .to be(false),
            "#{known_pending.fetch(src)} 表已建——把 #{src} 換成帶前綴寫法並建 stamp 欄"
        end
      end
    end
  end

  describe "寫入接線" do
    let!(:product) do
      ActsAsTenant.with_tenant(shop) { create(:product_variant, shop:).product }
    end

    it "🔴 SaveProduct 更新 ⇒ bump variants_updated_at（宣告式全量恆重寫變體樹）" do
      before = ActsAsTenant.with_tenant(shop) { db_row("products", product.id, "variants_updated_at") }
      travel 1.second do
        ActsAsTenant.with_tenant(shop) do
          variant = product.product_variants.sole
          Catalog::SaveProduct.call(shop:, input: {
            id: "gid://chilllove/Product/#{product.id}", title: "更名",
            lock_version: product.reload.lock_version,
            variants: [ { id: "gid://chilllove/ProductVariant/#{variant.id}", price: "128.00" } ]
          })
        end
      end
      after = ActsAsTenant.with_tenant(shop) { db_row("products", product.id, "variants_updated_at") }
      expect(after["variants_updated_at"]).not_to eq(before["variants_updated_at"])
    end

    it "MediaSync.create ⇒ bump media_updated_at" do
      ActsAsTenant.with_tenant(shop) do
        expect do
          Catalog::MediaSync.create(shop:, product:, entries: [ { file_id: make_file!.id } ])
        end.to(change { db_row("products", product.id, "media_updated_at")["media_updated_at"] })
      end
    end

    it "🔴 檔案層 alt 變更 ⇒ bump **所有**用到該檔的商品（D48 的跨商品傳播）" do
      ActsAsTenant.with_tenant(shop) do
        other = create(:product_variant, shop:).product
        file = make_file!
        Catalog::MediaSync.create(shop:, product:, entries: [ { file_id: file.id } ])
        Catalog::MediaSync.create(shop:, product: other, entries: [ { file_id: file.id } ])
        before_other = db_row("products", other.id, "media_updated_at")["media_updated_at"]

        travel 1.second do
          # 從第一個商品的媒體卡改 alt（D48：寫的是檔案）⇒ 第二個商品的呈現也變了
          row = product.media.reload.sole
          Storage::FileWrite.update(shop:, entries: [ { id: "gid://chilllove/File/#{file.id}", alt: "新說明" } ])
          after_other = db_row("products", other.id, "media_updated_at")["media_updated_at"]
          # 🔴 只 bump 本商品＝other 留在舊快取顯示舊 alt——這正是本條要防的靜默窗
          expect(after_other).not_to eq(before_other)
          expect(row).to be_present
        end
      end
    end

    it "FileWrite.delete ⇒ bump 受影響商品（商品少了一張圖）" do
      ActsAsTenant.with_tenant(shop) do
        file = make_file!
        Catalog::MediaSync.create(shop:, product:, entries: [ { file_id: file.id } ])
        expect do
          travel 1.second do
            Storage::FileWrite.delete(shop:, file_ids: [ "gid://chilllove/File/#{file.id}" ])
          end
        end.to(change { db_row("products", product.id, "media_updated_at")["media_updated_at"] })
      end
    end

    it "DeleteVariant ⇒ bump variants_updated_at" do
      ActsAsTenant.with_tenant(shop) do
        # 要兩個變體才刪得動（LAST_VARIANT 守衛）
        option = ProductOption.create!(shop_id: shop.id, product_id: product.id, name: "尺寸", position: 1)
        values = %w[S M].each_with_index.map do |v, i|
          OptionValue.create!(shop_id: shop.id, product_option_id: option.id, value: v, position: i + 1)
        end
        base = product.product_variants.sole
        base.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
          product_option_id: option.id, option_value_id: values[0].id)
        base.save!
        extra = ProductVariant.new(shop_id: shop.id, product_id: product.id, title: "M",
                                   position: 2, currency: shop.store_currency)
        extra.product_variant_option_values.build(shop_id: shop.id, product_id: product.id,
          product_option_id: option.id, option_value_id: values[1].id)
        extra.save!

        expect do
          # 🔴 不能寫 `travel 1.second { … }`——大括號綁到 `.second`，區塊靜默不執行
          travel(1.second) do
            Catalog::DeleteVariant.call(shop:, variant: extra)
          end
        end.to(change { db_row("products", product.id, "variants_updated_at")["variants_updated_at"] })
      end
    end

    it "SaveCollection 成員同步 ⇒ bump collections.products_updated_at" do
      ActsAsTenant.with_tenant(shop) do
        collection = Collection.create!(shop_id: shop.id, title: "測試系列", description_html: "",
                                        handle: "st-#{SecureRandom.hex(3)}", collection_type: "manual")
        expect do
          result = Catalog::SaveCollection.call(shop:, input: {
            id: "gid://chilllove/Collection/#{collection.id}",
            title: "測試系列",
            lock_version: collection.lock_version,
            product_ids: [ "gid://chilllove/Product/#{product.id}" ]
          })
          expect(result.user_errors).to eq([])
        end.to(change { db_row("collections", collection.id, "products_updated_at")["products_updated_at"] })
      end
    end

    it "MediaSync.reorder／append_to_variant／卸變體圖 ⇒ 都 bump media stamp" do
      ActsAsTenant.with_tenant(shop) do
        Catalog::MediaSync.create(shop:, product:,
          entries: [ { file_id: make_file!.id }, { file_id: make_file!.id } ])
        ids = product.media.reload.order(:position).pluck(:id)
        variant = product.product_variants.sole

        stamp = -> { db_row("products", product.id, "media_updated_at")["media_updated_at"] }
        expect { Catalog::MediaSync.reorder(shop:, product:, media_ids: ids.reverse) }
          .to(change { stamp.call })
        expect { Catalog::MediaSync.append_to_variant(shop:, product:, variant_id: variant.id, media_id: ids.first) }
          .to(change { stamp.call })
        expect { Catalog::MediaSync.append_to_variant(shop:, product:, variant_id: variant.id, media_id: nil) }
          .to(change { stamp.call })
      end
    end

    it "🔴 衍生尺寸就緒（ProcessFile）⇒ bump 所有用到該檔的商品" do
      ActsAsTenant.with_tenant(shop) do
        # 替身後端＝process_file_spec 的同款形狀（open 回 source、source 有 derive）
        source = Object.new
        def source.width = 800
        def source.height = 600
        def source.derive(spec) = [ "WEBP#{spec[:width]}", spec[:width], spec[:height] ]
        backend = Object.new
        backend.instance_variable_set(:@source, source)
        def backend.open(_bytes) = @source
        MediaPipeline::ProcessFile.backend = backend

        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
        Storage::LocalDisk.write(key, StringIO.new("PNGBYTES"))
        file = StoredFile.create!(filename: "pp-#{SecureRandom.hex(3)}.png", content_type: "image/png",
                                  byte_size: 8, checksum: Digest::SHA256.hexdigest("PNGBYTES"),
                                  storage_key: key, status: "uploaded")
        Catalog::MediaSync.create(shop:, product:, entries: [ { file_id: file.id } ])

        expect do
          travel(1.second) { MediaPipeline::ProcessFile.call(file) }
        end.to(change { db_row("products", product.id, "media_updated_at")["media_updated_at"] })
        expect(file.reload.status).to eq("ready")
      ensure
        MediaPipeline::ProcessFile.reset_backend!
      end
    end

    it "處理失敗（ProcessFile）也 bump——縮圖占位變失敗占位，呈現變了" do
      ActsAsTenant.with_tenant(shop) do
        backend = Object.new
        def backend.open(_bytes) = raise(MediaPipeline::VipsBackend::DecodeFailed, "bad header")
        MediaPipeline::ProcessFile.backend = backend

        key = "shops/#{shop.id}/files/#{SecureRandom.uuid}.png"
        Storage::LocalDisk.write(key, StringIO.new("BAD"))
        file = StoredFile.create!(filename: "pf-#{SecureRandom.hex(3)}.png", content_type: "image/png",
                                  byte_size: 3, checksum: Digest::SHA256.hexdigest("BAD"),
                                  storage_key: key, status: "uploaded")
        Catalog::MediaSync.create(shop:, product:, entries: [ { file_id: file.id } ])

        expect do
          travel(1.second) { MediaPipeline::ProcessFile.call(file) }
        end.to(change { db_row("products", product.id, "media_updated_at")["media_updated_at"] })
        expect(file.reload.status).to eq("failed")
      ensure
        MediaPipeline::ProcessFile.reset_backend!
      end
    end

    it "🔴 掛既有共用檔＋alt（productCreateMedia 的 fileId 路徑）⇒ 其他商品的 stamp 也動" do
      # 審查 cs-1／P3-1：CacheStamps 檔頭③自己點名的錯，第一版就在 build_media! 犯了
      # ——create 只 bump 目標商品，其他掛著同檔的商品留在舊快取顯示舊 alt。
      ActsAsTenant.with_tenant(shop) do
        other = create(:product_variant, shop:).product
        file = make_file!
        file.update!(alt_text: "舊說明")
        Catalog::MediaSync.create(shop:, product: other, entries: [ { file_id: file.id } ])
        before_other = db_row("products", other.id, "media_updated_at")["media_updated_at"]

        travel(1.second) do
          Catalog::MediaSync.create(shop:, product:,
            entries: [ { file_id: file.id, alt: "新說明" } ])
        end
        expect(file.reload.alt_text).to eq("新說明")
        expect(db_row("products", other.id, "media_updated_at")["media_updated_at"])
          .not_to eq(before_other)
      end
    end

    it "🔴 TOUCH 寫入值與 Rails 的 UTC 同一個時鐘域" do
      # 審查 cs-3（實測證實）：CURRENT_TIMESTAMP(6) 用 session 時區（本機＝台北），
      # Rails 以 UTC 讀 ⇒ stamp 變成未來 8 小時。TOUCH 必須用 UTC_TIMESTAMP(6)。
      ActsAsTenant.with_tenant(shop) do
        described_class.bump_media_for_product!(shop.id, product.id)
        stamp = db_row("products", product.id, "media_updated_at")["media_updated_at"]
        expect((stamp - Time.current.utc).abs).to be < 60,
          "stamp 與 UTC 差 #{(stamp - Time.current.utc).round} 秒——時鐘域不一致"
      end
    end

    it "🔴 市場鏈寫入 ⇒ bump markets.updated_at（market stamp；touch 級聯：mwpl→presence→market）" do
      # 包 32：market_settings_version 落成 markets.updated_at 之後，「繼承解析結果變了」
      # 的三類輸入（region／presence／白名單開關）都必須推進 stamp——漏一類＝該類變更後
      # 前台永遠舊快取（63 §G.5 的靜默窗，本檔檔頭的失敗形態）。
      ActsAsTenant.with_tenant(shop) do
        market = Market.find_by!(is_primary: true)
        stamp = -> { db_row("markets", market.id, "updated_at")["updated_at"] }
        presence = market.market_web_presences.sole

        ShopLocale.find_by!(locale_tag: "zh-Hant").update!(published: true)
        row = nil
        expect { travel(1.second) { row = presence.market_web_presence_locales.create!(locale_tag: "zh-Hant", position: 1) } }
          .to(change { stamp.call })
        expect { travel(2.seconds) { row.close! } }.to(change { stamp.call })
        expect { travel(3.seconds) { Market.create!(name: "TW", handle: "tw", status: "active", market_type: "region")
                                            .market_regions.create!(country_code: "TW") } }
          .not_to(change { stamp.call }) # 對照：別的市場的寫入不動本市場的 stamp
      end
    end

    it "🔴 bump 不得動 lock_version（Rails 8.1 的 update_all 對樂觀鎖 model 會自動 +1，已顯式釘住）" do
      # 本包首輪的現行犯：hash 形式的 update_all 讓 0 → 1，正在編輯該商品的人
      # 存檔就撞 STALE_OBJECT——改一張共用圖的 alt 會打斷所有相關商品的編輯。
      ActsAsTenant.with_tenant(shop) do
        before = db_row("products", product.id, "lock_version")["lock_version"]
        described_class.bump_media_for_product!(shop.id, product.id)
        described_class.bump_variants!(shop.id, product.id)
        expect(db_row("products", product.id, "lock_version")["lock_version"]).to eq(before)
      end
    end
  end

  describe "files.alt_source（62 §F.1 稽核）" do
    it "後台寫 alt ⇒ 自動標 human；顯式來源不被覆蓋；沒動 alt 就不標" do
      ActsAsTenant.with_tenant(shop) do
        file = make_file!
        expect(file.alt_source).to be_nil   # 建立時沒寫 alt ⇒ 不標

        file.update!(alt_text: "人工說明")
        expect(file.reload.alt_source).to eq("human")

        # 未來的 AI 產生器顯式帶來源 ⇒ callback 不動它
        file.update!(alt_text: "AI 產的", alt_source: "ai")
        expect(file.reload.alt_source).to eq("ai")

        # 沒動 alt 的更新不改來源
        file.update!(filename: "renamed-#{SecureRandom.hex(3)}.png")
        expect(file.reload.alt_source).to eq("ai")
      end
    end

    it "值域來自 limits（白名單外拒收）" do
      ActsAsTenant.with_tenant(shop) do
        file = make_file!
        expect { file.update!(alt_text: "x", alt_source: "robot") }
          .to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end
end
