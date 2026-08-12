# 交接 · 2026-08-12 · 依香港基準執行 55 號 8 條 P0

> 補寫。這一輪（commit `9407f83`）當時只 commit 未寫交接，違反 CLAUDE.md 工作方式第一條，事後補齊。
> 上游：`docs/handoff/2026-08-12-jurisdiction-architecture.md`（56 號法域架構）。

---

## ① 我改了什麼

執行 `docs/specs/55-money-tax-event-inventory.md` 的 8 條 P0（G-01～G-08），但**先套用 56 號的香港基準重新分流**再落地。

**處置：已做 6 / 移入 tw pack 2 / 零刪除**

| # | 內容 | 處置 |
|---|---|---|
| G-01 | 部分出貨開立粒度 | 已做（擋單規則補上 pack 條件：**先問法域再問未定案**） |
| G-02 | 折讓累計上限 | 憑證側 → tw pack；**金流側累計檢查落地為可測式子** |
| G-03 | 作廢窗 fallback | 移入 tw pack，router 標 tw-only ＋ 明確宣告 no-op |
| G-04 | 一訂單多發票／不建唯一索引 | 已做（**裁決值從未啟用的 pack 提到核心層並列舉化**） |
| G-05 | COD 未取件退回 | 已做（事件改法域中性 `TaxEvent(sale_uncollected)`） |
| G-06 | 禮品卡稅務時點 | 移入 `jurisdictions.tw.accounting` ＋ **HK 側明確宣告 `false`** |
| G-07 | 抵用金定位 | 已做（HKFRS 15 完整寫出 ＋ 併發安全那一半補進契約） |
| G-08 | 9 支金流 mutation 強制冪等 | 已做（複核 + 補簽名 + 平台域 2 支標 pack-scoped） |

**檔案**：`config/limits.yml` 1086→1185｜`16` 860→985｜`55` 481→515｜`28` 404→435｜`06` 229→255｜`38` 2790→2810｜新增 `57`（517 行）。`docs/design/*.html` 零改動。

---

## ② 為什麼這樣改（含被推翻的假設）

**56 號的分流方向沒錯，錯在落地——8 處，共同點是「測試抓不到」。** 這是本輪真正的產出：

| # | 缺口 | 為什麼危險 |
|---|---|---|
| H-1 | `block_multi_fulfillment_when_undecided: false` **只寫在 limits，唯一呼叫端 16-F5.5(a) 仍是無條件擋單** | 照規格實作，HK 依然卡死所有多次出貨訂單——56 想防的事原封不動還在。**與 55 G-03「掛勾寫了沒接上」是同一形態，剛發現又犯一次** |
| H-2 | G-04 的 schema 裁決值埋在 `tw.enabled: false` 的 pack 裡 | **建表的人不會去讀一個未啟用的 pack**。schema 級不可逆 |
| H-3 | 56 全檔 grep `G-08` **命中 0**——「法域無關」是由缺席推得的 | 因此漏掉 `required_for_platform` 那 2 支**是 pack-scoped**（統一發票專屬）。做成無條件斷言，HK 首發 schema 快照測試會紅 |
| H-4 | G-02 只說「金流側要留著」，55 §A.2 只有式子沒有 SQL／錯誤碼／併發情境 | 「留著」沒有落地物等於沒留 |
| H-5 | G-05 根因被讀窄成「憑證面的事」，真正根因是 router 入參語義不成立 | HK 下照舊走 router 會產生**金額 0 的假退款列**，因為沒有折讓可看**反而更難發現** |
| H-6 | G-06 旗標從 HK 移走，但 **HK 側沒寫出對應的 `false`** | **違反 56 自己訂的原則 2「未宣告 ≠ none」**。移走不等於關閉 |
| H-7 | G-07 只涵蓋稅務那一半，**併發安全那一半（法域無關）完全沒提** | 容易被讀成「整條移到會計層了」，而那半是顧客資損 |
| H-8 | G-07d 的 J-03 只登記「兩鍵 null + verify」，沒寫定案前行為 | 與 G-06 完全相同的病根 |

**兩條技術結論值得單獨記住：**

**G-02 的超額退款路徑也必須走條件式 UPDATE。**
```sql
UPDATE orders SET refunded_total_cents = refunded_total_cents + :amount_cents
 WHERE id = :order_id AND shop_id = :shop_id
   AND refunded_total_cents + :amount_cents <= captured_total_cents;
```
超額路徑只把上界換成 `captured_total_cents + :approved_over_refund_cents`——**若改走普通 UPDATE，就在最需要保護的地方失去併發保護**。`affected == 0` 分兩碼：`REFUND_EXCEEDS_MAXIMUM_REFUNDABLE`（走二次確認）／`REFUND_CONCURRENT_MODIFIED`（原樣重試），HTTP 恆 200。
**不做 DB CHECK**——會擋掉 `46c:223` 允許的合法超額退款。

**G-07 的 HKFRS 15 分錄方向是唯一真相。** 售出儲值 → 合約負債↑、收入 0；兌換 → 負債↓、認列收入；**退款回補至卡片 → 負債↑，不是收入沖銷**。做反會同時少計負債與少計收入，**兩個錯誤互相抵銷、恆等式抓不到**，只有對帳到現金才會發現。落庫 `contract_liability_entries`，唯一鍵 `(shop_id, source_type, source_id, direction)`，與餘額變動同 transaction；恆等式 `Σ↑ − Σ↓ − Σbreakage == Σ outstanding_balance_cents`。

---

## ③ 還有什麼沒解決

- **breakage 估計方法**維持 ⚠ V-28 未查證，`defer_all`。但已要求**建兌換率 rollup**，否則 V-28 永遠結不了案（沒有資料就無法估計）。
- **抵用金定位** ⚠ V-29 未定，定案前 `record_with_undetermined_basis`、**不擋發放與使用**。
- **三條新待查證，都跟實際是 HKD/MYR 多幣別有關**，不擋開發但擋（會計意義上的）結帳：
  - **V-34** 合約負債的計量幣別與匯率：發卡日還是兌換日？匯兌損益落哪？56 的分錄表隱含單一幣別。
  - **V-35** 超額退款在 HKFRS 下是收入沖銷（可能為負）還是費用？這是有權限就能做的日常操作。
  - **V-36** `jurisdiction_capability_skips` 的保留年限——它是稽核證據，該對齊 PDPO 日誌保留（V-26）還是收據保存年限？**兩個參照物本身都還沒定案**，而該表在 HK 是高頻寫入。
- 56 號 §D 遷移計畫的 **P0-2/3/6/8/9 尚未執行**（本輪只做了與 55 號 P0 交集的部分）。

---

## ④ 下一個人要注意什麼

1. **「移到別的 pack」不等於「在本 pack 關閉」。** H-6 就是這樣發生的：旗標搬走了，HK 側沒寫 `false`，於是變成「未宣告」——而 56 自己的原則 2 明講未宣告要 reject。**每次搬移，兩邊都要寫。**

2. **旗標寫進 `limits.yml` 不代表生效。** H-1 的教訓：一定要回去確認**呼叫端真的讀了它**。建議之後所有新增的行為旗標，都在規格檔留一行「唯一呼叫端：<檔案:章節>」。

3. **不可逆的決定不要放在未啟用的 pack 裡。** schema、唯一索引、列舉值這類東西，即使是某法域專屬的動機，**結論也要提到核心層**（H-2）。

4. **「法域無關」要有正面證據，不能由缺席推得。** H-3 就是 grep 命中 0 卻當成「無關」。

5. **本輪唯一動到 schema 語義的是 G-04（不得建唯一索引）與 `contract_liability_entries` 的唯一鍵**。M4 建表前務必先讀 `docs/research/06-data-model.md` §7.1。

6. 交付物 `docs/specs/57-p0-hk-baseline-fixes.md` 逐條記了「55 原結論 → 56 分流 → HK 下實際做什麼 → 改哪些行 → 測試案例」，追溯註釋 16 處分佈在 5 個檔案。
