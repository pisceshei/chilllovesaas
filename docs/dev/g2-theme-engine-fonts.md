# G2 步 13a：字型管線真實作（Times New Roman 根因收口）

> 取證正典＝`docs/research/97-theme-engine-fonts-blocks-teardown.md` §1（官方三
> filter＋font object 七屬性逐字；chill.deals live @font-face 形；Ella
> global-style 消費鏈）。13b（render block／block.blocks／色階群組）另包。

## 1. 構件

| 件 | 落點 | 說明 |
| --- | --- | --- |
| 字型庫 registry | `config/storefront_fonts.yml` | 平台字典（隨版本部署、無租戶資料）；Jost/Poppins ×n4-n7＋system 四鍵 |
| 實體字型 | `public/fonts/{family}/{handle}.woff2` | Google Fonts **OFL** latin subset 自 host（靜態層服務，無路由） |
| 解析器 | `ThemeEngine::FontLibrary` | handle→FontDrop 唯一解析點；未知 handle＝system fallback＋miss 遙測 |
| `font` drop | drops.rb FontDrop | 官方七屬性（variants 走庫；baseline_ratio=0.1 常數 ours） |
| 三 filter | filters.rb | font_face（live 對錨形＋font_display 傳了才出）／font_url（恆 woff2）／font_modify（官方值域＋CSS 相對表） |

## 2. 防線（突變紅證 MF1–MF5）

- 🔴 **font_modify 缺變體回 nil**（官方逐字）——回原 font 的退化會讓 Ella 的
  italic 鏈輸出錯 face（MF1）；nil 進 font_face＝空輸出（MF2 反向：無檔 font
  絕不出 src）。
- handle 解析（觀察形 `{family}_{n|i}{weight/100}`，97 §4-2 標 V）退化＝全部
  走 system fallback ⇒ 零 @font-face（MF3——Times New Roman 根因的復發形）。
- lighter/bolder＝CSS font-weight 相對規則表（MF4）；font_url 回自 host 路徑（MF5）。

## 3. v1 邊界（91 §3.62）

單 woff2 src（無 woff 退路）／font_url 'woff' 同回 woff2／latin subset（中文標題
字型不在庫——主題 CJK 面另議）／字型庫只 2 家族 8 變體（新主題引用新家族要擴
registry＋下載檔）。
