# frozen_string_literal: true

# S0 方案 D（第二批）：`platform_apps` ＋ `app_installations` ＋ `channels`。
#
# 🔴 **這一支落入鐵律 18.3（人工合併）**：它連帶要改 CLAUDE.md 鐵律 2 本文、
#   `docs/specs/71` §A G24 與 `scripts/check-tenant-isolation.rb` 的 `NON_TENANT_TABLES`
#   ——因為 `platform_apps` 是**第三類「平台字典表」**（無 `shop_id`），
#   而鐵律 2 的配套條款③明文要求新增這類表時三處同步改、PR 描述標明。
#   使用者 2026-08-26 已裁定「建 `platform_apps` 平台字典表（忠於本尊）」。
#
# 🔴 **為什麼要它們**（決策文件 C-1／C-2／C-5／C-7／C-8／C-13）：
#   - 管道 handle 的權威在本尊是 `Channel.handle`，且**帶每店後綴**（`shop-72`，`82` §10.3）；
#   - 「已安裝」這個狀態我方無處表達，於是只剩「安裝＝INSERT publication、
#     卸載＝DELETE publication」這條會連帶清光發布列的路；
#   - `App` 是獨立實體（R13-V2 的原始裁定，2026-08-14 至今無人動過）。
#
# 施工圖＝`docs/plans/2026-08-26-S0-方案D-schema設計.md`（表名與欄位以本檔為準，
# 該文件 §7.3 記載本輪對它的三處更正）。
#
# @see docs/plans/2026-08-26-S0-管道身分模型-決策文件.md
# @see docs/research/82-admin-channels.md §10
class CreateChannelIdentity < ActiveRecord::Migration[8.1]
  def up
    # MySQL DDL 非交易（第 3 包實踩）⇒ 全部 if_not_exists，半途死掉可重跑。

    # ── T1 platform_apps：平台字典表（無 shop_id）────────────────────────────
    #
    # 🔴 自然主鍵 `handle`，形態抄 `platform_locales`（主鍵 `tag`）。
    #   用自然鍵而不是自增 id 的理由：字典是**隨版本部署**的，seed 要能冪等 upsert，
    #   而 upsert 需要一個穩定的業務鍵。自增 id 在多環境之間不保證一致。
    create_table :platform_apps, id: false, if_not_exists: true,
                 comment: "平台 app 字典（跨租戶共用；非租戶資料，無 shop_id——鐵律 2 平台字典表）" do |t|
      t.string :handle, limit: 64, null: false, primary_key: true,
               comment: "本尊 App.handle（String／\"Handle of the app.\"）；我方作自然主鍵故 NOT NULL"
      t.string :title, limit: 255, null: false,
               comment: "本尊 App.title（String!／\"Name of the app.\"）"
      t.string :developer_name, limit: 255,
               comment: "本尊 App.developerName（String／\"The name of the app developer.\"）"
      t.boolean :shopify_developed, null: false, default: false,
                comment: "本尊 App.shopifyDeveloped（Boolean!／\"Whether the app was developed by Shopify.\"）；我方文檔慣稱「第一方」"
      t.timestamps
    end

    # ── T2 app_installations：每店的安裝狀態（租戶級）────────────────────────
    create_table :app_installations, if_not_exists: true,
                 comment: "app 在本店的安裝狀態（本尊 AppInstallation）" do |t|
      t.bigint :shop_id, null: false
      t.string :app_handle, limit: 64, null: false, comment: "指向 platform_apps.handle"
      # 🔴 下面兩欄**本尊沒有**（官方 AppInstallation 無任何時間戳、無卸載狀態欄，
      #   取證 2026-08-26）。我方要它們的理由與未取得的部分，見 model 檔頭逐條登記。
      t.datetime :installed_at, null: false, comment: "🔴 ours：本尊 AppInstallation 沒有時間戳"
      t.datetime :uninstalled_at, comment: "🔴 ours：軟刪。NULL＝仍安裝中。讀取端一律帶 installed scope"
      t.timestamps
    end

    add_index :app_installations, %i[shop_id id], unique: true,
              name: "uq_app_installations_tenant_id", if_not_exists: true
    # 🔴 唯一鍵是 `(shop_id, app_handle)` **不含 `uninstalled_at`**：
    #   MySQL 的唯一索引把 NULL 視為互異 ⇒ 把 `uninstalled_at` 放進鍵裡，
    #   「安裝中」的列（該欄為 NULL）可以有無限多筆，正好擋不住我們要擋的東西。
    #   ⇒ 每店每 app 恆一列，重裝＝把 `uninstalled_at` 清回 NULL。
    #   代價：不留安裝歷史。v1 沒有任何消費者需要歷史，需要時另開一張事件表。
    add_index :app_installations, %i[shop_id app_handle], unique: true,
              name: "uq_app_installations_app", if_not_exists: true

    # ── T3 channels：管道身分（租戶級）──────────────────────────────────────
    create_table :channels, if_not_exists: true,
                 comment: "銷售管道身分（本尊 Channel）：handle 的權威來源" do |t|
      t.bigint :shop_id, null: false
      t.bigint :publication_id, null: false
      t.bigint :app_installation_id,
               comment: "可 NULL：agentic 型管道無安裝實體（82 §10.1 實測）。⚠️ 本尊 Channel.app 是非 null"
      t.string :handle, limit: 64, null: false,
               comment: "本尊 Channel.handle（String!／\"...identifier for the channel within the shop\"）；每店唯一、可帶後綴"
      t.string :channel_type, limit: 24, null: false, default: "app",
               comment: "app／agentic（對位本尊 Channel vs AgenticChannel 兩個不同型別）"
      t.timestamps
    end

    add_index :channels, %i[shop_id id], unique: true, name: "uq_channels_tenant_id", if_not_exists: true
    add_index :channels, %i[shop_id handle], unique: true, name: "uq_channels_handle", if_not_exists: true
    # 🔴 `(shop_id, publication_id)` **唯一**：本尊官方 SDL 是 `Publication : Channel = 1 : N`，
    #   但 `82` §10.3 實測第一方管道上 `Channel.id == Publication.id`（都是 209681744107）
    #   ⇒ 實務退化成 1:1。我方**取實測的 1:1**，因為多對一的那個形態
    #   （同一 publication 多個 channel）**我方沒有任何已知用例**，而唯一鍵能擋住
    #   「回填或建店重複建 channel」這一類真實會發生的錯。
    #   ⚠️ 日後若真的出現多連線管道（決策文件 U-1，未取得）要放寬，改這個索引即可。
    add_index :channels, %i[shop_id publication_id], unique: true,
              name: "uq_channels_publication", if_not_exists: true

    # ── 外鍵 ────────────────────────────────────────────────────────────────
    #
    # 新建空表加 FK：strong_migrations 的鎖表顧慮不適用（零列）。
    # 同型先例＝`20260824160000_create_file_usages.rb`。
    safety_assured do
      unless foreign_key_exists?(:app_installations, :shops)
        add_foreign_key :app_installations, :shops, name: "fk_app_installations_shop"
      end
      unless foreign_key_exists?(:app_installations, :platform_apps)
        add_foreign_key :app_installations, :platform_apps,
                        column: :app_handle, primary_key: :handle,
                        name: "fk_app_installations_app_handle"
      end
      unless foreign_key_exists?(:channels, :shops)
        add_foreign_key :channels, :shops, name: "fk_channels_shop"
      end
      unless foreign_key_exists?(:channels, :publications)
        add_foreign_key :channels, :publications,
                        column: %i[shop_id publication_id], primary_key: %i[shop_id id],
                        name: "fk_channels_publication_id"
      end
      unless foreign_key_exists?(:channels, :app_installations)
        add_foreign_key :channels, :app_installations,
                        column: %i[shop_id app_installation_id], primary_key: %i[shop_id id],
                        name: "fk_channels_app_installation_id"
      end
    end

    # ── 字典 seed（唯一正典＝`PlatformApp.seed!`，migration／db:seed／spec 共用）──
    say_with_time("seed platform_apps") { safety_assured { PlatformApp.seed! } }

    # ── 回填 ────────────────────────────────────────────────────────────────
    #
    # 🔴 **配對 spec 非有不可**（第 11／12 包換來的固定處理）：回填迴圈的本體只有在
    #   資料庫已有 publication 時才執行；CI 跑空庫、開發庫也常剛好沒有 ⇒ 兩處都不執行
    #   迴圈本體、`db:migrate` 一路綠，只有正式環境會炸。
    #   配對 spec＝`spec/migrations/s0_backfill_channels_spec.rb`。
    say_with_time("backfill app_installations + channels") { backfill_channel_identity! }
  end

  def down
    drop_table :channels, if_exists: true
    drop_table :app_installations, if_exists: true
    drop_table :platform_apps, if_exists: true
  end

  # 為每筆還沒有 channel 的 publication 建一組（app_installation → channel）。
  #
  # 🔴 **整段包 `ActsAsTenant.without_tenant`**：三個 model 都宣告 `acts_as_tenant`
  #   （`platform_apps` 除外），而 `require_tenant = true` ⇒ 沒有 current_tenant 時
  #   **讀**被 default scope 過濾、**寫**直接 raise `NoTenantSet`。
  #   ⚠️ 更危險的是**租戶是別間店**：default scope 把下面的 `where` 過濾成 0 列，
  #   於是回填一列都不做**而 migration 回報成功**。配對 spec 有一格專盯這個形態。
  #
  # 🔴 **查詢刻意不加 `.unscoped`**：那樣 default scope 的 raise 就死了，
  #   「拿掉 `without_tenant` 會炸」這個行為守衛也跟著死。
  #
  # 🔴 **為什麼獨立成方法**：`up` 的 `create_table` 會送真 DDL ⇒ MySQL 隱式提交，
  #   把 RSpec 的測試交易打斷。抽出來之後 spec 呼叫的是 `up` 呼叫的同一個方法本體
  #   （不是副本），而且不碰 DDL。（同 `20260826062000` 的處置。）
  #
  # @return [Integer] 新建的 channel 列數
  # @note 副作用：INSERT `app_installations` 與 `channels`。
  def backfill_channel_identity!
    created = 0
    now = Time.current

    ActsAsTenant.without_tenant do
      existing_channel_publication_ids = Channel.pluck(:publication_id).to_set

      Publication.find_each do |publication|
        next if existing_channel_publication_ids.include?(publication.id)

        # 🔴 handle 取自 `publications.channel_handle`——這是**權威遷移**：
        #   遷移完成後 `publications.channel_handle` 降級為 legacy 快照，
        #   權威改成 `channels.handle`（設計文件 T5）。
        handle = publication.channel_handle.presence || Shop::DEFAULT_CHANNEL_HANDLE

        # 🔴 app_handle 對不上字典時**不猜、不自動建字典列**，直接跳過並留紀錄。
        #   理由：`platform_apps` 是隨版本部署的字典，回填時憑既有資料反推出一列
        #   新字典項，等於讓正式環境的資料倒過來定義平台目錄。
        unless PlatformApp.exists?(handle: handle)
          say "  ⚠️ 跳過 publication ##{publication.id}：platform_apps 沒有 handle=#{handle}", true
          next
        end

        installation = AppInstallation.find_or_create_by!(
          shop_id: publication.shop_id, app_handle: handle
        ) { |row| row.installed_at = now }

        Channel.create!(
          shop_id: publication.shop_id,
          publication_id: publication.id,
          app_installation_id: installation.id,
          handle: handle,
          channel_type: "app"
        )
        created += 1
      end
    end

    created
  end
end
