# handoff — 包 33 前半：Section Rendering API（2026-08-31）

## ① 我改了什麼
GET 面兩端點（?section_id=／?sections=）進 PageRenderer＋controller JSON 分流；
契約全部帶 83 §12.3 真店錨。輸入 ref：main=f150fb5（疊 #202 探針收口分支後）。

## ② 為什麼這樣改
缺口分析切分 2 剩餘＝本端點面；Ella 變體切換的伺服端半邊（?variant=&section_id=
疊加）在 E16 落地成閘。衝突格、空 body、群組可定址全來自今晨乾淨態重測——
上午第一輪量測被 sticky preview 污染整批作廢（教訓入 83 §12.3）。

## ③ 還有什麼沒解決
worklog Pending 三項（bundled POST 面、未知路徑格、動態實例 id）。

## ④ 下一個人要注意什麼
- 🔴 量前台任何東西前先確認當前渲染主題（sticky preview 坑）。
- fragment 的 id 是 section 鍵不是檔名；靜態 {% section %} 檔名定址未做
  （我方 layout 尚無該用法）。
