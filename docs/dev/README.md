# docs/dev — 功能開發文檔（每個功能一篇，驗收強制項）

每個**新增功能**的 PR 必須同時新增（或更新）本目錄一篇文檔。目的：任何工程師或代理接手時，讀完該篇即可理解、修改、擴充該功能——「以後有人接手」是驗收標準的一部分。

## 命名

`m{里程碑}-{功能}.md`，全小寫、連字號。例：`m0-rails-skeleton.md`、`m1-products-crud.md`、`m2-liquid-engine.md`。

## 模板（複製開始寫）

```markdown
# {功能名}（M{N}）

## 概述
一段話：這個功能做什麼、給誰用、對應 Shopify 的哪個行為。

## 規格出處
- docs/research/22 §…、docs/specs/…、docs/research/28 §…

## 架構與資料流
請求 → controller/resolver → service → model 的路徑；背景 job 與 outbox 事件；快取點與失效時機。

## API
本功能的 GraphQL 操作（對應 docs/research/28 章節表格行）；storefront 端點（如有）。

## 資料表
涉及的表與關鍵欄位／索引（對應 docs/research/06 §7 條目）；migration 檔案名。

## 關鍵取捨
為什麼這樣做而不是那樣做（含併發／冪等／效能考量），與對應的「為什麼」註釋位置。

## 測試
測試檔案位置；併發要害測試怎麼跑；手動驗證步驟。

## 已知限制與 TODO

## 變更記錄
- {日期} {PR#}：建立
```

## 規則

- 繁體中文為主、技術名詞保留英文。
- 修 bug／重構的 PR：更新受影響的既有篇章，並在「變更記錄」補一行。
- PR 描述的「文檔」欄列出本 PR 的 docs/dev 變更；沒有變更要寫明理由（例：純 CI 修改）。
- 驗收方（Claude）逐項檢查：功能 PR 缺對應文檔＝🔴 打回（見 `.github/workflows/claude-review.yml` 硬性紅線）。
