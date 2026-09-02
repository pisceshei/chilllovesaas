# 100 — 本尊主題編輯器逐面板實測 teardown（2026-09，D79 的 E1）

> 對標＝admin.shopify.com 主題編輯器（2026 春季版）。實測店＝pnrjnw-sy（使用者全權授權，操作一律在
> 現行主題的 Duplicate 副本上）；補走 `docs/research/24` §1（2026-08 Horizon 局部實測）未覆蓋的層。
> 六層：⓪載入紀律 ①按鈕級功能與交互 ②值域窮舉 ③架構深度 ④CSS 量測三段式 ⑤help 雙源 ⑥條件控件三源。
> 🔴 編輯器本體在跨域 iframe（online-store-web.shopifyapps.com）：DOM 不可讀，量測走「截圖＋zoom」與
> 編輯器 CSS bundle（network 面板取 cdn.shopify.com 的 CSS 檔原文）兩路；每項標明來源與取證日期。

## 0. 操作紀錄（時間序，含 URL 去 token）

（逐步填寫）

## 1. Shell／頂欄

## 2. 左欄：面板切換器＋sections 樹

## 3. 右欄：設定面板（逐控件型別 26 型）

## 4. 區段 picker／區塊 picker

## 5. 預覽：裝置切換、inspector、hover 工具列、插入點

## 6. 儲存／發布／undo-redo／快捷鍵／URL 狀態

## 7. 佈景主題設定（全域 settings）與 app embeds

## 8. CSS 量測（token 值表 → 元件量測 → 我方 token 映射）

## 9. help.shopify.com 雙源對照

## V. 待驗證／工具限制
