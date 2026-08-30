# Handoff — 結帳線第一包：Calculator＋cart→checkout 快照（2026-08-31）

## ① 我改了什麼

六步方案**步 6**：15 F2 金額引擎（`Checkouts::Calculator`——命名對映見 worklog；
最大餘數法分攤＋Σ恆等、含稅行級反推、Float 即 TypeError、44 組手算表格＋200 組
property）＋`Checkouts::CreateFromCart`（即時價重快照、不扣庫存）＋`Checkout` model
（M0 空表首個消費者）＋POST /checkout／GET /checkouts/:token 端點。
全量 1511/0；突變 c1–c5 全紅。細節＝配對 worklog
`docs/worklog/2026-08-31-結帳線第一包-Calculator與快照.md`。

## ② 為什麼這樣改

- Calculator 零 DB 讀取：把「設定變更不回溯舊訂單」從紀律變成結構（輸入全是快照）。
- 服務命名空間 `Checkouts::`（複數）：`Checkout` model 類與 `module Checkout` 不能並存
  ——Ruby TypeError，不是風格選擇；規格名 `Checkout::Calculator` 的功能契約原樣保留。
- 表格期望值全部手算再跑（質數分攤組首算錯、複核抓出後才首跑全綠）——
  「跑碼回填期望值」會讓表格淪為快照測試，殺不了任何突變。

## ③ 還有什麼沒解決

worklog Pending 逐項（F2.1 合併運費／折扣碼接線／F3–F7 各包／expires·abandoned
無寫入者／presentment 多幣別／Shop#destroy 的 checkouts 清理）。

## ④ 下一個人要注意什麼

- 🔴 **四處重用**：訂單成立／draft order／退款一律吃同一 `Calculator.call` 的 Result
  ——任何「訂單自己再加總一次」都是 F2-2 要杜絕的形。退款退某一行要查
  `discount_allocations` 的行級值，**不得按比例重算**（差 1 分錢；F2 坑 2）。
- 🔴 稅與折扣的進位策略已全域定死（半數進位、行級）——改任何一處進位＝改契約，
  需連表格與 property 一起重審。
- 訂單成立包入口：吃 checkout（token）→ Calculator Result → 訂單＋扣庫存＋outbox
  （鐵律 5：idempotencyKey 必帶、transaction 內禁外部 IO）。
- 重跑：`bundle exec rspec spec/services/checkouts spec/requests/storefront_checkout_spec.rb`。
