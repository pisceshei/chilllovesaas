# 2026-09-03 主題編輯器 E10：Announcement bar 逐控件對照與修法

分支 `editor/e10-announcement-bar`（自 main `0f553370`）。規範 `docs/dev/e10-theme-editor-announcement-bar.md`；證據 `docs/dev/external-facts.md` §G16；
未取得 `docs/specs/91-pit-register.md` §3.78；E4 規範追加 `docs/dev/e4-theme-editor-settings-panel.md` §E10。

## 已完成的工作 (Done)

- 本尊實測（真店副本主題，Chrome 前景分頁）：Announcement bar section → `_group-announcement-bar` → `_group-announcement` → `_announcement-text`
  四層的右欄控件、樹列、URL、Add block 選擇器、「…」選單、預覽覆疊逐項記錄（§G16）；官方 input-settings 的 select 分段／下拉三條件逐字。
- 我方 demo 同 section 並排，抓到 7 項差異（dev doc §2）並全部修：
  1. section schema 的 theme block **引用形**後端解析（先前面板退成原始鍵文字框、樹列名原始 type）；
  2. Add block 分類退 preset `category`（「Header」）；
  3. `select` 分段控制規則（`segmentFits`，真店六例校準，含全形字寬）；
  4. 面板「標籤｜控件」單列形（range／select／radio／checkbox／color／color_background／color_scheme／text_alignment）；
  5. 「Remove block」不帶 id；6. 樹列名不截只截摘要；7. 預覽工具列圖示鈕＋選中 chip（chip 貼框內左上）。
- 對表結果：見「閘門」段與 PR body；部署後在 demo 店並排複驗（dev doc §5）。

## 修改的檔案與核心邏輯 (Changes)

- `app/graphql/types/theme_type.rb`：`block_defs_for` 引用形 ⇒ theme block 定義（`limit` 留引用處）；`theme_block_defs` 分類退 preset。
- `app/frontend/admin/editor/SettingControls.tsx`：`segmentFits`／`labelWidth`／`SEGMENT_COLUMN_WIDTH`、select 分段分支、`INLINE_TYPES` 單列形。
- `app/assets/stylesheets/admin.css`：`.cl-panel__row--inline`／`.cl-panel__inline`；`.cl-tree__name`／`.cl-tree__summary` 縮放規則。
- `app/assets/javascripts/editor-bridge.js`：圖示工具列（aria-label／title 跟語系）、`closest("[data-cl-op]")`、選中 chip、chip 位置。
- `app/frontend/admin/pages/ThemeEditorPage.tsx`＋五語系 `editor.blockRemove`：去 id（首輪漏 zh-Hant，`messages.test.ts` 占位符集合檢查轉紅後補；閘門重跑）。
- 規格：`spec/requests/theme_editor_bootstrap_spec.rb` E13b（fixture `blocks-local` 加引用、`_parent` 加 preset 分類）；
  `SettingControls.test.ts` S4–S6；`ThemeEditorPage.test.tsx` ED8（改點分段）、ED44b；`editorBridge.test.ts` B1（aria-label＋svg）、B1b。
- 文檔：dev doc（新）、external-facts §G16、91 §3.78、e4 doc §E10、本 worklog／handoff。

## 尚未完成或需注意的風險 (Pending / TODO)

- **未取得（91 §3.78）**：Theme Settings 收合區判定規則（本尊列 Facebook＋Reveal sections on scroll；疑執行期讀取追蹤）；
  section 級 Duplicate 灰化規則；URL `section=` 的 group 前綴；面板字型／字級；Text 標籤旁小圖示；「…」選單 section 級項目。
- **下一輪待驗**：隱藏後樹／預覽形態、拖曳排序、Undo／Redo、Save 啟用時機、改值時預覽更新方式、Header section 逐控件。
- **行為面**：分段規則套用全編輯器所有 select——短選項 select 一律分段（本尊同）；估寬非本尊實際量法（V）。
- **部署複驗**：本機無法登入 demo admin（憑證紅線）⇒ 合併部署後用使用者 Chrome 登入態在 demo 店並排複驗；不符再修。

## 閘門（凍結 tree 後全跑兩輪，2026-09-04 凌晨本機；第二輪＝zh-Hant 修正後重跑）

| 閘門 | 結果 |
|---|---|
| `bin/rubocop` | 979 files inspected, no offenses detected |
| `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | exit 0 |
| doc-claims／doc-claims-rules／tenant-isolation／tokens-sync／baseline-raise／lint-prototype／lint-rules／exec-bits／exec-bits-rules | 全部 exit 0（worklog／handoff commit 後再跑 doc-claims，見 PR body） |
| `pnpm typecheck` | exit 0 |
| `pnpm test` | 412 passed（第一輪 411/412：`messages.test.ts` 抓到 zh-Hant `{id}` 占位符 ⇒ 修後第二輪全綠） |
| `bundle exec rspec` | 2103 examples, 0 failures |
| 突變 M104–M111（scratchpad `mutate_e10.py`，commit 後跑） | 輸出貼於 PR body |
