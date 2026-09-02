# tools/theme-conformance — 主題 conformance 工具（D78）

任何買斷主題進倉後的第一步：渲染全模板、收集 count_miss、對 schema 與官方契約分類。
所有腳本從倉庫根目錄執行；Rails 類走 `RAILS_ENV=test bundle exec rails runner`。

| 檔案 | 用途 | 用法 |
| --- | --- | --- |
| `run.rb` | 渲染主題全模板（含 `?view=` 替代模板），可疊 preset 覆蓋層；輸出逐頁 status／Liquid error／例外／count_miss delta | `RAILS_ENV=test bundle exec rails runner tools/theme-conformance/run.rb test/fixtures/themes/kalles-5.4.2 Kalles 5.4.2 [preset_dir\|-] [out.json]` |
| `engine_surface.rb` | 導出引擎已註冊 tags／filters／globals／Drop 方法 | `RAILS_ENV=test bundle exec rails runner tools/theme-conformance/engine_surface.rb evidence/engine_surface.json` |
| `static_scan.py` | 靜態掃描主題用到的 tag／filter／`root.prop`，對 engine_surface 找候選缺口 | `PYTHONIOENCODING=utf-8 python tools/theme-conformance/static_scan.py tools/theme-conformance/evidence/engine_surface.json test/fixtures/themes ella-7.2.0 minimog-6.0.0 kalles-5.4.2` |
| `settings_preclassify.py` | 把 `settings.*`／`section(x).*`／`block(t).*`／`color_scheme(s).*` miss 鍵對 schema 機械分類 | `PYTHONIOENCODING=utf-8 python tools/theme-conformance/settings_preclassify.py test/fixtures/themes`（讀 `tmp/conformance-*.json`） |
| `schema_parse_probe.rb` | 三套主題全部 schema 用引擎 `tolerant_json` 解析，統計失敗 | `RAILS_ENV=test bundle exec rails runner tools/theme-conformance/schema_parse_probe.rb` |
| `golden_capture.sh` | curl 真店（預設 hoko.vip）全頁 HTML 當金標本 | `bash tools/theme-conformance/golden_capture.sh <label> [base_url]` |

- `evidence/`：2026-09-02 首跑的 conformance／preclassify／engine_surface／static_scan JSON。
- `research/`：三個研究 Workflow 的原始輸出複本（契約矩陣、hoko 對位稽核、缺口 triage）
  與前一輪 Minimog 5.9.0 triage。都是未經人工整理的機器輸出；分類結論見
  `docs/handoff/2026-09-02-主題無關conformance與真店切換.md` §①4。
- `golden/`：真店抓取結果（目前只有 Ella 基線）。

坑：主題 schema 常帶尾逗號（Kalles 194 檔），Python 嚴格 `json.loads` 會炸——
`settings_preclassify.py` 已內建與引擎同款的寬容規則；miss 鍵 ≠ 引擎缺口，先分類再比官方。
