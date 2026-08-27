# frozen_string_literal: true

module Types
  # 本店本身（本尊 `Shop`）。
  #
  # ## 🔴 我方只出**當前有消費端**的欄位
  #
  # 本尊 `Shop` 有數十個欄位；本 type 建立於 S6b-2，當時唯一的消費端是排程發布彈層
  # 需要的店鋪時區。沿用 `Types::Interfaces::Publishable` 檔頭立下的規矩——
  # **沒有呼叫端之前不開欄位**（零消費者欄位的代價見 `publications.catalog_id`
  # 空轉兩週那個坑）。
  #
  # ## 時區：本尊有四個欄位，我方只出第一個
  #
  # 官方 `Shop` 的時區欄位共四個（取證 2026-08-27，
  # <https://shopify.dev/docs/api/admin-graphql/latest/objects/Shop>）：
  #
  # | 本尊欄位 | 型別 | 官方描述逐字 | 我方 |
  # |---|---|---|---|
  # | `ianaTimezone` | `String!` | `The shop's time zone as defined by the IANA.` | ✅ |
  # | `timezoneAbbreviation` | `String!` | `The shop's time zone abbreviation.` | ❌ 前端可導出 |
  # | `timezoneOffset` | `String!` | `The shop's time zone offset.` | ❌ 同上 |
  # | `timezoneOffsetMinutes` | `Int!` | `The shop's time zone offset expressed as a number of minutes.` | ❌ 同上 |
  #
  # 🔴 **官方沒有一個叫 `timezone` 的欄位**——我方 DB 欄名是 `shops.timezone`，
  # 但對外一律用本尊的 `ianaTimezone`（鐵律 12 的命名對齊優先於內部欄名）。
  #
  # 🔴 **後三個刻意不出**：它們都是 `ianaTimezone` 加上「某個時刻」導出的值，而
  # **偏移不是常數**——同一個 IANA 時區的偏移隨日期變（DST 與政治性變更）。
  # MDN 逐字 `To know the offset, we need two pieces of information, the time zone,
  # and the instant.`（<https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Temporal/ZonedDateTime>，
  # 取證 2026-08-27）。出一個「現在的偏移」給前端，前端拿去標一個**未來**時刻，
  # 在跨 DST 的日期上就是錯的。⇒ 只出時區名，偏移由前端**以目標時刻為基準**現算
  # （`Intl.DateTimeFormat` 的 `timeZoneName: "shortOffset"`）。
  #
  # ## 🔴 為什麼是店鋪級而不是使用者級
  #
  # 我方 schema 有**兩張表都有 `timezone`**：`shops.timezone` 與
  # `staff_members.timezone`，兩者 default 都是 `Asia/Hong_Kong`。
  # 排程發布必須用**店鋪級**——help 逐字
  # `Verify that the date and time in the Store defaults section of your General settings
  # page is set to your time zone so that your products publish at the correct time.`
  # （<https://help.shopify.com/en/manual/shopify-admin/productivity-tools/future-publishing>，
  # 取證 2026-08-26）。本尊設定頁也逐字證實兩級並存
  # （`To change your user level time zone and language visit your account settings`，
  # `docs/research/82` §15.6）。
  # ⚠️ **兩者現在 default 相同 ⇒ 選錯在現況下 100% 測綠**，spec 必須讓兩者不同值。
  class ShopType < BaseObject
    graphql_name "Shop"
    description "本店。"

    field :iana_timezone, String, null: false,
      description: "本店的 IANA 時區（例 Asia/Hong_Kong）。🔴 排程發布的時刻以此為準，不是瀏覽器時區。"

    # @return [String] IANA 時區名
    def iana_timezone = object.timezone
  end
end
