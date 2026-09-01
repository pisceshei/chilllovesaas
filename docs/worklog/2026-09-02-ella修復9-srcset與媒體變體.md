# 2026-09-02 Ella 修復 PR-9：image_url 尺寸參數＋媒體變體＋image_tag srcset

## 已完成的工作 (Done)

- chill.deals 對表艦隊 srcset 軸收口（官方 image_url/image_tag 文檔逐字取證
  2026-09-01）：
- **image_url**：width/height 以 query 參數編進 URL（官方形 `…?width=450`）；
  '800x' 類字串 to_i 係數化；format 吞掉不編出（我方衍生恆 webp＝ours）；
  回傳 `ImageUrlResult`（String 子類攜 source drop＋請求尺寸）。
- **媒體端點變體**：?width=/?height= 從 derivatives 選「最小 ≥ 請求」的
  fit 變體（thumb/card/detail；🔴 排除 og——cover 裁切改比例）；以 entry
  實際尺寸比對（勿用名目值）；全部不足或無 derivatives ⇒ 原圖（官方
  「永不放大」語義天然滿足）；衍生 blob 缺檔回落原圖（SR1/M9-1 紅證——
  「最小 ≥」退化成「最大」被殺）。
- **image_tag 重寫**：widths CSV → 逐寬換 src 的 width 參數組 srcset＋
  " Nw"（🔴 只取 ≤ src width——官方 "up to the maximum defined in the
  image URL"；SR2/M9-2 紅證）；明示 srcset ＞ widths ＞ 預設單條；width
  屬性推導自 src width、height＝width÷aspect_ratio（官方例證 200→133）、
  alt＝drop alt；🔴 widths/preload 不再誤落 HTML 屬性（對表軸實錘）。
- M5 升級斷言：渲染級 `<img src="…?width=800" width="800" height="533"
  srcset="… 800w">` 官方全形。
- 突變 2/2 殺。

## 修改的檔案與核心邏輯 (Changes)

- 新：image_url_result.rb。
- 改：filters.rb（image_url/image_tag/srcset 組裝三函式）、
  media_controller.rb（pick_variant）、storefront_media_chain_spec
  （SR1/SR2 新增＋M5 升級）。

## 尚未完成或需注意的風險 (Pending / TODO)

- 官方 smart set 預設 srcset（無 widths 時多條）＝未取得（V）——現出單條。
- 衍生尺寸集只有 thumb/card/detail 三檔——大圖中間檔位缺（需擴
  Derivatives::SPECS 另輪）。
- 🔴 本包沿革：首推遇背景/前台 git 競態（commit 落錯分支）——已 cherry-pick
  重建；新紀律＝git 變更前台序列化、背景僅純輪詢（記憶已固化）。
