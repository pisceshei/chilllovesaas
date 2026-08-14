# 身分與權限表由商店級升為組織級（裁定 D8／§A G24；兩案評估＝docs/specs/85）。
#
# 表定義出處（AGENTS.md §註釋與文檔 第 2 條要求引 `docs/research/06` §7）：
#   - `staff_members` / `roles` / `role_permissions` → **06 §7 骨幹表清單有這三張**，本檔只改其
#     租戶維度（移除 shop_id），欄位語義不變。
#   - 🔴 `user_store_assignments` → **06 §7 沒有這張表**。它不是漏引，是 06 號成文時
#     （單店身分模型）根本不存在這個概念；它源自 R12 實測本尊的組織級 RBAC，
#     由 71 §A **G24** 裁定新增。定義出處＝`docs/specs/85` §3。
# <!-- 2026-08-14 補（PR #23 的 Codex review 第 2 條指出 A-3 的 migration 漏引 06 §7，
#      回頭檢查發現本檔與 20260814200000 同樣漏引）。
#      🔴 這裡刻意**不**照貼一句「見 06 §7」——`user_store_assignments` 在那份文件裡查不到，
#      貼了等於指路指到空的地方，比不貼更糟。缺表就寫明缺，並指向真正的出處。 -->
#
# 為什麼要改：本尊 2026 已改 RBAC 且使用者掛組織層（R12 實測），完整鏈是
# 使用者↔（群組）↔角色↔權限，角色可跨店。M0 依當時的鐵律 2「全表帶 shop_id」
# 把這四張表建成商店級——**M0 沒有寫錯**，是鐵律 2 在 2026-08-14 被裁定加上豁免。
#
# 🔴 豁免的邊界（CLAUDE.md 鐵律 2 註釋、71 §A G24）：
#   - 豁免的是「表有沒有 shop_id 欄」，**不是「查詢可不可以不帶 shop_id」**；
#   - **業務資料表完全不動**——products／orders／inventory 等的 shop_id 與複合外鍵照舊，
#     隔離的主體本來就是業務資料；
#   - 身分表失去資料庫層跨店保護後，改由 `Current.accessible_shop_ids`（fail-closed）
#     ＋ CI 檢查補回（85 §4 的條件）。
#
# 遷移策略：M0 骨架尚無正式資料，但本 migration 仍寫成**可重跑、且會保留既有列**的形態
# （回填 user_store_assignments），以免有人已在 dev/staging 建過帳號。
class IdentityTablesToOrganizationLevel < ActiveRecord::Migration[8.1]
  def up
    # ── 1. 先建 user_store_assignments：它是「誰能進哪些店」的唯一事實來源 ──────
    #    這張表**自己**保留 shop_id，因為它就是 user × shop 的關聯本體。
    create_table :user_store_assignments do |t|
      t.bigint :staff_member_id, null: false
      t.bigint :shop_id, null: false
      t.bigint :role_id
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false

      t.index %i[staff_member_id shop_id], unique: true, name: "uq_usa_member_shop"
      t.index %i[shop_id staff_member_id], name: "ix_usa_shop_member"
      t.index :role_id, name: "ix_usa_role_id"
    end

    # ── 2. 回填：既有的 (staff_member, shop, role) 組合就是一筆 assignment ───────
    # strong_migrations 無法檢視 execute 內容，需明示安全。
    # 安全理由：純 INSERT ... SELECT 到**剛建立的空表**，不鎖既有表的寫入路徑，
    # 且 staff_members 在 M0 骨架階段列數極小（dev/staging 個位數）。
    safety_assured do
      execute <<~SQL.squish
        INSERT INTO user_store_assignments (staff_member_id, shop_id, role_id, created_at, updated_at)
        SELECT id, shop_id, role_id, NOW(), NOW() FROM staff_members
      SQL
    end

    # ── 3. 拆掉指向這四張表的複合外鍵（必須先拆，否則無法 drop 欄位）──────────
    #    🔴 api_tokens / events 是**業務側**的表，它們保留自己的 shop_id，
    #       只是不能再用複合鍵指向 staff_members。
    # 🔴 以下整段包 safety_assured，逐項安全理由：
    #   - remove_column / remove_index：M0 骨架階段這四張表列數極小，且**本專案尚未上線**
    #     （M7 才是部署線），不存在線上讀寫流量需要考慮鎖表時間；
    #   - remove_foreign_key 必須先於 remove_column，否則 MySQL 拒絕；
    #   - add_index 皆為小表建索引，同上。
    # 🔴 若日後在**有流量的環境**重做同型改造，必須改走線上 DDL（gh-ost/pt-osc）並重新評估。
    safety_assured do
      remove_foreign_key :api_tokens, name: "fk_api_tokens_staff_member_id"
      remove_foreign_key :events, name: "fk_events_staff_member_id"
      remove_foreign_key :sessions, name: "fk_sessions_staff_member_id"
      remove_foreign_key :sessions, name: "fk_sessions_shop"
      remove_foreign_key :staff_members, name: "fk_staff_members_role_id"
      remove_foreign_key :staff_members, name: "fk_staff_members_shop"
      remove_foreign_key :role_permissions, name: "fk_role_permissions_role_id"
      remove_foreign_key :role_permissions, name: "fk_role_permissions_shop"
      remove_foreign_key :roles, name: "fk_roles_shop"

      # ── 4. 四張身分表：拆 shop_id 與其複合索引，改為單鍵 ─────────────────────
      remove_index :sessions, name: "uq_sessions_tenant_id"
      remove_index :sessions, name: "uq_sessions_token_digest"
      remove_index :sessions, name: "ix_sessions_expires_at"
      remove_index :sessions, name: "ix_sessions_staff_member_id"
      remove_index :sessions, name: "ix_sessions_staff_member_id_revoked_at"
      remove_column :sessions, :shop_id
      add_index :sessions, :token_digest, unique: true, name: "uq_sessions_token_digest"
      add_index :sessions, :expires_at, name: "ix_sessions_expires_at"
      add_index :sessions, %i[staff_member_id revoked_at], name: "ix_sessions_member_revoked"

      remove_index :role_permissions, name: "uq_role_permissions_tenant_id"
      remove_index :role_permissions, name: "uq_role_permissions_role_id_permission_key"
      remove_index :role_permissions, name: "ix_role_permissions_role_id"
      remove_column :role_permissions, :shop_id
      add_index :role_permissions, %i[role_id permission_key], unique: true,
        name: "uq_role_permissions_key"

      remove_index :staff_members, name: "uq_staff_members_tenant_id"
      remove_index :staff_members, name: "uq_staff_members_email"
      remove_index :staff_members, name: "ix_staff_members_role_id"
      remove_index :staff_members, name: "ix_staff_members_status_id"
      remove_column :staff_members, :shop_id
      # 🔴 語義改變：email 唯一性由 (shop_id, email) 變成全平台唯一。
      #    ⇒ 一個 email 全平台只有一個帳號，透過 user_store_assignments 進入多間店。
      #    這正是 A 案要換到的東西（85 §2），不是副作用。
      add_index :staff_members, :email, unique: true, name: "uq_staff_members_email"
      add_index :staff_members, :status, name: "ix_staff_members_status"

      remove_index :roles, name: "uq_roles_tenant_id"
      remove_index :roles, name: "uq_roles_name"
      remove_column :roles, :shop_id
      add_index :roles, :name, unique: true, name: "uq_roles_name"

      # ── 5. R12-V3：時區與語言是**使用者層級**（本尊一般設定明文）──────────────
      #    同批 migration 帶上，避免之後再動一次這張表。
      add_column :staff_members, :timezone, :string, limit: 64, null: false, default: "Asia/Hong_Kong"
      add_column :staff_members, :locale, :string, limit: 16, null: false, default: "zh-Hant"

      # ── 6. 重建單鍵外鍵 ──────────────────────────────────────────────────
      add_foreign_key :sessions, :staff_members, name: "fk_sessions_staff_member_id"
      add_foreign_key :role_permissions, :roles, name: "fk_role_permissions_role_id"
      add_foreign_key :user_store_assignments, :staff_members, name: "fk_usa_staff_member_id"
      add_foreign_key :user_store_assignments, :shops, name: "fk_usa_shop_id"
      add_foreign_key :user_store_assignments, :roles, name: "fk_usa_role_id"
      # api_tokens / events 改為單鍵指向 staff_members（它們自己的 shop_id 保留不動）
      add_foreign_key :api_tokens, :staff_members, name: "fk_api_tokens_staff_member_id"
      add_foreign_key :events, :staff_members, name: "fk_events_staff_member_id"

      # ── 7. staff_members.role_id 不再有意義（角色改由 assignment 逐店指派）──────
      remove_column :staff_members, :role_id
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "身分表的租戶歸屬改造不可自動回滾：email 唯一性由 (shop_id,email) 變為全平台唯一，" \
      "回滾會在既有資料上產生無法自動裁決的衝突。要回退請走 B 案（docs/specs/85 §3）並手動處理。"
  end
end
