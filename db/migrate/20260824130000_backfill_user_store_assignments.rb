# frozen_string_literal: true

# 為既有 staff 補上 `user_store_assignments`，讓「這個人屬於這間店嗎」有資料可答。
#
# 🔴 為什麼需要這支：D8 把身分表升為組織層、拿掉 `staff_members.shop_id` 之後，
# 那道保證要由 `user_store_assignments` 在應用層補回來（`Current#can_access_shop?`）。
# 但**從來沒有任何 production 代碼建立過這張表的資料**——實測正式站
# `assignments=0`。於是那道閘一旦接上，**現有帳號會全部進不去**。
# 本 migration 就是接閘之前必須先鋪的路。
#
# 🔴 對應關係怎麼來的：`shop_id` 已經被刪掉了，資料庫裡**沒有**原始對應。
# 因此只在**能明確推斷**時才補：
#   - 恰好一間店 ⇒ 既有 staff 全部指派到它（這就是 D8 之前的事實：
#     系統實際部署一直是單店，staff 由 seeds 為那間店建立）。
#   - 超過一間店 ⇒ **一列都不建**，並在日誌大聲說明。
#     這不是偷懶，是 fail-closed：猜錯的代價是把 A 店的人放進 B 店，
#     正是這支 migration 要防的那件事。營運者必須手動指派。
#
# `role` 欄位可為 nil：owner 的權限由 `StaffMember#can?` 的 owner 短路提供，
# 不需要角色列。非 owner 沒有角色就等於沒權限（fail-closed），這是對的。
class BackfillUserStoreAssignments < ActiveRecord::Migration[8.1]
  def up
    shop_ids = select_values("SELECT id FROM shops ORDER BY id")

    if shop_ids.length != 1
      say "shops=#{shop_ids.length}：無法明確推斷 staff↔shop 對應，一列都不建（fail-closed）。"
      say "營運者必須手動建立 user_store_assignments，否則既有帳號將無法登入。"
      return
    end

    shop_id = shop_ids.first
    inserted = execute(<<~SQL.squish)
      INSERT INTO user_store_assignments (staff_member_id, shop_id, created_at, updated_at)
      SELECT sm.id, #{shop_id.to_i}, NOW(6), NOW(6)
      FROM staff_members sm
      WHERE NOT EXISTS (
        SELECT 1 FROM user_store_assignments usa
        WHERE usa.staff_member_id = sm.id AND usa.shop_id = #{shop_id.to_i}
      )
    SQL
    say "已為 shop##{shop_id} 補上既有 staff 的指派（#{inserted&.affected_rows} 列）。"
  end

  def down
    # 不刪：刪掉會讓所有人被閘擋在外，比留著危險得多。
    say "不可逆（刪除指派會鎖住所有帳號）。"
  end
end
