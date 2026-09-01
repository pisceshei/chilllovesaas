# 2026-09-01 G4 步 16e2：code editor UI

## 已完成的工作 (Done)

- `/admin/themes/:id/code` CodeEditorPage（官方形取證 2026-09-01：help
  edit-theme-code＋dev code-editor）：檔案樹按型分資料夾（官方 sidebar
  organizes by type；DIR_ORDER 八目錄）＋多 tab＋🔴 unsaved dot（官方
  "a dot displays next to the tab name"）＋per-file save（按鈕＋官方
  Cmd/Ctrl+S 快捷鍵）＋STALE 衝突 toast。
- 寫回走 16e1 themeFileUpsert（帶 lockVersion 底版——CE2/MC-1 紅證：不帶
  底版＝並發互蓋暗門）；`fileLockVersion(path:)` 新讀面（F8：無列 null）。
- 🔴 templates/*.json 與 config/settings_data.json 唯讀（CE3/MC-2 紅證）：
  雙真相源禁令的前端半場——後端白名單會拒，但前端可編輯＝使用者輸入被
  靜默丟棄；binary（body null）同樣唯讀。
- StorePage 動作列加「編輯代碼」（41 §634 選單項）；i18n 14 鍵 ×5。
- 突變 3/3 殺（MC-1 lockVersion／MC-2 唯讀守衛／MC-3 dot 清除）。

## 修改的檔案與核心邏輯 (Changes)

- 新：CodeEditorPage.tsx、CodeEditorPage.test.tsx（CE1-3）。
- 改：theme_type（fileLockVersion）、theme_file_overlay_spec（F8）、App.tsx
  路由、StorePage（Edit code 動作）、i18n ×5、admin.css（.cl-code__*）。

## 尚未完成或需注意的風險 (Pending / TODO)

- textarea 素編輯器（鐵律 1：不引入未討論編輯器依賴）——語法高亮／Theme
  Check 紅線／格式化／跨檔搜尋／Timeline 版本歷史＝91 §3.71-72 登記。
- 16e3 候選＝new file／rename／delete（官方右鍵選單形已取證）。
- 生產煙測：部署後開 code editor 改 snippet→save→前台變→還原自清。
