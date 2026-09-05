# frozen_string_literal: true

module Storefront
  # 店面 Ajax／JSON 端點的序列化形（E17）。本尊逐字（hoko.vip 2026-09-05）：`/products/acme-tee.js` `"url":"\/products\/acme-tee"`、
  # `/en/search/suggest.json` `"url":"\/en\/products\/acme-tee?_pos=1\u0026_psq=tee…"` ⇒ 斜線跳脫成 `\/`、`&` 成 `\u0026`
  # （後者＝Rails `escape_html_entities_in_json` 既有行為；`<`／`>` 同樣 `\u003c`／`\u003e`）。斜線只出現在字串內 ⇒ 對整段
  # 編碼結果替換是安全的。適用：products .js／.json、predictive search JSON、recommendations JSON；cart JSON 的本尊形＝V（91 §3.86）。
  module AjaxJson
    module_function

    def dump(obj)
      ActiveSupport::JSON.encode(obj).gsub("/", "\\/")
    end
  end
end
