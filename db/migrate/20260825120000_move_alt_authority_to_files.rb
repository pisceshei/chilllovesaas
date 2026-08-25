# frozen_string_literal: true

# D48（2026-08-25 使用者裁定「所有的都跟 Shopify」）：alt 權威從 `media.alt_text`
# 遷回 `files.alt_text`。
#
# ①**為什麼是資料遷移不只是改程式**：第 27／28 包期間已經有列在寫 `media.alt_text`
#   （媒體卡的 alt 就地編輯、`productCreateMedia` 的 `alt` 參數）。程式改成只讀
#   `files.alt_text` 之後，那些使用者已經打過的 alt **會從畫面上消失**——不是壞掉，
#   是讀錯欄位。⇒ 必須把它們搬上去。
#
# ②🔴 **衝突處置＝取最早的非空值，其餘保留在原欄不動**。
#   同一個 file 被多個 media 引用、各自有不同 alt 時，遷移必須挑一個。三個候選：
#   ⓐ最早（`media.id` 最小）ⓑ最晚 ⓒ最長。選 ⓐ 的理由是**可預測且可解釋**：
#   「第一次為這張圖寫的說明」是使用者能理解的規則；ⓑ 會讓後來隨手填的覆蓋掉
#   認真寫的，ⓒ 是把「長」當成「好」的假設。
#   🔴 落選的值**不刪**（`media.alt_text` 欄保留），使用者若發現搬錯了，
#   原始資料還在，可以人工救回。
#
# ③**只填空的**：`files.alt_text` 已有值時不覆蓋——那是使用者在檔案庫直接寫的，
#   比從 media 推上來的更接近「檔案層 alt」的本意。
#
# ④`media.alt_text` **不刪欄**（同 B4 `product_variants.sku` 的先例，schema drift 最小）：
#   ⓐ本次遷移的落選值要留著可救ⓑ刪欄是不可逆操作，而遷移的正確性要等線上驗收才確認。
#   🔴 停用的**機械**保證目前沒有：依鐵律 20.4，新增 `scripts/` 判準要先登記候選、
#   取得使用者裁定、另開 18.3 PR——候選已登記 `docs/specs/91-pit-register.md` §2。
#   在那之前的防線是 spec（本包把每一條 per-product alt 斷言反轉成 per-file）。
class MoveAltAuthorityToFiles < ActiveRecord::Migration[8.1]
  def up
    # 逐店逐檔取「最早那筆非空 media.alt_text」，填進 files.alt_text 的空位。
    # 🔴 走單句 UPDATE…JOIN 而不是 Ruby 迴圈：遷移不得依賴 model
    #    （model 之後會改成不再讀 media.alt_text，舊遷移就跑不起來了）。
    # `safety_assured`：strong_migrations 看不進 execute，要人明說安全。
    # 本句只 UPDATE 既有列的一個 nullable 欄、有 WHERE 限縮在空值列、不加鎖結構，
    # 且本表現況列數是十位數（demo 站 14 列）——不是長交易風險。
    # `safety_assured`：strong_migrations 看不進 execute，要人明說安全。
    # 本句只 UPDATE 既有列的一個 nullable 欄、有 WHERE 限縮在空值列、不加鎖結構。
    #
    # 🔴 **不用 `GROUP_CONCAT` 取第一筆**：它受 `group_concat_max_len` 限制
    #    （MySQL 預設 1024 **bytes**），而 alt 上限是 512 **字元**——中文一字 3 bytes，
    #    512 字就是 1536 bytes，**第一筆本身就會被截斷**。截斷後寫進 files.alt_text
    #    是靜默的資料損壞（值還在、但少了尾巴）。改用相關子查詢，沒有長度上限。
    safety_assured do
      execute(<<~SQL.squish)
        UPDATE files f
           SET f.alt_text = (
                 SELECT m.alt_text
                   FROM media m
                  WHERE m.shop_id = f.shop_id
                    AND m.file_id = f.id
                    AND m.alt_text IS NOT NULL
                    AND m.alt_text <> ''
                  ORDER BY m.id
                  LIMIT 1
               )
         WHERE (f.alt_text IS NULL OR f.alt_text = '')
           AND EXISTS (
                 SELECT 1
                   FROM media m2
                  WHERE m2.shop_id = f.shop_id
                    AND m2.file_id = f.id
                    AND m2.alt_text IS NOT NULL
                    AND m2.alt_text <> ''
               )
      SQL
    end
  end

  def down
    # 🔴 **不還原**：本遷移只填空位、不覆蓋、不刪來源，落選與被填的值都還在
    #    `media.alt_text`。要回到舊語義只需把程式改回讀 media 那一欄；
    #    把 `files.alt_text` 清空反而會刪掉使用者在檔案庫直接寫的 alt。
    raise ActiveRecord::IrreversibleMigration,
          "只填空位、未覆蓋任何值；回退方式是改讀取端，不是清 files.alt_text（見檔頭④）"
  end
end
