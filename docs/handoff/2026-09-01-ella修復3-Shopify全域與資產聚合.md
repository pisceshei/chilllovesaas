# Handoff：Ella 修復 PR-3（2026-09-01）

## ①我改了什麼

六軸診斷 coverage＋console 實錘軸。base＝main（#266 後），分支
`ella/shopify-global-assets`。逐檔＝worklog Changes。

## ②為什麼這樣改

- Shopify 全域注入在 renderer 而非 layout 模板：主題檔不可改（鐵律 9），
  且所有主題共用此 runtime 面。
- 聚合桶掛 runtime（per-render 生命週期）：tag 無法直接寫頁尾，收集/輸出
  分離是唯一乾淨形。

## ③還有什麼沒解決

- coverage 餘項（worklog 列表）；編輯器四連發；主題頁 Preview 流。

## ④下一個人要注意什麼

- 改 tags.rb 的類名先 grep 全部 register_tag 引用（Swallow 波及一次）。
- ShopifyGlobal.script 內是 JS 字面——改動時跑 SG1 且注意 #{} 插值逃逸。
