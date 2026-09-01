# 2026-09-02 Ella 修復 PR-25：.liquid 替代模板（?view=）＋{% layout %} 真語義

## 已完成的工作 (Done)

- 4 軸艦隊 password 軸點名項第二半收口（第一半＝PR-10 的 JSON layout 鍵）：
  官方 `{% layout 'name' %}`／`{% layout none %}`（shopify.dev tags/layout
  取證 2026-09-02；預設 theme.liquid）。Ella 消費＝
  `cart.ajax_side_cart.liquid`／`product.ajax_edit_cart.liquid` 等 Ajax
  view 模板全以 `{% layout none %}` 出片段——原 LayoutTag no-op＋
  `template_key_for` 只認 JSON ⇒ **Ajax 側車拿到整頁**（生產原形態）。
- **LayoutTag 真語義**：parse 期取值（none ⇒ false／quoted ⇒ 名字）；
  render 期寫進 registers 掛的可變載體。🔴 Liquid 5 `Registers#[]=` 寫
  overlay、外層 hash 讀不回——必須經預掛的 carrier hash 帶出。
- **`template_key_for`**：JSON 未命中再認 `templates/{key}.liquid`。
- **`render_liquid_template`**：.liquid 模板 body 渲染＋layout override
  三態（false＝片段直出／字串＝`render_named_layout`（缺檔回落預設）／
  nil＝theme.liquid 預設）。
- fixture 加 cart.ajax_side_cart／cart.slim／layout/bare；測試 LV1–LV3；
  突變 2/2 殺（tag no-op ⇒ 2 紅、拔 .liquid 分支 ⇒ 3 紅）。

## 修改的檔案與核心邏輯 (Changes)

- `app/liquid/theme_engine/tags.rb`：LayoutTag。
- `app/liquid/theme_engine/page_renderer.rb`：liquid_template?／
  render_liquid_template／render_named_layout＋render_html 分流。
- fixtures ×3；新 spec `storefront_liquid_view_templates_spec.rb`。

## 尚未完成或需注意的風險 (Pending / TODO)

- 基底 .liquid 模板（老主題 index.liquid 形、無 ?view=）未接——
  `render_template_sections` 對缺 JSON 仍出註解；Ella 全 JSON 基底不受影響，
  老主題支援另輪。
- gift_card.liquid（Ella 有檔）＝gift card 頁未路由（既有登記），非本包射程。
- 生產覆檢（demo `/en-hk/cart?view=ajax_side_cart` 片段形）隨部署後煙測。
