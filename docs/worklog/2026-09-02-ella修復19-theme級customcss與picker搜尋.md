# 2026-09-02 Ella 修復 PR-19：theme 級 Custom CSS＋picker 搜尋

## 已完成的工作 (Done)

- **theme 級 Custom CSS**（官方 help add-css：Theme settings → Custom CSS、
  1500 字上限、全頁生效；dev json-templates：custom_css 存
  「the settings_data.json platform_customizations object」——取證 2026-09-02）：
  - 儲存：我方收納在 settings hash 的 `platform_customizations` 鍵
    （官方是 settings_data 兄弟物件——我方 ThemeSetting.settings 即
    settings_data 等價層，同鍵對位）；Runtime 初始化即抽離
    （`@settings_data.delete`），🔴 SettingsDrop 值面不曝露它
    （platform_customizations 不是 setting id——TCC1 殺手格）。
  - 渲染：`theme_custom_css_style` 出 `<style data-shopify-custom-css-theme>`
    進 head 尾（無 scope 前綴＝全站語義）；String/Array 雙收（同 PR-18 V）。
  - 編輯器：佈景設定面板底部 Custom CSS textarea（maxLength 1500）走
    setThemeSetting ⇒ themeSettingsUpsert 整份送、draft_page 改即見繼承。
- **picker 搜尋**（⑤a 部分）：新增區段目錄頂部搜尋框，按 name/type
  不分大小寫過濾。
- 測試 TCC1（head style／值面不汙染／draft 路徑）＋ED22（save payload）＋
  ED23（過濾雙向）；突變 2/2 殺（跳過抽離、filter 恆真）。

## 修改的檔案與核心邏輯 (Changes)

- `app/liquid/theme_engine/runtime.rb`：platform_customizations 抽離＋
  theme_custom_css_style。
- `app/liquid/theme_engine/page_renderer.rb`：head 注入。
- `app/frontend/admin/pages/ThemeEditorPage.tsx`：佈景面板底部 textarea＋
  pickerQuery 過濾。
- i18n editor.pickerSearch × 5；specs（TCC1／ED22／ED23）。

## 尚未完成或需注意的風險 (Pending / TODO)

- picker 的分類/「區段·應用程式」tabs/hover 即時預覽（⑤a 其餘）照舊登記。
- 官方「except Checkout」邊界：我方結帳頁不走主題引擎 ⇒ 天然滿足，未另設閘。
- 1500/500 字上限只在前端 maxLength——後端 mutation 級長度驗證未加
  （themeSettingsUpsert 收整份 JSON；超長會被欄位大小自然擋），登記。
