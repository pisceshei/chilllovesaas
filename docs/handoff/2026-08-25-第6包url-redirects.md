# 交接：第 6 包 url_redirects＋handle 變更解鎖

分支 `m1/p6-url-redirects`，base＝`main`（第 3 包之後）。

## ① 我改了什麼

**目標**：商家終於能改商品／系列 handle（先前商品硬拒、系列靜默忽略），
改名同 transaction 落 301。詳細見配對 worklog
`docs/worklog/2026-08-25-第6包url-redirects.md`。

**驗證輸出**（快照 2026-08-25，複驗＝重跑）：rspec 674、rubocop 0、vitest 全綠、
tsc 乾淨。守衛突變驗證五紅一冗餘（冗餘者已移除）。

## ② 為什麼這樣改

- **鏈坍縮在寫入時做**＋**舊 handle 永不回收**＝「表裡永遠無鏈無迴圈」不變量
  ——第 36 包的 301 引擎因此**不需要**迴圈偵測與 hop 追蹤，查一次表就回。
- **同 txn**：redirect 沒寫成＝舊網址 404；寫了、改名回滾＝好網址被轉走。
- **系列的靜默忽略比硬拒更糟**：商家以為改了、其實沒改——所以本包一併解鎖。
- **被推翻的假設**：「更新態要自寫佔用檢查」——model uniqueness → HANDLE_TAKEN
  已承接（突變證實寫了也測不出差異 ⇒ 刪）。

## ③ 還有什麼沒解決

見 worklog Pending（301 引擎＝36 包／manual 等 source 無寫入者／410 隨下架流程／
系列頁前端解鎖待辦／spec 常數撞名的全倉同型風險只登記）。
**線上驗收未做**（合併部署後）：改名 → 查 url_redirects 列、連續改名 → 無鏈。

## ④ 下一個人要注意什麼

- **入口**：`app/services/catalog/handle_change.rb` 檔頭四條。
  凡新增「handle 指派」的路徑（匯入、API、新資源類型）都必須經
  `path_reserved?`——漏了＝新資源佔走舊網址、被既有 301 轉走。
- 🔴 **第 36 包讀表時不用做迴圈偵測**（不變量保證），但**必須**剝 locale 前綴
  再查、命中後加回前綴（62 §F.3；表存正規路徑）。
- 🔴 **spec 常數要唯一名**：describe 裡的常數在 Object 上，後載覆蓋先載，
  症狀是「單跑全綠、整套才炸」且炸的是**別人的檔**。
- **重跑**：`bundle exec rspec spec/requests/url_redirects_spec.rb`。
- **停止條件**：審查零未清 ∧ 閘門綠 ∧ CI 綠 ⇒ 合併 ⇒ 部署 ⇒ 線上驗收。
