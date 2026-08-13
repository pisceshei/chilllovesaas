# 移除 `translations.market_id`（裁定 10 執行；67＋70＋limits.yml＋原型同輪）

> 對應規格：`docs/specs/67` §C.2／§C.4／§E.6／§K、`docs/specs/70` §D.5、裁定 10 ｜ commit：見本檔所在 commit

## 已完成的工作 (Done)

- **67 號本體（12 處）**：§C.2 刪 `market_id` 欄、UNIQUE 由六欄縮五欄（五欄全 NOT NULL——這同時修掉 MySQL nullable-UNIQUE 形同虛設的問題）、原處留完整沿革註釋（原文逐字＋兩條刪欄理由＋防回退＋**復活條件三款**）；§C.4 `resolve()` 去 market 參數、鏈 5 步縮 4 步；§C.1 防線表格改寫；§E.2-1 六元組縮五元組＋「無法承載 market_id」句移除；§I **L15 標「已依裁定 10 取消」**（不靜默刪——29 §8 還列著它，會被人加回來）；§K.0 六欄→五欄；**I18N-3** 去 per-market 分支；**I18N-6 反轉為防回歸斷言**（schema 無此欄、resolve() 不收 market、所有市場輸出逐位元組相同）；§0.4 新增第 7 列（明知偏離登記，形態比照 62 §F.3-1）；§M 新增 **M-5a**（29/28/50 的下游批註待各檔 owner）。
- **V-201 匯入語義翻轉**（唯一會弄壞既定功能的連鎖點）：原「`market_handle` 留空⇒拒絕」在刪欄後會把**每一列**都拒絕（匯出恆空白）⇒ 改為「空白＝唯一合法值；非空白⇒拒絕該列並明示裁定 10」。欄位本身保留（純對齊本尊 8 欄格式）。
- **70 號（5 處）**：檔頭、§D.5(b) 表格與後果 1／後果 3、(c) 假設段、§M M-1b——「欄位仍然存在、本檔不動它」全部改為「已依裁定 10 移除」；並在檔頭沿革註釋補一行後記（歷史引句不改，加括號註記防混淆）。
- **limits.yml（3 處）**：fallback 解析順序註釋去 (locale,market) 層；`market_handle` 欄補格式相容說明；`locale_columns_map_to_market_id: "NULL"` 改為 `market_id_column_removed: "2026-08-13"`（受指涉物消失，鍵語義懸空）；`assumes_no_market_level_override` 與 `market_override_ruling_date` 保留（記錄裁定本身，仍為真）。
- **原型與設計檔（9 處）**：admin-v2 的 fallback JS 註釋（4415）、**mk-catalog「翻譯覆寫」卡整卡改造**（7580：兩列覆寫輸入框→「內容與翻譯」說明卡）、刪除市場確認文案（7596）、設定頁解析順序列（8550）、mk-catalog DOCS 條目（9173）、content-locale DOCS 條目與 `[tbl:]` 六元組（11550-11551）、set-lang-fallback DOCS 鏈（11610）；48-component-contract:5097 從「尚未實作」改「**不做**」；storefront-v2:1457 註釋塊改寫。
- **清單外抓到並修掉一處既有矛盾**：67 §I **L12** 還寫著 68 輪的「空白＝清空」——B-3 二次反轉（69 §V-182）時漏改，與 §E.6(b) 直接矛盾。已對齊現行語義並留雙層追溯。

## 修改的檔案與核心邏輯 (Changes)

- `docs/specs/67-multilingual.md`、`docs/specs/70-product-csv-io.md`、`config/limits.yml`、`docs/design/chilllove-admin-v2.html`、`docs/design/chilllove-storefront-v2.html`、`docs/design/48-component-contract.md`。
- **為什麼同輪 commit**：67 說欄位已刪而 70/limits 說「欄位仍在」＝規格自相矛盾；本專案已有 62/67「同一裁定的兩半分開改必產生半套狀態」的前例。
- **為什麼 UNIQUE 縮欄而非 sentinel**：裁定 10 之後市場維度是「不存在」不是「恆為預設值」；sentinel 0 是**復活時**的形態（已寫進復活條件），現在用它等於假裝維度還在。
- **為什麼 I18N-6 改反向斷言而非刪除**：刪掉驗收條目會讓「不做市場覆寫」變成沒有執法點的口頭約定；反向斷言讓誤加欄位／誤加參數在 CI 就紅。
- **沒動的（同名不同義，六種）**：63 §D.3／67 §G.1 快取鍵的 `market_id`（市場定價維度）、62 `knowledge_entries.market_id`、`market_settings`、`derived_parent_market_id`、`company_locations.market_id`、原型 `market_shipping_options(market_id)`；以及**裁定 11 的語言白名單全線**（`market_web_presence_locales`、67 §A.5/§C.8——白名單管曝光、translations 管內容，兩個機制）。

## 尚未完成或需注意的風險 (Pending / TODO)

- **M-5a 的下游批註未做**（刻意）：29 §2.2/§2.4/§8、28:343 `marketLocalizations*`、50:313 是別的 owner 的檔案，本輪只登記不代改——與 M-8「本輪不得改 63」同一條紀律。下一輪誰動 28/29/50 時要一併帶上。
- **67 §J 宣稱已落鍵的 `i18n.market_locales.*`／`locale_prefix.*` 在 limits.yml 不存在**（分析員發現的既有缺口，與本次刪欄無關）——刻意不順手補，避免改動面失控；**待開任務**。
- 驗證證據：lint ERROR 0／WARN 13（＝基線，零新增）；原型經 localhost 實開——市場詳情頁新卡渲染正確（0 輸入框）、語言設定頁可見鏈為「語言層譯文 → BCP-47 截尾鏈 → base row → 依欄位類別」、console 零錯誤。**殘留字串僅存在於追溯註釋與 DOCS 沿革引句（不可見文字）**，grep 已逐條核對。
- 復活成本已寫死在 67 §C.2 沿革註釋：不是「加回一欄」——NOT NULL sentinel／生成欄位、70 §D.5(b) 三條後果重做、V-201 翻回，三件缺一不可。
