# Handoff：Ella 修復 PR-9（2026-09-02）

## ①我改了什麼

srcset 軸三件（image_url 參數化／端點變體／image_tag srcset）。分支
`ella/srcset-variants`（cherry-pick 重建於 #271 base）。逐檔＝worklog。

## ②為什麼這樣改

- 變體選擇用 entry 實際尺寸不用名目：小圖不放大時實寬 < 名目寬（管線
  已存實值）。
- ImageUrlResult 走 String 子類：Liquid 管線把它當字串零成本，image_tag
  又能取中繼資料——與本尊「image_url 回傳物帶資料」的行為證據同構。

## ③還有什麼沒解決

- smart set 預設多條 srcset（V）；衍生檔位擴充；PR-11 編輯器 live 五格。

## ④下一個人要注意什麼

- swap_width 只動 query 的 width 鍵、保序——日後補 v= 參數零改動。
- image_tag 的屬性 dump 過濾 nil；新保留參數記得從 dump 摘出（widths
  誤落屬性的前科）。
