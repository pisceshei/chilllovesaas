# frozen_string_literal: true

module Publications
  # 把 publication GID 解析成本店的記錄（S1）。
  #
  # 🔴 **抽出來的理由是鐵律 7，不是省字**：`publicationUpdate` 與 `publicationDelete`
  #   都要「把 GID 解析成本店的 publication，查不到就回一個形狀一致的錯誤」。
  #   寫兩份的失敗形態是**兩邊的 `field` path 或 `code` 慢慢分岔**，
  #   而前端是照 path 定位欄位的。
  #
  # 🔴 **放在服務層不是 `app/graphql/mutations/` 底下**：那個目錄有一條 CI 斷言
  #   （`spec/graphql/mutation_idempotency_call_spec.rb`）要求非 `base_*` 的檔案
  #   一律是帶 `resolve` 的具體 mutation，且明文「不逐檔白名單」。
  #   ⚠️ 第一版放錯地方，被該斷言當場擋下——**那個判準是對的**，
  #   錯的是「一個 lookup 不是 mutation」。不得為了遷就放錯的檔案去放寬判準。
  #
  # ⚠️ 本倉庫**沒有共用的 GID parser**（`Storage::FileWrite`、`BaseMediaMutation`、
  #   `Catalog::SaveProduct` 各自寫一份 regex）。本檔刻意**只服務 publication 線**，
  #   不順手做全域重構——那是跨元件的事（鐵律 20.5），登記於 `docs/specs/91-pit-register.md` §3。
  module Lookup
    module_function

    # @param shop [Shop]
    # @param gid [String]
    # @return [Publication, nil] 格式不符或不屬於本店時為 nil
    # @note 副作用：一次 tenant-scoped SELECT。
    def call(shop:, gid:)
      legacy_id = gid.to_s[%r{\Agid://chilllove/Publication/(\d+)\z}, 1]
      return nil unless legacy_id

      ActsAsTenant.with_tenant(shop) { Publication.find_by(id: legacy_id.to_i) }
    end

    # 查無 publication 時的 `userErrors`（鐵律 4 ①：HTTP 200 走 userErrors，不是 404）。
    #
    # 🔴 `field` 是 `["id"]` 而不是 `["input","id"]`——本尊的 `publicationUpdate`
    #   與 `publicationDelete` 都把目標 ID 放在**扁平的具名參數**上，不在 input object 裡。
    #
    # @return [Array<Hash>]
    def not_found_errors
      [ { field: [ "id" ], message: I18n.t("errors.publication.not_found"), code: "NOT_FOUND" } ]
    end
  end
end
