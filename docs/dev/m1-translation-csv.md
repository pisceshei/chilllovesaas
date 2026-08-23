# m1 — 翻譯 CSV 匯出／匯入 ML-5b（第三套 CSV）

> 使用者 2026-08-23 指令：「做數據庫主要是為了之後對語言商品數據的導出或者導入」。
> 依據：`docs/specs/67-multilingual.md` §E.6（(a) 空白語義與覆寫旗標、(b) 檔案契約）＋ `config/limits.yml` `i18n.export` / `i18n.import`。
> 每單元四件事（鐵律 12.4）：①是什麼 ②功能與值域 ③怎麼做 ④跨功能影響。

## 1. 為什麼翻譯是「第三套」CSV（不是塞進商品 CSV）

四條理由（§E.6）：
1. **鍵不同**：商品 CSV 的鍵是 handle＋變體行；翻譯的鍵是 (resource_type, resource_id, locale, field)。塞進商品 CSV 要為每語言加一組欄位——加第 4 個語言時整張表要改。
2. **範圍不同**：翻譯還涵蓋頁面、選單、主題字串、通知範本——這些根本不在商品 CSV 裡。
3. **生命週期不同**：翻譯檔會**出境**（交給譯者／TMS）再回來，所以需要商品 CSV 沒有的 `source_digest`。
4. **空白語義不同**：商品 CSV 空白＝洗掉（61 §6.1）；翻譯 CSV 空白＝**不動作**（69 §V-182 查到本尊用顯式勾選框，不用空白表達刪除）。

## 2. 檔案契約（匯出 8＋1 欄）

`resource_type, resource_gid, field_key, locale, market_handle, status, source_text, translated_text, source_digest`

- ②`status` ∈ translated／outdated／untranslated（對齊本尊三值）；**純輸出**，匯入時忽略（V-201）。
- ②`market_handle` 恆空白（裁定 10：不做市場級內容覆寫）；保留欄位只為讓本尊的檔案能直接匯入而不必手工改欄。匯入時非空 ⇒ 拒絕該列並明示理由。
- ②未翻譯的欄位**也出列**（`status=untranslated`、`translated_text` 空）——否則譯者不知道有什麼要翻。來源沒有內容的欄位不出列（避免空原文噪音）。
- ③`source_digest` 是我方獨有：回匯時比對它就知道譯者照的是哪一版原文。
- ④可選語言／欄位（`selectable_locales` / `selectable_fields`）：不只是方便，它決定 `overwrite_existing` 的**作用範圍**（範圍由表頭界定），是縮小覆寫爆炸半徑最直接的手段。

## 3. 匯入語義（本包最重要的一節）

🔴 **四種「不變更」的表達，四種都必須各自成立**：

| 情況 | 行為 | 為什麼 |
|---|---|---|
| 列缺席 | 該 (resource, locale, field) 完全不處理 | 譯者只交回部分列是常態 |
| 欄位缺席（表頭沒有） | 該欄對全檔不處理 | `overwrite` 的範圍靠表頭界定 |
| 儲存格空白 | **本列本欄不做任何事**（不是刪除） | 刪除不可逆，不該由「儲存格是空的」這種易誤觸狀態觸發 |
| 有值 ∧ 未勾 overwrite | 既有譯文保持原值（只補新的） | 預設保守失效，與 56／58／65「未宣告 ≠ 預設」同一條哲學 |

- 🔴 **清空的唯一手段＝寫 `__CLEAR__`**（`explicit_clear_token_is_alias_of_blank: false`——這兩鍵是同一語義的兩面，只改一個不會被任何測試抓到）。
- 🔴 **缺 `source_digest` 欄 ⇒ 整檔拒絕**：沒有它無法判斷譯者照的是哪一版原文。
- 🔴 **digest 不符 ⇒ 仍然寫入**（譯者是照當時原文翻的，內容多半可用）**但標 `outdated` + `review_required`** 並計入報告——不得靜默當成最新。
- 逐行獨立 transaction（`per_row_transaction`）＋逐行錯誤報告：一列壞掉不讓整份檔案回滾。
- 清空與覆寫都寫稽核軌（目前以結構化日誌承載：誰、何時、哪一列、舊值是什麼；專用資料表屬後續包）。

## 4. 兩步匯入與預覽數字

`POST /admin/translations/preview`（dry_run，只算不寫）→ 商家看四個數字 → `POST /admin/translations/import`。
- ④🔴 覆寫要與清空**分開計數**的理由：「明示動作」只解決了『是不是故意的』，沒有解決『知不知道有多大』——勾一個框而不知道會蓋掉多少既有譯文，與誤刪一樣不可接受。
- UI 另顯示 `digestMismatch` 筆數（「有 N 筆是照舊版原文翻的，將標記為需要覆核」）。

## 5. 為什麼走 HTTP 而不是 GraphQL

檔案下載（`Content-Disposition`）與上傳（multipart）走 HTTP 語義才自然；admin SPA 的**資料讀寫**仍然只走 GraphQL（D5）。這兩支 action 是**檔案通道**，不是資料 API——路由必須排在 `admin/*path` 的 SPA catch-all **之前**，否則會被吃成 SPA 頁面。

## 6. 已知邊界

- 匯出目前同步產出；非同步＋email 交付（`i18n.export.async_delivery`）屬後續包（資料量大時才需要）。
- 稽核軌是結構化日誌，不是資料表。
- 射程＝PRODUCT／COLLECTION × 四欄位；頁面／選單／主題字串隨各自模組落地時加進 `resource_type` 值域即可（**不需要改 CSV 格式**）。
- `csv` 自 Ruby 3.4 起是 bundled gem 且不再預設 require ⇒ 已加進 Gemfile。
