# frozen_string_literal: true

module Types
  module Inputs
    # 逐資源發布／取消發布的輸入（S5）。
    #
    # 本尊對位＝`PublicationInput`，被 `publishablePublish` 與 `publishableUnpublish`
    # **兩支共用**（input object 自己的描述逐字寫的是 publish：
    # `The input fields required to publish a resource.`）。
    #
    # ## 官方 SDL 逐字（取自
    # <https://shopify.dev/docs/api/admin-graphql/latest/input-objects/PublicationInput>
    # 的 schema payload，取證 2026-08-27）
    #
    #     input PublicationInput { channelId: ID  publicationId: ID  publishDate: DateTime }
    #
    # 🔴 **三欄全部 nullable、且 SDL 層沒有任何 `= value` 預設子句**——
    #   渲染頁與官方 `.md` 也都沒有 `Default:` 標註。⇒ 「省略 `publishDate` 會怎樣」
    #   在 schema 層**沒有**答案，是由 mutation 描述那句
    #   `You can schedule future publication by providing a publish date.` 反推的。
    #
    # ## 🔴 我方兩處刻意偏離
    #
    # 1. **不實作 `channelId`**：官方已 deprecate。⚠️ 渲染頁與 `.md` 只顯示 `Deprecated`
    #    一個字，**描述與 reason 只存在於同一官方 URL 的 schema hydration payload**，
    #    逐字片段 `"channelId","ID of the channel.",[],"Use publicationId instead."`
    #    （渲染層未取得，取證 2026-08-27）。偏離依據＝`28 §0.3.2`「偏離只減不加」
    #    與第 12 包 §2.4「deprecated 的不抄」。
    #    ⇒ 官方那條「同時給 channelId 與 publicationId 時只用後者」的優先序規則
    #    （只出現在 unpublish 頁）在我方**情境不會發生**，不照抄成我方規則。
    # 2. **`publicationId` 我方要求必填**：官方是 nullable，但那個 nullable 是為了
    #    「可以改傳 `channelId`」而存在的——既然我方不收 `channelId`，兩欄都空的請求
    #    沒有任何可指向的目標。⚠️ 這不在 GraphQL 型別層擋（保持與本尊同型 `ID`），
    #    而是在 `Publications::Write` 收集階段回 `INVALID` 的 userError，
    #    理由：鐵律 4 ①要求業務錯誤走 `userErrors`／HTTP 200，型別層 non-null
    #    會讓它變成 top-level `errors`。
    #
    # @see docs/dev/m2-publishable-write.md
    # @see docs/plans/2026-08-27-S5-規格草案.md §1.3
    class PublicationInput < GraphQL::Schema::InputObject
      graphql_name "PublicationInput"
      description "把一個資源發布／取消發布到某個 publication 的目標描述。"

      # 官方逐字：`ID of the publication.`
      argument :publication_id, ID, required: false,
        description: "publication 的 GID。🔴 我方必填（本尊 nullable 是為了相容 deprecated 的 channelId）。"

      # 官方逐字（`PublicationInput.publishDate`，取證 2026-08-27）：
      #   `The date and time that the resource was published. Setting this to a date in
      #    the future will schedule the resource to be published. Only online store
      #    channels support future publishing. This field has no effect if you include
      #    it in the publishableUnpublish mutation.`
      #
      # 🔴 最後一句是**唯一一條**關於本欄在 unpublish 上行為的規範性陳述，
      #   且它說的是「無效果」不是「報錯」⇒ 我方 `publishableUnpublish` 收到本欄
      #   一律**靜默忽略**（不驗證、不生效、不回錯）。有反向 fixture 鎖死。
      #
      # ⚠️ **時區＝ours 裁定**：官方對「不帶 offset 的字串怎麼解讀」無正面陳述
      #   （S2 §4.C 已登記為未取得）。`ISO8601DateTime` 對不帶 offset 的輸入會當 UTC，
      #   我方**接受這個行為並明文登記**，不自行套用店鋪時區——
      #   `shops.timezone` 至今零讀取者，寫成「沿用店鋪時區」會是一句沒有實作的話。
      #   官方唯一的形狀證據是範例 variables 逐字 `"publishDate": "2999-01-01T00:00:00-00:00"`
      #   （帶 offset），與此一致。
      argument :publish_date, GraphQL::Types::ISO8601DateTime, required: false,
        description: "發布時刻。未來時間＝排程發布（僅支援排程的管道）。🔴 在 publishableUnpublish 上無效果。"
    end
  end
end
