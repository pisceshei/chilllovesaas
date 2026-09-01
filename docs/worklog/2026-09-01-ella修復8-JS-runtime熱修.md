# 2026-09-01 Ella 修復 PR-8：JS runtime 熱修批（no-js 殺手根治）

## 已完成的工作 (Done)

- chill.deals 對表艦隊（wf_4fdcbcc5-7ba）js-runtime 軸實錘五格全修：
- 🔴 **全域 settings 三層解析**（schema defaults ← 檔案 current ← DB）——
  先前缺 defaults ⇒ Ella inline theme.config 塊產出 `show: ,`（值缺失）⇒
  SyntaxError ⇒ **整站 JS 停 no-js**（header 高 0、互動全滅的真兇）。
  修後本地 Chrome 實錘：`html.js`、theme.utils=object。JS1/M8-1 紅證
  （schema-default-only 鍵 show_probe 吐空即紅）。
- 🔴 formatMoney 正則反斜線（heredoc 插值吃一層 ⇒ 金額永不替換輸出字面
  "${{amount}}"）——四反斜線落地；實錘 `Shopify.formatMoney(148000)` →
  "HK$1,480.00"。JS2/M8-2 紅證（⚠ M8-2 首次錨反斜線層數沒對上＝未施加
  假綠——改程式化構造 needle 重做真紅；反斜線類突變一律程式化構造）。
- ShopDrop#money_format 真值（"HK${{amount}}"——Ella JS 動態價格 pattern；
  與 money filter 同符號源）；實錘 window.money_format 落頁。
- request.locale 物件化（iso_code——`<html lang>` 不再吐空）。
- t filter 佔位空白寬容（Ella `{{ inventory}}` 無尾空格形；JS5/M8-3 以
  **真渲染路徑**紅證——locale fixture 加 probe.tight）。
- 突變 3/3 真紅；本地 Chrome 六指標覆核（js class/theme.utils/formatMoney/
  money_format/readyState/header-component 45px absolute＝Ella 透明頁首
  設計非 bug）。

## 修改的檔案與核心邏輯 (Changes)

- 改：runtime.rb（全域 settings 三層）、shopify_global.rb（regex 四反斜線）、
  drops.rb（money_format／RequestDrop locale 物件）、filters.rb（t 佔位）、
  minimal fixture（settings_schema show_probe＋locales probe.tight）。
- 新：theme_js_runtime_spec.rb（JS1-5，3 例）。

## 尚未完成或需注意的風險 (Pending / TODO)

- money_format 符號表 v1＝HKD 硬表（與 runtime money_symbol 同型）——多幣別
  時兩處同步抽公用。
- 對表艦隊剩餘軸待修：srcset/變體（PR-9）、/password＋layout 鍵＋
  current_page（PR-10）、編輯器 live 五格（PR-11）。
