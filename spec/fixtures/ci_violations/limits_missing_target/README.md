# fixture：`limits_missing_target`

🔴 **這個 fixture 的內容就是「它沒有 `config/limits.yml`」。**
不要在這個目錄下建 `config/limits.yml`——建了就等於刪掉這條測試。
本檔存在的唯一理由是 git 不追蹤空目錄，需要一個佔位檔把目錄帶進版本庫。

## 它守的是哪一條

`scripts/check-limits-keys.rb` 的 fail-closed 分支：

```ruby
unless File.exist?(path)
  warn "::error::#{rel} 不存在——TARGETS 列了一個不在倉庫裡的檔案，請修正 scripts/check-limits-keys.rb。"
  exit 1
end
```

期望：`ruby scripts/check-limits-keys.rb <本目錄>` → **exit 1**，訊息含 `TARGETS`。

## 🔴 為什麼非有不可

`TARGETS` 目前只有一個項目。**把 `unless File.exist?` 整段刪掉**、
或把 `exit 1` 改成 `next`（＝「檔案不在就跳過」），在本倉庫上**完全看不出差別**——
`config/limits.yml` 一直都在，那個分支在 CI 上永遠不會被走到。
於是 checker 會靜默退化成：**檔案被改名／搬走／誤刪時，它照樣 exit 0 報「通過」**，
而鐵律 6 的唯一上限值來源已經不見了。

這是本專案反覆出現的同一種形態：**沒有 fixture 的 fail-closed 分支等於沒有 fail-closed**
（比照 `spec/fixtures/ci_violations/limits_erb*` 的 ERB 閘門）。

註冊處：`scripts/test-limits-key-rules.rb` 的 `CASES`。
