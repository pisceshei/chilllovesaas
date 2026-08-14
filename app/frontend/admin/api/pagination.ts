/**
 * 分頁常數（前端側鏡像）。
 *
 * 單一真相是 `config/limits.yml` 的 `api.pagination_default_page_size`（鐵律 6）；
 * 前端無法在執行期讀 YAML，故此處鏡像其值並以本註釋綁定出處——
 * 改 limits.yml 的該鍵時必須同步改這裡（server 端會以
 * `api.pagination_max_page_size`＝250 硬夾上限，鏡像漂移不會越權，只會拿錯頁量）。
 * 原骨架將 50 硬編碼於 ProductsPage.tsx，2026-08-13 移植時外移。
 */
export const DEFAULT_PAGE_SIZE = 50;
