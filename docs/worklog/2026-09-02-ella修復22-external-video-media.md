# 2026-09-02 Ella 修復 PR-22：external_video media 進 Liquid（影片鏈第②步a）

## 已完成的工作 (Done)

- 影片鏈第②步的 external_video 面：資料層 D48 既有（media_type=
  external_video＋external_host/external_id 驗證），缺口只在 drop 面
  ——`ProductDrop#media` 原本 `= images`（外部影片在商品 gallery 靜默
  消失）。本包：
  - **ExternalVideoMediaDrop**：media_type/host/external_id/alt/position；
    preview_image=nil（無縮圖資料面——Ella `media.preview_image.aspect_ratio
    | default: 1.0` 形對 nil 寬容）。
  - **product.media 合流**：image＋external_video 依 position 排序（官方
    media＝全媒體序列）；`images`／`featured_image` 照舊只走圖片子集
    （官方 images 本就是圖片子集）。
  - **全鏈接通**：PR-16 的 external_video_url/tag 收 host/external_id
    duck-type ⇒ media drop 直入 → 官方 embed URL → iframe（EV2 全鏈格）。
- 測試 EV1/EV2；突變 1/1 殺（合流退回 images ⇒ 兩格全紅）。

## 修改的檔案與核心邏輯 (Changes)

- `app/liquid/theme_engine/drops.rb`：ExternalVideoMediaDrop 新增＋
  ProductDrop#media 合流＋media_count 改 media.size。
- 新 spec `spec/liquid/external_video_media_drop_spec.rb`。

## 尚未完成或需注意的風險 (Pending / TODO)

- 上傳影片（media_type "video"＋sources）＝upload_media_types_enabled
  仍只 [image]——需媒體管線影片處理（轉碼/封面），為獨立大包；
  video_tag 的 sources 分支（PR-16）已備。
- external video 的 preview_image 縮圖（本尊由 oEmbed 取 YouTube/Vimeo
  封面）未做——gallery 卡以 CSS ratio 1.0 兜底。
- Ella product gallery 對 external_video 的實渲染驗證＝需 demo 店掛一筆
  外部影片媒體後生產覆檢（登記，隨下次 demo 資料輪）。
