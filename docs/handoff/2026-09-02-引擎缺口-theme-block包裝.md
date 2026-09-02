# Handoff：引擎缺口 PR-2——theme block 包裝／隱藏 block／section 本地 blocks（2026-09-02）

> 工作包＝分支 `engine/theme-block-wrapper`（base main `553312b0`）。依鐵律 21 四段。
> 配對 worklog：`docs/worklog/2026-09-02-引擎缺口-theme-block包裝.md`。
> 本包是 `docs/handoff/2026-09-02-主題無關conformance與真店切換.md` §④E 排定的第 2 包。

## ① 我改了什麼
- theme block 包裝依官方 theme-blocks/schema（tag 預設 div＋唯一 id、`null` 不包、class 追加）與
  真店 hoko.vip 逐字（`<div id="shopify-block-{id}" class="shopify-block …">`，包裝無其他屬性）；
  `content_for 'blocks'`／`render child_block` 兩路同形。
- block 級 `disabled: true`：不渲染、不進 `section.blocks`。
- section 本地 blocks 進 `section.blocks`（settings 預設取自 section schema 的 block 定義）。
- 驗證：W1–W6 綠；五個突變各自轉紅（worklog）；schemes／conformance／page_renderer 回歸綠；rubocop 綠。

## ② 為什麼這樣改
- 原實作「無 `tag` 鍵＝不包、包了也沒 id」與官方預設相反——主題 CSS／JS 用 `#shopify-block-…`
  定位的一律失效；本地 blocks 被丟掉則是 Kalles 21 個／Minimog 40 個迭代 `section.blocks` 的
  section 直接空掉（`grep -rl "for block in section.blocks" test/fixtures/themes/<theme>/sections | wc -l`）。
- 隱藏 block 與 section 級 `disabled` 同鍵同義：help 頁把 section 與 block 的 Hide 寫成同一操作；
  Kalles 官方 Demo Data 的 block 級 `"disabled": true` 是 Shopify 編輯器匯出的形。
- 被推翻的假設：「`{% render var, k: v %}` 是必修缺口」——三套主題都沒有這個用法，官方頁也只寫
  字串字面形；不修。

## ③ 還有什麼沒解決
- section 包裝的 group class／BEGIN-END 註解、設計模式下包裝屬性、block 級 disabled 的官方逐字
  ——見 worklog Pending。
- 真店 Publish／金標本仍待（前一份 handoff §③：分頁不可見時截圖逾時；hoko.vip 零商品待使用者裁定）。

## ④ 下一個人要注意什麼
- 下一包＝§④E 第 3 包（settings 預設語義：checkbox 無 default ⇒ false；color_scheme 無 default／
  空字串 ⇒ 第一組；select／radio 無 default 先查官方）。
- 改 `minimal-1.0/templates/index.json` 會牽動 `storefront_blocks_schemes_spec`（B1／B3／K1）與
  `page_renderer_spec`——加 section 可以，改既有 `demo`／`iter` 的塊要同步期望。
- 突變輪前先 commit；`ordered_block_drops` 現在有 theme block／本地 block 兩個建構分支，改任一邊都要
  跑 W5（size 同源）。
