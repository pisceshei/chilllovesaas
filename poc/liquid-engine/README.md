# PoC — CHILL LOVE Liquid 相容引擎（渲染 Ella 7.2.0 實證）

> 目的：用最小可行代碼證明 25 號規格的核心主張——**MIT 的 Shopify/liquid gem ＋ 自實作平台層，能渲染未經修改的第三方主題（Ella 7.2.0）真實檔案與真實模板實例資料**。這是 M2 的起點代碼，不是生產代碼。

## 跑法

```bash
git clone --depth 1 --branch v5.5.0 https://github.com/Shopify/liquid.git /tmp/liquid
ELLA_DIR=/path/to/ella ruby render_ella.rb   # 需 Ruby 3.2+；輸出 out/index.html + compat-report.json
# 註：生產用 5.13.x（需 strscan ≥3.1.1）；沙箱 Ruby 3.3.6 內建 strscan 較舊故用 5.5.0，語言面一致
```

Ella 原始碼因授權不入 repo（見 25 §8）——本 PoC 讀外部路徑，`out/` 已 gitignore。

## 檔案

| 檔 | 內容 |
|---|---|
| `engine.rb` | ThemeRuntime：寬容 JSON、schema 剝離、AST cache、section/group/block 渲染、動態來源 resolver、blank? core_ext |
| `drops.rb` | 平台 drops：Product/Variant/Image/Color/Font/Settings(schema 型別強轉)/Section/Block/Closest/Routes/Shop/Cart/Request/Localization…＋ miss 遙測 |
| `tags.rb` | 9 個平台 tags：**content_for（blocks 機制核心）**、style、stylesheet/javascript、doc、form、paginate、section、sections、layout |
| `filters.rb` | ~70 個 T0 filters：t/asset_url/inline_asset_content/image_url/image_tag/money 族/handleize/font 族/color 族/stub 族 |
| `render_ella.rb` | Harness：三個渲染目標＋真實 head 管線（global-style/global-css）＋輸出組頁 |

## 三個渲染目標（全部 0 Liquid errors）

1. **announcement-bar**——header-group.json 真實實例；`_group-announcement-bar → _group-announcement → 子卡片` 樹＋color scheme。
2. **商品卡 card-product-flex ×4**——product.json recommendations 實例的 `product-slide-item` 靜態卡片子樹：media/information(title/price)/button 巢狀卡片、`closest.product` 動態來源逐商品切換、變體感知按鈕（CHOOSE OPTIONS）、cents→money 劃線價。
3. **main-product 商品詳情頁**——product.json main 真實實例：⚓media-gallery（主圖＋縮圖）＋⚓product-details 巢狀 9 卡片（title 動態來源 H1、product-info、price、hot-stock 庫存條讀 variant 數、customization text/file 欄位、quantity、buy-buttons、subtotal）＋⚓sticky-atc。

## 實測抓到的一級相容坑（已回寫 25 號）

1. **`blank` 語義依賴 ActiveSupport**：gem 的 `x == blank` 走 `MethodLiteral(:blank?)`——裸 Ruby 沒有 `Object#blank?` → `undefined == blank` 恆 false，Ella 的 `if text == blank / assign` 慣用法全滅（實測：全部標題消失）。Rails 環境免費修復；引擎必須保證 ActiveSupport core_ext 已載。
2. **color 設定必須是 color 物件**：主題訪問 `.rgb/.rgba/.red`（color-scheme-style snippet）——回 hex 字串會輸出 `rgb()` 空值。→ SettingsDrop 依 schema 型別強轉 ColorDrop。
3. **動態來源兩形態**：純單一引用（`"{{ closest.product }}"` → 回物件）與混合內容（`"<h1>{{ closest.product.title }}</h1>"` → 迷你渲染成字串）都真實存在於 Ella 實例資料。
4. **strscan 版本鏈**：liquid 5.6+ 需 strscan ≥3.1.1（`peek_byte`）——Ruby 3.3 內建 3.0.x 會炸，Gemfile 要鎖。
5. 寬容 JSON（註解/尾逗號）、schema `t:` 翻譯鍵、`visible_if` 條件設定、`{% doc %}`——全在真實檔案遇到（詳 27 號 §7）。

## 與規格的對應

- 25 §2（gem 能力）→ `engine.rb` 實證；25 §6（渲染服務）→ ThemeRuntime 雛形；27 §2（卡片樹）→ 目標 B/C 復現。
- compat-report.json = 25 §7「liquid_method_missing 命中遙測」的最小實作。
