# 2026-09-04 主題編輯器 E11：Announcement bar 第二輪（部署後並排複驗的兩項收斂）

分支 `editor/e11-announcement-bar-r2`（自 main `17621f57`）。規範：`docs/dev/e10-theme-editor-announcement-bar.md` §3（E11 註）、
`docs/dev/e5-theme-editor-pickers.md`（Generate 條）；證據 `docs/dev/external-facts.md` §G16 E11 追加；未取得 `docs/specs/91-pit-register.md` §3.78 E11 追加。

## 已完成的工作 (Done)

- E10 部署後在 demo 店同 block 並排複驗（使用者 Chrome 登入態）：樹列名、面板控件單列／分段／toggle／色票、預覽 chip 與圖示工具列、
  Add block「Header」群皆與本尊一致；並列出第二輪差異（scratchpad audit §G 七項）。
- 本包收兩項有真店證據、不需本尊分頁的差異：
  1. color 列：本尊只有色票＋hex，我方多一顆動態來源（Database）圖示 ⇒ 移除；
  2. block 級 Add block 選擇器：本尊無「Generate」列（兩層皆無），我方有 ⇒ 只在 section picker 顯示。
- 我方面板量測（demo，JS）：右欄 292px、列高 48、數字框 60×28、分段項高 24、toggle 32×18、標籤 13px（font-weight 受本機 Chrome 注入污染不採）。

## 修改的檔案與核心邏輯 (Changes)

- `app/frontend/admin/editor/SettingControls.tsx`：`ColorControl` 去 `<Database>` 圖示。
- `app/frontend/admin/editor/SectionPicker.tsx`：Generate 列與分隔線只在 `kind === "section"`。
- `app/frontend/admin/pages/ThemeEditorPage.test.tsx`：ED54 斷言 block picker 無 `.cl-picker__generate`；ED45 斷言色票鈕內無 svg。
- 文檔：external-facts §G16 追加、91 §3.78 追加、e5 doc Generate 條、e10 doc §3 註。

## 尚未完成或需注意的風險 (Pending / TODO)

- 待本尊分頁前景：右欄寬／標籤欄（我方 292px、「Show separator line」折行，本尊單行）、color_background「No color chosen」彈層內容、
  section 級 Add section 是否仍有 Generate、Remove block 列捲到底的形、面板字級（本機量測受污染，改在本尊 zoom 換算）。
- Theme Settings 收合區規則仍未取得（91 §3.78）。
- 影響面：所有 color 設定列（全編輯器）不再有動態來源圖示；有相容 metafield 定義時本尊是否顯示圖示未取得（V）。

## 閘門（凍結 tree 後全跑，2026-09-04 本機）

| 閘門 | 結果 |
|---|---|
| `bin/rubocop` | 979 files inspected, no offenses detected |
| `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | exit 0 |
| doc-claims／doc-claims-rules／tenant-isolation／tokens-sync／baseline-raise／lint-prototype／lint-rules／exec-bits／exec-bits-rules | 全部 exit 0（commit 後再跑 doc-claims，見 PR body） |
| `pnpm typecheck` | exit 0 |
| `pnpm test` | 412 passed |
| `bundle exec rspec` | 2103 examples, 0 failures |
| 突變 M112／M113（scratchpad `mutate_e11.py`，commit 後跑） | 輸出貼於 PR body |
