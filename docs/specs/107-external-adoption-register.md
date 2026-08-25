# 107 — 外部方案採用登記簿

> 依 CLAUDE.md 鐵律 9 的增補條款建立：「外部方案的採用／拒絕逐項登記於
> `docs/specs/107-external-adoption-register.md`」。本檔在 D49（2026-08-25）隨第一個
> 需要登記的採用（OpenCC 字元表）正式建立——早於原定的「隨合併版總方案 R-8 引入」，
> 因為採用先發生了；R-8 屆時直接續用本檔。
>
> **登記門檻**：任何第三方**內容**（代碼、資料檔、字表、schema、詞庫）要進倉庫，
> 必須先有一列。純參考（讀完自己寫）不登記，但授權紅線照鐵律 9：
> GPL 家族禁讀禁抄；MIT／BSD 可參考；Apache-2.0 需使用者知情（專利授權＋NOTICE 義務）。
>
> **每列七欄**：編號／專案／授權（含複驗 URL）／採用內容／落點／義務履行／裁定錨。

## 採用

### OpenCC-1：Open Chinese Convert 字元表（2026-08-25，D49）

| 欄 | 值 |
|---|---|
| 專案 | OpenCC（Open Chinese Convert），<https://github.com/BYVoid/OpenCC> |
| 授權 | **Apache-2.0**。複驗＝<https://raw.githubusercontent.com/BYVoid/OpenCC/master/LICENSE>（2026-08-25 抓取，首兩行逐字 `Apache License` / `Version 2.0, January 2004`） |
| 採用內容 | **僅兩個資料檔**（原樣未修改）：`STCharacters.txt`（簡→繁字元映射，4012 資料行）、`TSCharacters.txt`（繁→簡，4148 資料行）。**不含任何 OpenCC 原始碼**。 |
| 落點 | `lib/opencc/`（連同上游 LICENSE 逐字副本與我方 NOTICE）。消費者＝`app/services/translations/script_detector.rb`（繁簡誤借稽核 `script_mismatch` 的判別核心）。 |
| 義務履行 | ①LICENSE 逐字入庫同目錄 ②NOTICE 載明版權人、來源 URL、抓取日期、三檔 SHA-256（複驗＝`sha256sum lib/opencc/*`）③本登記列。Apache-2.0 §4：redistribution 附授權副本＋標明來源——皆滿足；未修改檔案 ⇒ 無「修改聲明」義務。 |
| 專利面 | Apache-2.0 §3 授予專利授權；資料檔（字元映射表）本身非可專利標的，風險面極小，仍照鐵律 9 走知情裁定。 |
| 裁定錨 | `docs/DECISIONS.md` **D49**（2026-08-25 使用者裁定「引入（連 NOTICE＋attribution 一起入庫）」，回應第 7 包 dev doc §7 的待裁定項）。 |

**刻意不採用（同專案）**：`TWPhrases.txt` 等**詞庫**（詞彙在地化：软件↔軟體）——
那是 `machine_translation`／`script_conversion`（ML-5）的射程，且電商詞覆蓋率未量測
（第 7 包研究輪登記的疑慮）；字形稽核只需要字元表。日後要用詞庫＝新開一列，不得引用本列。

## 拒絕／禁用（鐵律 9 紅線的具名登記）

| 專案 | 授權 | 處置 | 出處 |
|---|---|---|---|
| Vendure（含 admin dashboard） | GPLv3 | **禁讀禁抄禁引用**（污染不可逆） | CLAUDE.md 鐵律 9 增補條款 |
| Spree ≥4.10 | AGPL-3.0 | 同上（AGPL 屬 GPL 家族） | 官方 blog 標題逐字 "Why Spree is changing its Open Source license to AGPL-3.0"（2026-08-25 WebSearch；license.md 直取 404，見第 11 包研究 P11-U15） |
| TinyMCE `develop` 分支 | GPL-2.0-or-later | 一次誤讀已封存（`Schema.ts`，第 7 包研究輪）；讀取結果不得作實作輸入 | 第 7 包研究輪注入登記節 |
| Medusa | 未取證（LICENSE 未取回，P11-U13） | 取證前視同禁 | 第 11 包研究 |
