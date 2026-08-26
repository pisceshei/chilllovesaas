# Handoff：S1 Publication 的生命週期 API

> 工作包＝S1（分步方案 `docs/plans/2026-08-26-發布與可見性-分步執行方案.md`）。
> 前一個工作包＝S0（handoff＝`docs/handoff/2026-08-26-S0-管道身分模型.md`，已合併並部署）。
> 配對 worklog＝`docs/worklog/2026-08-26-S1-publication生命週期.md`。

---

## ① 我改了什麼

**目標**：交付 publication 的生命週期 API——建立、更新（含批次加／減 publishable）、刪除。

**輸入 ref**：main `ff17fdc`（S0 PR B 合併後）。分支 `s1/publication-lifecycle`。

**六道關卡都走完了**：官方文檔（13 個 agent 的研究工作流）／後台逐控件實測／抓包／
外部參考（Saleor BSD-3、Medusa MIT；GPLv3 專案全程未讀）／倉庫影響面掃描／開發。

**🔴 研究階段推翻了這一步的預設框架**。分步方案原本把 S1 定義成
「`Publication.operation` 的狀態機與進行中的鎖」，但倉庫掃描發現：

> `resource_publications.published_at` **只在建立時**被寫入，
> 全倉**零 UPDATE、零 DELETE、零 publish／unpublish 入口**。

⇒ 鎖是空掛的（沒有可被鎖住的動作）。射程改成「**先交付那個動作**」。

**驗證輸出**（本輪實跑）：

| 項目 | 結果 |
|---|---|
| `bundle exec rspec` | `1162 examples, 0 failures` |
| `spec/requests/publication_lifecycle_spec.rb` | `29 examples, 0 failures` |
| 六個突變複驗 | 各自 `29 examples, 1 failure`；還原後 `0 failures` |
| `bundle exec rubocop` | 待凍結 tree 後全跑 |

**實作當下被 CI 判準擋下一次**：第一版把 `PublicationLookup` 放進
`app/graphql/mutations/`，被 `spec/graphql/mutation_idempotency_call_spec.rb` 擋下
（該目錄下非 `base_*` 一律必須是帶 `resolve` 的具體 mutation，且明文「不逐檔白名單」）。
🔴 **判準是對的，錯的是放錯層** ⇒ 移到 `app/services/publications/lookup.rb`。

---

## ② 為什麼這樣改

**為什麼三支 mutation 而不是先做鎖**：見上（C-12）。鎖與被鎖的動作必須同批設計，
而動作不存在時，鎖只會變成第二個零消費者欄位——正是 `publications.catalog_id`
空轉兩週那個坑的同型情境，而 S0/S1 這整條線就是來收那個口的。

**為什麼參數形態照抄本尊的 `input:` 而不是我方 28 §0.3.4 的具名參數**：
§0.3.4 的依據是「本尊自 2024-10 起把 `input:` 拆成具名」，但 publication 線
**至今仍是舊式**。鐵律 12 的 1:1 對齊是最高強制，優先於我方的風格偏好。

**為什麼批次上限取「合計」**：官方兩句措辭不同（`simultaneously` vs `per operation`）
且**都沒有指明切分**⇒ 未取得 ⇒ fail-closed 取較嚴的一側，登記為 ours 加嚴。

**為什麼 `ALL_PRODUCTS` 誠實拒絕而不是同步實作**：本尊那條路是非同步的
`AddAllProductsOperation`（帶進度欄位），我方沒有落點。同步跑一遍會在商品多時
把請求跑爆，而且與本尊的非同步語義分岔——那是「假裝做了」不是「做了」。

**被推翻的假設**：

| 假設 | 怎麼被推翻 |
|---|---|
| S1 ＝ 做 `operation_status` 的狀態機（分步方案原文） | 倉庫掃描：沒有可被鎖住的動作 |
| `publishablesToAdd/Remove` 應該像 `productSet` 一樣宣告式全量 | `82` §11.5 實測：本尊發布 modal 一律全部未勾開場 ⇒ 累加語義 |
| 分步方案寫的「各 ≤50」 | 那個「各」是我方寫的，官方沒說 |
| 「本尊 `AppInstallation` 沒有時間戳 ⇒ 那兩欄純 ours」（S0 PR B 的說法） | `82` §11.1 實測：admin UI 顯示 `Installed July 14` ＋ `App history` 時間軸 ⇒ 平台有存，只是不在公開 API 面上。已就地更正（`app_installation.rb`、D52） |
| 批次寫入用 `insert_all` 比較快 | 它繞過唯一那道租戶守衛（多型側無 DB 外鍵）⇒ 改逐列 `find_or_create_by!` |

---

## ③ 還有什麼沒解決

| # | 內容 |
|---|---|
| H-1 | 🔴 **`operation_status` 仍然零寫入者、恆為 null**。type 上有這個欄位**不代表鎖已生效**。做鎖之前要先解掉 U-2（`Publication.operation` 的實地形態，需安裝管道 app——使用者已裁定不安裝） |
| H-2 | **`defaultState: ALL_PRODUCTS` 回 `FEATURE_NOT_ENABLED`**。要做它得先決定進度欄位（`processedRowCount`／`rowCount`）的落點——那是 schema 決策 |
| H-3 | **`sales_catalog_id` 未轉 NOT NULL**（88 §2.1 指派給 S1，語義獨立 ⇒ 另包）。前提是先讓 `20260814200000`／`20260815000010` 兩支既有 migration 的建立順序對齊 |
| H-4 | **`publications.name`／`channel_handle` 欄位未刪** |
| H-5 | **逐資源的 `publishablePublish`／`publishableUnpublish` 未做**（劃給 S5）；契約形態已取證完畢 |
| H-6 | 🔴 **`insert_all` 繞過租戶守衛的全域缺口仍在**。S1 自己那條路徑避開了，但**下一個批次寫入者（匯入器）會再遇到一次**。斷根需 DB 層守衛或 CI 斷言 ⇒ 依 20.4 登記候選（`91` §3.20），待裁定後另開 18.3 PR |
| H-7 | **前端未動**：admin SPA 沒有管道管理介面。本步只交付 API |
| H-8 | 六條未取得（S1-U1～U6）逐條在 dev doc §7；其中 U-1（`ProductBulkPublish` 的 POST body）受現有抓包工具限制（鐵律 14.3 誠實登記） |
| H-9 | **本 PR 尚未 push、尚未部署、尚未線上驗證** |

---

## ④ 下一個人要注意什麼

**入口**：`docs/dev/m2-publication-lifecycle.md`（§3 的四條規則、§4 的刪除裁定、
§6 的誠實聲明）。研究全文＝`docs/plans/2026-08-26-S1-規格草案.md`（自帶證據地位聲明：
那份是三路研究的合併，**未逐位元組複驗**，當硬判準前要複核）。

**重跑方法**：

```bash
bundle exec rspec spec/requests/publication_lifecycle_spec.rb
```

**紅線**：

1. 🔴 **不要把 `publishablesToAdd/Remove` 改成宣告式全量**（未列出＝移除）——
   那與本倉庫 `productSet`／`collectionSet` 家族的直覺相反，但本尊是累加語義。
   改了會讓商家一次勾選清空整個管道。有 spec 盯著。
2. 🔴 **不要把批次寫入改成 `insert_all`／`upsert_all`**——它繞過唯一那道租戶守衛
   （`ResourcePublication#publishable_belongs_to_same_shop`），會寫出跨租戶的列**而不拋錯**。
3. 🔴 **不要在刪除路徑省掉 cache stamp 的 bump，也不要改順序**——
   `dependent: :destroy` 不會 bump，而刪完就查不到受影響的是哪些商品了。
4. 🔴 **不要把 `Product.bump_publications_stamp!` 改成 `update_all` 的 hash 形式**——
   那會推 `lock_version`，把商家開著的編輯表單直接作廢。有 spec 盯著。
5. 🔴 **不要為了遷就放錯位置的檔案去放寬 `mutation_idempotency_call_spec` 的判準**
   （本輪實際遇到過一次；正確處置是把檔案移到該去的層）。
6. 🔴 **不要宣告本尊 `PublicationUserErrorCode` 那 22 個值裡我方不會發出的碼**——
   前端會為它寫一條永遠死掉的分支。刻意不宣告的逐條理由寫在該 enum 檔內。
7. 🔴 **輪詢終止條件照 schema 不照散文**：`ResourceOperationStatus` 恰三值無 `FAILED`，
   而官方指南頁要求 poll 到 `COMPLETE or FAILED` ⇒ 照散文寫會得到一條永遠等不到的分支。

**不得外推的範圍**：本 PR **沒有**做 operation 狀態機、**沒有**做 add-all、
**沒有**動可見性判定、**沒有**動前端。任何「既然 API 有了就順手接上鎖」的改動都不在射程內。

**停止條件**：CI `quality`＋`test` 兩個 job 綠即自合併（D40）。
本 PR **不命中鐵律 18.3**（沒有改 `scripts/`、workflow、`config/ci.rb` 或規範本文）。
合併後照兩步紀律部署 bt3 並線上驗證。
