# 2026-09-02 引擎缺口 PR-2：theme block 包裝／`tag: null`／隱藏 block／section 本地 blocks

分支 `engine/theme-block-wrapper`（base main `553312b0`）。配對 handoff：
`docs/handoff/2026-09-02-引擎缺口-theme-block包裝.md`。收口 hoko 稽核候選「theme block 預設
`<div id="shopify-block-…">` 未輸出」「section 本地 blocks 被靜默丟棄」與 triage 未驗證三項中的
`block-wrapper-id-class`／`disabled-blocks-skipped`（`content_for-blocks-closest-param` 已由既有
ContentFor 的 `closest.*` 參數覆蓋，本包未動）。

## 已完成的工作 (Done)
- `Runtime#block_wrapper`：theme block 預設 `<div id="shopify-block-{id}" class="shopify-block">`；
  `"tag": null` 不包；`tag` 指定元素；`class` 接在 `shopify-block` 後（官方 theme-blocks/schema 逐字
  ＋真店 hoko.vip 2026-09-02 逐字，包裝上無其他屬性）。`content_for 'blocks'` 與
  `{% render child_block %}` 兩條渲染路徑同包。
- `disabled: true` 的 block：不渲染（`render_block` 早退）也不進 `section.blocks`
  （`ordered_block_drops` 跳過）。依據＝help.shopify.com sections-and-blocks「Hide」＋ Kalles Demo
  Data 匯出的 block 級 `"disabled": true`（官方 json-templates 頁只寫 section 級，block 級逐字＝未取得）。
- section 本地 blocks：無 `blocks/{type}.liquid` 的 type 以 section schema `blocks` 定義建
  `BlockDrop`（settings 預設與型別取自該定義），可與 `@theme` 塊混排；`@app`／未知型仍跳過。
- spec `spec/requests/storefront_theme_blocks_wrapper_spec.rb` W1–W6；既有
  `storefront_blocks_schemes_spec` B1／B3 期望改為帶包裝形。fixture `minimal-1.0` 新增
  `blocks/_bare.liquid`（tag null）、`blocks/_boxed.liquid`（section＋class）、
  `sections/blocks-local.liquid`（本地 blocks）與 `templates/index.json` 的 `local` section／隱藏塊。
- 突變輪（鐵律 20.2⑤，逐個套用後 `git checkout --` 還原）：M1 無 tag 鍵不包 ⇒ W1 紅；
  M2 tag null 仍包 ⇒ W2 紅；M3 `section.blocks` 不跳 disabled ⇒ W5 紅；M3b `render_block` 不跳
  disabled ⇒ W4 紅；M4 拔本地 block 分支 ⇒ W5 紅。
- 回歸：`bundle exec rspec spec/requests/storefront_theme_blocks_wrapper_spec.rb
  spec/requests/storefront_blocks_schemes_spec.rb spec/liquid/theme_conformance_spec.rb
  spec/liquid/page_renderer_spec.rb` 綠（TC-M1／TC-K1 不退化）。

## 修改的檔案與核心邏輯 (Changes)
- `app/liquid/theme_engine/runtime.rb`：`ordered_block_drops(data, depth:, local_defs:)`＋
  `local_block_def`；`render_section` 傳入 section schema 的 `blocks`；`render_block` 的 disabled 早退；
  新 `block_wrapper(id, schema, html)`。
- `spec/requests/storefront_theme_blocks_wrapper_spec.rb`：新檔。
- `spec/requests/storefront_blocks_schemes_spec.rb`：B1／B3 期望加包裝。
- `spec/fixtures/theme_engine/minimal-1.0/`：`blocks/_bare.liquid`、`blocks/_boxed.liquid`、
  `sections/blocks-local.liquid` 新檔；`templates/index.json` 加 `local` section 與 b1／b2／b3 塊。

## 尚未完成或需注意的風險 (Pending / TODO)
- `{% render var, k: v %}`（變數＋參數形）：三套 fixture 主題無此用法（`grep -rhoE "render\s+[a-z_]+\s*," test/fixtures/themes`
  無輸出），官方 render 頁只寫字串字面形 ⇒ 本包不動，候選留在 hoko 稽核清單。
- section 包裝的 `shopify-section-group-*` class 與 BEGIN／END 註解（真店有、我方無）＝另一 producer
  （`render_section`），不在本包射程，登記待後續包。
- 設計模式（theme editor）下包裝是否另帶 editor 屬性＝未取得；本包維持只有 id／class。
- block 級 `disabled` 的官方逐字＝未取得（help 頁只有「Hide」語義）；若日後官方明載語義不同再改。
