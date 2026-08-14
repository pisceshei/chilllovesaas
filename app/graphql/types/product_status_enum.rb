# GraphQL 公開的商品狀態列舉。
#
# Database 以小寫字串保存狀態；GraphQL 以穩定的大寫 enum token 對外，避免
# client 依賴 persistence spelling。見 docs/research/28 §0.2–0.3。
#
# 🔴 值由 `config/limits.yml` 的 `product.status_values` 產生（鐵律 6），
# 不逐個 `value` 硬編。三份清單（limits.yml／`Product::STATUSES`／本 enum）
# 若各寫一份，漂移不會有任何跡象——本 enum 的第四個值 `UNLISTED` 就是
# 這樣漏掉的：limits.yml 從一開始就是四值，model 與 enum 停在三值。
#
# 🔴 **不做舊 API 版本降級**（`limits.yml:817` `unlisted_downgrade_on_old_api_version: false`，
# 刻意偏離本尊，13 §F1.2(f)）。Shopify 對舊版 API 把 `UNLISTED` 回成 `ACTIVE`，
# 那會讓舊版整合把它當 ACTIVE 處理、再送進 feed 與索引，**等於 noindex 完全失效**。
# 我方 enum 一次到位四值，任何版本一律照實回 `UNLISTED`。
class Types::ProductStatusEnum < GraphQL::Schema::Enum
  graphql_name "ProductStatus"
  description "商品在 Admin API 中的生命週期狀態。"

  # 每個值的說明取自 docs/specs/13 §F1.2 的真值表（purchasable × discoverable）。
  DESCRIPTIONS = {
    "ACTIVE" => "可販售也可被發現。直接 URL 回 200，並進入 sitemap、站內搜尋、商品系列與各管道 feed。",
    "DRAFT" => "尚未備妥，顧客在任何管道都取用不到；直接 URL 回 404。",
    "ARCHIVED" => "已停售，顧客在任何管道都取用不到；直接 URL 回 404。",
    "UNLISTED" => "可購買但不可被發現。拿到直接連結的顧客流程與 ACTIVE 相同，但不進搜尋、系列、sitemap 與任何 feed。"
  }.freeze

  Limits.enum(:product, :status_values).each do |token|
    value token, DESCRIPTIONS.fetch(token), value: token.downcase
  end
end
