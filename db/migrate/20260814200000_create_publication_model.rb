# 發布模型：把「商品有沒有上架」從一個布林欄改成 Publishable × Publication 的關聯
# （裁定 84 §1 A-5／71-R13-V4；契約全文＝docs/specs/88）。
#
# 為什麼現在做：M1 是商品線，商品的「上架到哪些管道」是它的核心欄位面。
# M0 目前用 `products.published_at` 表達上架——那是**扁平模型**（一個商品要嘛發布要嘛沒有），
# 而本尊的真實模型是 **Publishable × Publication × Catalog 三層 AND**（R13 實測＋help 明文）。
# 🔴 若 M1 照扁平模型寫完商品 CRUD、GraphQL 契約與 UI，之後要拆成三層是**結構改造**，
# 而不是加個欄位——那時商品表單、上架區塊、目錄、市場四個掛載點都要一起改。
#
# 本 migration 建**前兩層**；第三層 catalog 留 `publications.catalog_id`（暫不加外鍵），
# 待 M5 建 markets/catalogs 時補。理由見 docs/specs/88 §3.2：
# catalog 是**讀取時的過濾條件**，加它不需要改動本次兩張表的結構。
class CreatePublicationModel < ActiveRecord::Migration[8.1]
  def up
    # ── publications：一個銷售管道在一間店的發布容器 ─────────────────────────
    # 🔴 這是**業務資料**，帶 shop_id（鐵律 2；G24 的豁免只給身分表）。
    create_table :publications, comment: "銷售管道在本店的發布容器（Publication）" do |t|
      t.bigint :shop_id, null: false
      t.string :name, null: false, comment: "顯示名（線上商店／門市 POS／代理式）"
      t.string :channel_handle, limit: 64, null: false,
        comment: "管道識別（online_store／point_of_sale／agentic…）"
      # 本尊：新增管道時既有商品**自動可用**，不要就得逐一移除（82 §0.2）。
      t.boolean :auto_publish, null: false, default: true,
        comment: "新建的 publishable 是否自動納入本管道"
      # 🔴 Shop 管道不支援排程發布（82 §0.2）——所以這是 per-publication 的能力旗標。
      t.boolean :supports_future_publishing, null: false, default: true,
        comment: "本管道是否支援排程發布"
      # 第三層：M5 建 catalogs 時補外鍵。catalogType ∈ APP／COMPANY_LOCATION／MARKET。
      t.bigint :catalog_id, comment: "三層 AND 的第三層；M5 建 catalogs 時補外鍵"
      t.timestamps

      t.index %i[shop_id channel_handle], unique: true, name: "uq_publications_channel"
      t.index %i[shop_id id], unique: true, name: "uq_publications_tenant_id"
    end
    # 新表加外鍵：表是空的，加鎖無代價（strong_migrations 需明示）。
    safety_assured do
      add_foreign_key :publications, :shops, name: "fk_publications_shop"
    end

    # ── resource_publications：Publishable × Publication 的關聯 ─────────────────
    # 🔴 命名用 `resource_publications` 而非 `product_publications`：它是**多型**的——
    #    本尊的 Publishable 介面由 Product、Collection、ProductVariant 三者實作（82 §0.2），
    #    叫 product_* 會讓後兩者看起來像是硬塞進來的。對應本尊的 `ResourcePublication` 型別。
    create_table :resource_publications, comment: "Publishable × Publication 的發布關聯" do |t|
      t.bigint :shop_id, null: false
      t.bigint :publication_id, null: false
      t.string :publishable_type, limit: 32, null: false,
        comment: "Product／Collection／ProductVariant"
      t.bigint :publishable_id, null: false
      # 🔴 NULL＝尚未發布；未來時間＝**排程發布**（future publishing）。
      #    本尊限制：商品須為 Active 才生效、不支援單一 variant 排程（82 §0.2）——
      #    那兩條是應用層規則，不是欄位約束。
      t.datetime :published_at, comment: "NULL=未發布；未來時間=排程發布"
      t.timestamps

      t.index %i[shop_id publication_id publishable_type publishable_id],
        unique: true, name: "uq_res_pub_target"
      t.index %i[shop_id publishable_type publishable_id], name: "ix_res_pub_publishable"
      t.index %i[shop_id publication_id published_at], name: "ix_res_pub_published_at"
      t.index %i[shop_id id], unique: true, name: "uq_res_pub_tenant_id"
    end
    # 新表加外鍵：表是空的，加鎖無代價（strong_migrations 需明示）。
    safety_assured do
      add_foreign_key :resource_publications, :publications,
        column: %i[shop_id publication_id], primary_key: %i[shop_id id],
        name: "fk_res_pub_publication_id"
      add_foreign_key :resource_publications, :shops, name: "fk_res_pub_shop"
    end

    # ── 每間店建一個「線上商店」publication，並把既有的 published_at 搬過去 ──────
    # strong_migrations 無法檢視 execute，需明示安全。
    # 安全理由：INSERT 進剛建立的空表；shops/products 在 M0 骨架階段列數極小。
    safety_assured do
      execute <<~SQL.squish
        INSERT INTO publications (shop_id, name, channel_handle, auto_publish,
                                  supports_future_publishing, created_at, updated_at)
        SELECT id, '線上商店', 'online_store', TRUE, TRUE, NOW(), NOW() FROM shops
      SQL

      # 既有 products.published_at 的語義就是「發布到線上商店」，原樣搬進關聯。
      execute <<~SQL.squish
        INSERT INTO resource_publications (shop_id, publication_id, publishable_type,
                                           publishable_id, published_at, created_at, updated_at)
        SELECT p.shop_id, pub.id, 'Product', p.id, p.published_at, NOW(), NOW()
        FROM products p
        JOIN publications pub
          ON pub.shop_id = p.shop_id AND pub.channel_handle = 'online_store'
      SQL

      # 🔴 移除 products.published_at：**同一件事不留兩個事實來源**。
      #    這正是鐵律 7 要防的形態——兩處都能寫，遲早不一致。
      #    排程發布的語義沒有消失，它搬到了 resource_publications.published_at（per channel）。
      remove_index :products, name: "ix_products_published_at_id"
      remove_column :products, :published_at
    end
  end

  def down
    safety_assured do
      add_column :products, :published_at, :datetime
      add_index :products, %i[shop_id published_at id], name: "ix_products_published_at_id"
      execute <<~SQL.squish
        UPDATE products p
        JOIN publications pub
          ON pub.shop_id = p.shop_id AND pub.channel_handle = 'online_store'
        JOIN resource_publications rp
          ON rp.shop_id = p.shop_id AND rp.publication_id = pub.id
         AND rp.publishable_type = 'Product' AND rp.publishable_id = p.id
        SET p.published_at = rp.published_at
      SQL
    end
    drop_table :resource_publications
    drop_table :publications
  end
end
