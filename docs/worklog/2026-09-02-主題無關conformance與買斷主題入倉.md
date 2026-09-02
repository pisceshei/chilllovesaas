# 2026-09-02 主題無關 conformance：Minimog 6.0.0／Kalles 5.4.2 入倉＋harness＋研究

分支 `theme/minimog-fixture`（base main `3bfaeaf2`）。配對 handoff：
`docs/handoff/2026-09-02-主題無關conformance與真店切換.md`（斷點與續做入口在那裡）。

## 已完成的工作 (Done)
- 依使用者裁定刪除 Minimog 5.9.0 fixture，改入 **Minimog 6.0.0**（468 檔）＋同包 sample data
  （681 檔，與舊 zip md5 相同），新增 **Kalles 5.4.2**（642 檔，theme-blocks 架構）＋
  Template Demo v5（136 檔）＋ Demo Data v5（323 檔，圖片排除）。
- `docs/DECISIONS.md` D78 改寫：主題無關目標、三套買斷主題入倉授權、真店 Publish 授權、首跑數字。
- conformance harness 補 article／blog／search 視圖對映；新 spec `theme_conformance_spec.rb`
  TC-M1（Minimog 41 頁）＋TC-K1（Kalles 60 頁）——2 examples, 0 failures。
- 通用工具落 `tools/theme-conformance/`：run.rb（任意主題＋preset）、engine_surface.rb、
  static_scan.py、settings_preclassify.py、schema_parse_probe.rb、golden_capture.sh；
  evidence／research 子目錄放本輪 JSON 與三個 Workflow 的輸出複本。
- 首跑：Minimog 6.0.0 41 頁／77 miss、Kalles 60 頁／215 miss，8 個 preset 合計 0 Liquid error／0 例外；
  三套主題 711 個 schema 引擎 tolerant_json 0 失敗。
- 研究：契約矩陣 466 列（implemented 141／partial 161／missing 119／stub 34／n-a 11）、
  缺口 triage 70 鍵（engine-gap 31，18 條經對抗驗證）、hoko 稽核 72 條候選（未驗證）。
- 真店：主題庫確認 `minimog-6-0-0`／`kalles-v5-4-2-official` 已裝未發布；抓到 Ella 基線全頁。

## 修改的檔案與核心邏輯 (Changes)
- `test/fixtures/themes/{minimog-6.0.0,minimog-6.0.0-sample-data,kalles-5.4.2,kalles-5.4.2-template-demo,kalles-5.4.2-demo-data}/`：新 fixture（只供測試）。
- `spec/support/theme_conformance.rb`：`views.each` 的 `case base` 新增 article／blog／search 三個 `when`。
- `spec/liquid/theme_conformance_spec.rb`：共用 `expect_all_templates_render`，兩格 TC-M1／TC-K1。
- `docs/DECISIONS.md`：D78 全文改寫（標題改為「買斷主題入倉授權（Minimog 6.0.0／Kalles 5.4.2）」）。
- `tools/theme-conformance/`：新目錄（README 有用法）。
- `test/fixtures/themes/kalles-5.4.2/templates/page.store-locator.json`＋
  `kalles-5.4.2-template-demo/page.store-locator.json`：廠商夾帶的 Mapbox `access_token`
  （`pk.eyJ…`）改為 `REDACTED-MAPBOX-TOKEN`（GitHub push protection GH013 拒收原值）。
- 刪除：`spec/liquid/theme_conformance_minimog_spec.rb`（未入庫）、`test/fixtures/themes/minimog-5.9.0*`（未入庫）。

## 尚未完成或需注意的風險 (Pending / TODO)
- 🔴 真店 Publish 未完成（Chrome 跨域 iframe 操作失敗、renderer 卡死），Minimog／Kalles 金標本 0 頁；
  hoko.vip 零商品，商品頁在真店不可比——需使用者裁定資料來源。
- 三個 Workflow 皆因額度中斷（verify＋synthesis 缺），resume 指令在 handoff §④D。
- 引擎缺口一條未修；建議 PR 包順序在 handoff §④E（FormDrop 型別化最先——登入表單現在不出密碼欄）。
- `settings_preclassify.py` 對 `kalles-5.4.2/sections/header-inline-blocks.liquid` 仍解析失敗。
- `select`／`radio` 無 default 的官方語義未取得。
- CI 未跑（本輪只跑目標 spec 與 rubocop）：`quality`／`test` 綠之後才可合併。
