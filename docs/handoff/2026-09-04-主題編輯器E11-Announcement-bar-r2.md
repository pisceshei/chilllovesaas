# Handoff：主題編輯器 E11 Announcement bar 第二輪（2026-09-04）

配對 worklog：`docs/worklog/2026-09-04-主題編輯器E11-Announcement-bar-r2.md`。

## ① 我改了什麼

- 目標：E10 合併部署後用使用者 Chrome 在 demo 店與本尊並排複驗，收斂剩餘差異中「有真店證據、不需本尊分頁再驗」的兩項。
  輸入 ref：main `17621f57`；分支 `editor/e11-announcement-bar-r2`。
- 做了：color 列去動態來源圖示；block 級 picker 去 Generate；ED54／ED45 斷言；四份文檔追加。
- 遇到的問題：本尊編輯器分頁在複驗中途被切到背景（`visibilityState=hidden`），color_background 彈層、Add section 的 Generate、右欄寬量測
  三項未能點驗 ⇒ 登記待驗，不憑推測改。
- 驗證：見 worklog「閘門」。

## ② 為什麼這樣改

- 只做有證據的兩項：color 列八個實例皆無圖示、兩層 block picker 皆無 Generate（同日截圖）；其餘留待實測。
- Generate 保留在 section picker：8 月觀察（100 §V V13）仍是唯一證據，未證偽前不移除。

## ③ 還有什麼沒解決

- 右欄寬／標籤欄折行、color_background 彈層、Add section 的 Generate、Remove block 列形、面板字級——待本尊分頁前景後一輪處理。
- Theme Settings 收合區規則（91 §3.78）。

## ④ 下一個人要注意什麼

- 複驗入口：`https://demo.chilling.com.hk/admin/themes/1/editor?section=announcement_bar_4tGfEp&block=group_announcement_bar_PeTpTw`
  與本尊 `…/themes/143506604135/editor?section=sections--19774792466535__announcement_bar_4tGfEp&block=<同路徑>`；本尊分頁必須在前景。
- 本機 Chrome 量 font-weight 會被擴充功能注入的 `500 !important` 污染（memory `measurement-env-contamination`），字級量測改用本尊 zoom 換算。
