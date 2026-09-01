# 2026-09-02 Ella 修復 PR-18：section 級 Custom CSS（編輯器 ⑤b 缺項）

## 已完成的工作 (Done)

- 官方取證 2026-09-02：help add-css（「At the bottom of section properties,
  click Custom CSS」／「the CSS is scoped to that section」／section 級
  500 字、theme 級 1500 字上限）＋dev json-templates（「stored in a
  custom_css attribute in the section data」）。
- **渲染面**：`Runtime#custom_css_style`——section data 帶 `custom_css` ⇒
  wrapper 後輸出 `<style data-shopify-custom-css>#shopify-section-{id} {
  rules }</style>`（CSS 巢狀作用域＝後代選擇器語義與官方一致）；
  String/Array 雙收（儲存型別官方未載＝V）；`</` 逸出防 style 閉合注入。
- **編輯器面**：section 設定面板底部（移除區段鈕前——官方位置逐字）
  `<details>` 收合的 Custom CSS textarea（maxLength 500＝官方上限）；
  寫 entry.custom_css 走 applyOp ⇒ undo/URL/draft_page 改即見全部免費
  繼承；空值刪鍵（零殘留）。
- i18n editor.customCss × 5 語。
- 測試 CC1（draft_page 帶 custom_css ⇒ scoped style；未帶 ⇒ 零殘留）＋
  ED21（輸入 ⇒ save payload 含 custom_css）；突變 2/2 殺。
- 🔴 本包與 PR-17 在測試檔同錨插入撞衝突（rebase＋stash pop UU）——
  解法＝兩塊都留、rebase 後合跑 21/21。

## 修改的檔案與核心邏輯 (Changes)

- `app/liquid/theme_engine/runtime.rb`：custom_css_style＋render_section
  wrapper 後接。
- `app/frontend/admin/pages/ThemeEditorPage.tsx`：SectionEntry.custom_css
  ＋面板 details/textarea。
- i18n 五檔；specs（CC1／ED21）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 「規則選 wrapper 標籤本身」的官方邊角（descendant-tag 句）＝CSS 巢狀下
  是後代不含 wrapper 自身——差異登記 V。
- theme 級 Custom CSS（1500 字、settings_data platform_customizations）
  未做——另輪（佈景設定面板側）。
- 儲存型別 V：渲染雙收已備，若後續取證實錘 array 形，編輯器寫入端一行切換。
