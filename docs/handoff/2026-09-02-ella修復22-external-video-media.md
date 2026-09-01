# Handoff：Ella 修復 PR-22（2026-09-02）

## ①我改了什麼

external_video media 的 Liquid 面：ExternalVideoMediaDrop＋product.media
依 position 合流；PR-16 filter 鏈直通 iframe。逐檔＝worklog。

## ②為什麼這樣改

- 資料面早就在（D48）——先 grep 再造輪（91 §3.50 的老教訓）：本包零
  schema、零 mutation，只補 drop。
- images/featured_image 不動：官方 images＝圖片子集、featured_image 走
  圖片面；把影片混進去會炸 image_url 管線。

## ③還有什麼沒解決

- 上傳影片型（管線轉碼大包）；external video 封面縮圖（oEmbed）；
  demo 生產覆檢。見 worklog Pending。

## ④下一個人要注意什麼

- media 合流排序鍵＝[position, id]——新媒體型加入時進同一 sort，別另開
  第二條 media 出口。
- ExternalVideoMediaDrop.preview_image=nil 是資料面誠實值；接 oEmbed 縮圖
  時回 ImageDrop 相容形（aspect_ratio/url），Ella 直接吃。
