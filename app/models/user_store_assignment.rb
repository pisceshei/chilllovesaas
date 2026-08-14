# staff 與 shop 的指派關係——「誰能進哪些店、在該店是什麼角色」的唯一事實來源。
#
# 🔴 這張表是 A 案（裁定 D8／§A G24）的樞紐：身分表升為組織層之後，
# 「這個人屬於這間店嗎」不再由資料庫的複合外鍵回答，改由這張表回答。
#
# 🔴 **它自己保留 `shop_id`**，因為它就是 user × shop 的關聯本體，不是被隔離的業務資料。
# 它**不在** G24 的豁免白名單裡的意義是：它必須帶 shop_id，而不是可以不帶。
#
# ⚠️ 鐵律 2 與 71 §A G24 的白名單原文**曾誤列本表**（2026-08-14 已修正）。
# 若讀到舊版清單裡有 `user_store_assignments`，以本註釋與
# `scripts/check-tenant-isolation.rb` 的 `MUST_HAVE_SHOP_ID` 自檢為準。
#
# 角色為何掛在這裡而不是 staff_members：同一個人在 A 店可以是店長、在 B 店只是客服，
# 角色本質上是 (user, shop) 的屬性而非 user 的屬性（R12 實測本尊亦然）。
#
# @see docs/specs/85-identity-tenancy-decision.md §2
# @see docs/specs/71-admin-parity-sweep.md §A G24
class UserStoreAssignment < ApplicationRecord
  belongs_to :staff_member
  belongs_to :shop
  belongs_to :role, optional: true

  validates :staff_member_id, uniqueness: { scope: :shop_id }
end
