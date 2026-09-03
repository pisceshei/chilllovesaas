# E10 主題編輯器逐 section 對照 ①：Announcement bar

> 使用者 2026-09-03 指出「從 Announcement bar 開始你都沒和 shopify 本尊做到一模一樣」，並核准順序 D81 → 本包 → D80。
> 方法：真店 pnrjnw-sy 副本主題（143506604135，Ella 7.2.0）在本尊編輯器逐控件點擊（Chrome **前景**分頁；背景分頁側欄不載入，
> 91 §3.77），同一分頁切到我方 demo 店（Ella 7.2.0）同 section 並排；證據逐字與量測在 `docs/dev/external-facts.md` §G16，
> 範圍外與未取得在 `docs/specs/91-pit-register.md` §3.78。

## §1 本尊形（Announcement bar 全鏈）

| 層 | 本尊 | 控件 |
|---|---|---|
| section `announcement-bar` | 右欄：Color scheme（select＋色票）、Spacing › Spacing bottom（range px）、Section padding › Top／Bottom（range px）、收合區 Theme Settings、Custom CSS、🗑 Remove section | 樹：⊕ Add block → 子 block「Announcement」 |
| block `_group-announcement-bar`（樹列名「Announcement」） | Padding Top／Right／Left／Left（range；Ella 標籤 bug）、Layout：Direction（分段 Vertical｜Horizontal）、Wrap（分段 No｜Yes）、Align items（分段 Top｜Center｜Bottom）、Justify（下拉 6 項）、Column gap／Row gap（range）、Show separator line（toggle）；Colors：Inherit color scheme（toggle）＋ 8 個 color／color_background（visible_if）；Remove block | Add block 清單：Announcement text… |
| block `_group-announcement`（「Announcement」） | Grid width on desktop（range %＋help）、Announcements › Auto-rotate（toggle）、Change every（range s）、Inherit color scheme（toggle）、Remove block | Add block：Announcement text |
| block `_announcement-text`（「Announcement text – End …」） | Text（inline_richtext＋工具列 ✨ B I 🔗）、Font（下拉）、Size（下拉）、Text weight（下拉）、Text alignment on mobile（分段 Left｜Center｜Right）、Remove block | — |

其餘本尊形（樹列、URL、預覽覆疊、Add block 選擇器、「…」選單）逐字在 §G16。

## §2 我方差異與處置（本包）

| # | 我方（2026-09-03 demo 實測） | 根因 | 處置 | 規格／突變 |
|---|---|---|---|---|
| 1 | `_group-announcement-bar` 樹列名＝原始 type、面板＝原始鍵＋純文字框、標題＝原始 type | `Types::ThemeType#block_defs_for` 把 section schema 的 `{type:"_x"}` **引用**當本地定義（無 name／settings） | 引用形解析成 `blocks/_x.liquid` 定義（`limit` 留在引用處） | E13b／M104 |
| 2 | Add block 群名「General」（本尊「Header」） | theme block 的 category 只寫在 `presets[0].category` | `theme_block_defs` 分類退 preset | E13b／M105 |
| 3 | 所有 select 皆下拉（本尊短選項為分段） | 未實作官方三條件 | `segmentFits`（估寬對 158px；真店六例校準） | S4–S6／M106／M107／M111 |
| 4 | 控件上下排（本尊 range／select／toggle／color 與標籤同列） | E4 版面 | `INLINE_TYPES`＋`.cl-panel__row--inline` | ED44b／M108 |
| 5 | 「Remove block <id>」 | i18n 鍵含 `{id}` | 五語系去 id（首輪漏 zh-Hant，i18n bundle 測試抓到）| messages.test |
| 6 | 樹列名被截成「An…」（本尊只截摘要） | name／summary 同比縮 | `.cl-tree__name` 不縮、`.cl-tree__summary` 縮 | CSS |
| 7 | 預覽工具列文字鈕、選中元素無 chip、chip 在框上方 | 橋 | 圖示鈕（Lucide copy／eye-off／trash-2）＋aria-label；選中 chip；chip 貼框內左上 | B1／B1b／M109／M110 |

ED8 的 fixture select（2 個短選項）依官方規則變成分段 ⇒ 測試改點分段鈕（不是弱化：本尊同形）。

## §3 仍有差異（91 §3.78）

Theme Settings 收合區規則（本尊列 Facebook＋Reveal sections on scroll，判定法未取得）、Ask for changes（Sidekick）、section 級 Duplicate 灰化規則、
URL `section=` 的 group 前綴、面板字型／字級量測、Text 標籤旁小圖示、section 級「…」選單、隱藏／拖曳／Undo／Save／預覽更新方式（下一輪）。

## §4 影響面

- 引用形解析：Ella 幾乎所有 header／footer／announcement 類 section 的第一層 block 都是引用形 ⇒ 全部從「原始鍵文字框」變成完整面板；
  `themeBlocks` 全表不變，`sectionSchemas[type].blocks[]` 的引用項現在帶 name／settings／category／blocks。
- 分段規則：整個編輯器所有 `select`（含佈景設定面板）都套用；`radio` 不變（恆分段）。
- 單列形：所有 section／block／佈景設定面板的 range／select／radio／checkbox／color／color_background／color_scheme／text_alignment 列。
- 橋：所有預覽頁（工具列與 chip）；`cl:names.labels` 仍供 aria-label／title。
- 前端 i18n：`editor.blockRemove` 不再收參數。

## §5 驗收清單

- 後端：`spec/requests/theme_editor_bootstrap_spec.rb` E13b（引用解析＋preset 分類＋本地定義不被覆蓋）。
- 前端：`SettingControls.test.ts` S4／S5／S6；`ThemeEditorPage.test.tsx` ED8（改分段）、ED44b；`editorBridge.test.ts` B1（aria-label＋svg）、B1b。
- 突變 M104–M111（scratchpad `mutate_e10.py`，commit 後跑）。
- 部署後在 demo 店同 section 並排複驗（下一輪起點：本包 §3 待驗項）。
