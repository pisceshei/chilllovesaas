# m1 — 商品系列 ML-3（含多語言）

> 依據：`docs/plans/2026-08-23-多語言方案.md` §9（ML-3）；`docs/specs/13` §F4（手動/智慧二分）；67 §C.2（譯文共表）。
> 每單元四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. 資料模型

| 表 | 角色 | 關鍵紀律 |
|---|---|---|
| `collections` | 系列本體（title／handle／description_html／seo_*／collection_type／sort_order／**lock_version**） | 本包補 `lock_version`（migration `20260823120000`）：缺它時兩人同時編輯會靜默互蓋，含譯文 |
| `collection_products` | **手動系列**的成員 join，`position` 為顯示序 | 🔴 智慧系列**不寫**這張表——成員是規則的函數，物化就有兩個真相 |
| `collection_rules` | 智慧系列條件（column_name／relation／condition_value／position） | v1 只建模與讀取；求值引擎屬後續包 |
| `translations` | 譯文，**與商品同一張表** | `resource_type = "COLLECTION"`，其餘完全相同 |

②值域：`collection_type` ∈ manual／smart；`sort_order` ∈ manual／best_selling／title_asc／title_desc／price_asc／price_desc／created_desc／created_asc。

## 2. `collectionSet`（與 productSet 對稱）

- ①建立與更新同一支；全樹送出；`lockVersion` 涵蓋整棵樹（含譯文）。
- ②`productIds` 宣告式：未列出＝移除、順序＝陣列順序。🔴 **智慧系列一律忽略 productIds**（收下它＝製造第二個真相）。
- ③譯文走**同一個** `Translations::Upsert`（只換 resource_type）；handle 走同一個 `HandleGenerator`；說明走同一個 `sanitize_description_for`。
  🔴 各寫一份的代價不是重複碼，是**語義漂移**——兩邊對「空字串＝清除」的解讀遲早不同。
- ④錯誤碼：`BLANK`／`TOO_LONG`／`INVALID`／`HANDLE_TAKEN`／`STALE_OBJECT`／`NOT_FOUND`／`LOCALE_NOT_ENABLED`。

### 兩個實作缺口（spec 抓到，已修）
1. 🔴 `sync_members!` 原本用 `Product.where(id: ids).pluck(:id)` 當順序來源——那是 **DB 順序**不是送入順序，症狀是「拖曳排序存檔後順序又跳回去」。改成用原陣列排序、只用查詢結果做存在性過濾。
2. 🔴 handle 衝突有**兩條路徑**（model uniqueness 驗證 vs DB 唯一索引），原本只轉了後者 ⇒ 單機測試回 `INVALID`、併發才回 `HANDLE_TAKEN`。改成 `translate_record_invalid` 統一轉碼。
3. 🔴 **成員 ID 解析不出來或查無此商品時原本被靜默丟掉**（線上驗收時傳裸整數才發現）。宣告式 API 下靜默丟棄是最糟的失敗形態：存檔回「成功」、成員卻少一個，商家要到前台才發現。改成回 `INVALID`（格式不對）／`NOT_FOUND`（已刪除或別店 GID），整棵樹回滾。
4. 🔴 **巢狀交易回滾**：`ActiveRecord::Base.transaction` 若併入外層（joined），
   「block 內 raise、block 外 rescue」**什麼都不會回滾**。實測（2026-08-23，MySQL 8.4／Rails 8.1）：
   joined 殘留列數 1、`requires_new: true` 為 0。v1 沒有外層交易所以現在剛好是對的，
   但那取決於呼叫者 ⇒ 兩條路徑都加 `requires_new: true`。
   ⚠️ **request spec 驗不到這件事**——RSpec 測試交易是 `joinable: false`，兩種寫法都綠；
   守衛在 `spec/services/catalog/save_collection_spec.rb`（已做突變驗證：拿掉 `requires_new` 該例轉紅）。

## 3. GID 解析擴充

`ChillloveSchema.object_from_id` 原本硬編 Product；本包改成 `RESOLVABLE_TYPES` 對照表並補 `resolve_type`。
🔴 兩處要一起改——只改一邊的症狀是「query 回 null 但 mutation 寫得進去」（或反過來），錯誤訊息完全看不出原因。

## 4. 前端

- `/admin/collections` 列表（keyset＋IndexTable，與商品同一套）；成員數由 `Collection::MEMBER_COUNT_SELECT`
  相關子查詢**一次撈完**——列表上限 250（`limits.yml`），逐列 COUNT 就是單一請求打 250 次 DB；
  單筆讀取（編輯頁）沒有那個 select，`CollectionType#products_count` 退回逐筆 COUNT。
  測試以「數 SQL」斷言（`spec/requests/collection_set_spec.rb`「不逐列 COUNT」一例）——回傳值正確的 N+1 一樣是 N+1。
- 🔴 智慧系列的商品數顯示 `—` **不是 0**——規則引擎落地前我方不知道成員數，顯示 0 是在說一件假的事。
- `/admin/collections/new`／`/:id` 編輯頁：標題堆疊式三語、說明與 SEO 分頁式，全部用**同一個** `LocalizedField`；SaveBar／dirty／離頁攔截與商品頁共用。
- 智慧系列選起來時顯示「成員由規則決定，規則編輯器在後續里程碑開放」——不放一個編不了的條件 UI。
  🔴 **2026-08-26 更正（第 11 包 delta 審查 F4）**：上一句只在**建立頁**成立。型別
  **建立後不可變**（本尊官方逐字，取證 2026-08-26："You can't change an automatic
  collection to a manual collection."），伺服端硬拒 ⇒ 既有系列的「類型」下拉一律
  `disabled`、hint 改成不可變說明，且存檔 payload **不帶** `collectionType`
  （宣告式契約「缺席＝保持現值」）。可翻的控件配上必定失敗的伺服端，症狀是
  「改標題卻跳型別錯誤且永遠存不進去」——被拒的值留在表單狀態裡毒化後續每一次存檔。
  ⚠️ **V 項（待實測）**：本尊在**既有系列**編輯頁把型別呈現成什麼形態（隱藏／唯讀文字／
  停用下拉）尚未親自點擊複驗，本輪只依官方語義選了「停用並說明」這個安全形；
  形態對齊留待系列模組的 parity 輪（鐵律 12.1）。

## 5. 匯入匯出

Collection 的譯文**自動被翻譯 CSV 涵蓋**（`resource_type=COLLECTION`）：匯出時傳 `resource_type=COLLECTION` 即可，格式與商品完全相同——這正是「譯文共表」設計的直接紅利，不需要為系列再寫一套 CSV。

## 6. 已知邊界

- 智慧系列規則編輯器與求值引擎未做（`collection_rules` 只有模型）。
- 手動成員的商品挑選器 UI 未做（API 已支援 `productIds`；v1 靠匯入或 API 設定）。
- 71-R8-V4（2026 本尊的「來源」卡概念 vs 我方手動/智慧二分）仍待裁定——`collections` 表兩種都撐得住（84 §2 B-4），不影響本包。
- 系列的發布（channels）沿用 `resource_publications`，UI 未接。
