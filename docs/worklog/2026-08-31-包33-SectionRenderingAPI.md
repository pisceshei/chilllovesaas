# 2026-08-31 — 包 33 前半：Section Rendering API 端點面

## 已完成的工作 (Done)
- 實測補完（83 §12.3）：乾淨態七格（Content-Type、空 body、群組實例可定址、
  🔴 兩參數並存＝sections 壓過 section_id、Ella 自用形複驗）。
- 🔴 新量測坑入冊：`preview_theme_id` 是 sticky cookie，帶過一次後不帶參數的
  請求繼續渲染預覽主題——上午一輪全表 404/null 假象即此坑；復位＝帶一次
  正式主題 id。
- 實作：`PageRenderer#render` 分流 `?sections=`（JSON map、未知鍵 null、
  超限 400 空 body、上限 `limits theme_engine.section_rendering_max_ids: 5`）
  與 `?section_id=`（裸 wrapper 片段、未知 404 空 body）；id 解析＝template
  sections ＋ layout `{% sections %}` 群組 JSON；context 繼承含 ?variant=
  選中態；controller 分流 JSON 回應。
- spec E11–E17 七格（假綠殺手註記格：E12 不退主題 404 頁、E14 上限、
  E15 衝突向、E17 群組定址、E16 變體疊加）；突變 N1–N5 實跑全轉紅。

## 修改的檔案與核心邏輯 (Changes)
- `app/liquid/theme_engine/page_renderer.rb`：兩 fragment 端點＋Result 加
  content_type＋群組名單解析。
- `app/liquid/theme_engine/runtime.rb`：`raw_layout_source` 曝露。
- `app/controllers/admin/storefront_preview_controller.rb`：JSON 分流。
- `config/limits.yml`：`section_rendering_max_ids: 5`（官方句＋超限實測出處）。
- `spec/liquid/page_renderer_spec.rb`（E11–E17）＋minimal fixture 掛
  `test-group.json` 群組。
- `docs/research/83` §12.3。

## 尚未完成或需注意的風險 (Pending / TODO)
- Bundled section rendering（cart POST 的 sections 參數）歸購物車端點包
  （W6 後續）；本包只做 GET 面。
- 未知路徑＋sections 的本尊行為未取證（我方＝以 404 模板 context 渲染、
  200 回 map——與「any page」官方句相容，登記待對表）。
- 本尊動態實例 id 格式（template--N__）待 DB 實例化包對齊。
