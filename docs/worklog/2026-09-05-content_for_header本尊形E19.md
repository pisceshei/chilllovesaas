# 2026-09-05 content_for_header 完整本尊形 E19a（路線圖 T10）

> 規範＝`docs/dev/e19-content-for-header.md`；取證＝`docs/dev/external-facts.md` §G27；未取得／範圍外＝`docs/specs/91-pit-register.md` §3.88；
> handoff＝`docs/handoff/2026-09-05-content_for_header本尊形E19.md`。裁定依據 D84（任何不同即修）。

## 已完成的工作 (Done)

- **取證（hoko.vip 74 頁快照＋CDN，2026-09-05）**：content_for_header 邊界（主題 `window.routes` 之後到 `</head>` 全部）、24 種節點序列歸類（商品頁 38 節點、
  非商品頁 31–33、404 頁 25）、頁型變體判準（模組形＝本頁渲染了 `payment_button`；atom／prev／oembed／hreflang 出現條件）、資料節點形（`shopify-features`、
  `Shopify.*` 逐字、`__st` 各頁型鍵、`shop-js-analytics`／perf-kit 頁型詞彙、`ShopifyAnalytics.meta`、trekkie track 三種、web pixels 事件）、Set-Cookie／meta、
  `preloads.js` locale 形、`compiled_assets` 格式（block JS 併入 section 門控）、oEmbed／Atom（五語言標籤）／`sf_private_access_tokens`／`digital_wallets/dialog`／
  `/api/collect` 端點，全部落 §G27；官方句（content_for_header、javascript／stylesheet tag、JavaScript and stylesheet tags 最佳實務）。
- **實作**：`Storefront::ContentForHeader`（Lazy 延遲組裝；38＋10 節點；頁型變體；每請求 placeholder）、`Storefront::RequestValues`（代入＋`_shopify_y`／`_shopify_s`）、
  `ThemeEngine::ShopifyGlobal` 本尊逐字形（移除 PR-3 的 ours 擴充）、`Storefront::DynamicCheckoutHead` 分形（module／cart.bootstrap／styles）、
  `Storefront::PlatformAssets`＋10 支自寫 stub（load_feature／origin_trials／autosizes／shop_events_listener／trekkie／perf_kit／privacy_banner／shop_js_loader／webmcp／preloads）、
  `Storefront::CompiledAssets`（scripts.js／snippet-scripts.js）、`Storefront::PlatformAssetsController`（stub／編譯／401／collect／dialog）、`Storefront::FeedsController`
  （oembed／collection atom／blog atom）、runtime 記錄（payment_button／sections／snippets）、`SectionDrop#type`、Normalizer 平台規則、limits `content_for_header.*`、
  `_platform.atom` 五語言、路由 17 條（含前綴形三條）。`Seo::HeadTags` 退場（平台不注 canonical／JSON-LD）；fixture layout 補主題 canonical。
- 既有規格依本尊事實更正：SEO1（canonical 恰一個、404 頁主題同出）、SEO3／SEO8（改測 `Seo::JsonLd` 單元）、MR4（x-default 首）。

## 修改的檔案與核心邏輯 (Changes)

| 檔 | 變動 |
|---|---|
| `app/services/storefront/content_for_header.rb`（新） | 建構器＋`Lazy` |
| `app/services/storefront/request_values.rb`（新） | placeholder 代入、cookie |
| `app/services/storefront/platform_assets.rb`（新）＋`app/assets/storefront/platform/*.js`（新 10 檔） | stub 登記／本體 |
| `app/services/storefront/compiled_assets.rb`（新） | `{% javascript %}` 編譯 |
| `app/controllers/storefront/platform_assets_controller.rb`／`feeds_controller.rb`（新） | 端點 |
| `app/services/storefront/dynamic_checkout_head.rb` | `variant:`／`styles` |
| `app/liquid/theme_engine/shopify_global.rb` | 本尊逐字形 |
| `app/liquid/theme_engine/page_renderer.rb` | assign `Lazy`；移除 `</head>` 插入與 HeadTags |
| `app/liquid/theme_engine/runtime.rb`／`tags.rb`／`filters.rb`／`drops.rb` | 記錄器、`record_file`、旗標、`SectionDrop#type` |
| `app/controllers/storefront/pages_controller.rb`／`admin/storefront_preview_controller.rb` | `RequestValues.substitute` |
| `app/services/render_parity/normalizer.rb` | E19 規則 |
| `app/services/seo/head_tags.rb` | 刪除 |
| `config/routes.rb`、`config/limits.yml`、`config/storefront_locales/*.yml` | 路由／limits／atom 標籤 |
| `spec/requests/storefront_content_for_header_spec.rb`（新 C1–C9）、fixture `product.e19.json`／`js-probe.liquid`／`js-snippet.liquid`／`_js-block.liquid`／layout canonical、`storefront_seo_spec.rb`、`render_parity/mirror_spec.rb` | 驗證 |
| `docs/dev/e19-content-for-header.md`（新）、external-facts §G27、91 §3.88、路線圖 T10／T12 | 規範／取證／V／路線圖 |

## 閘門（凍結 tree （首候選；commit 前的工作樹＝本 commit 內容；RF15 期望修正後全跑第二次） 後全跑，本機，dev server 已停；scratchpad `gates_e8b.py` 以 `PYTHONIOENCODING=utf-8` 逐支以 bash.exe 執行 config/ci.rb 步驟）

| 閘門 | 命令 | 退出碼 | 摘要 |
|---|---|---|---|
| Style: Ruby | `bin/rubocop` | exit=0 | 1004 files inspected, no offenses detected |
| Security: Gem audit | `bin/bundler-audit` | exit=0 | No vulnerabilities found |
| Security: Frontend audit | `pnpm audit --audit-level high` | exit=0 | No known vulnerabilities found |
| Security: Brakeman code analysis | `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | exit=0 | No warnings found |
| Test: Rails | `bundle exec rspec` | exit=0 | 2197 examples（總數取自凍結前一輪全跑；閘門 log 尾段被 rack 棄用警告佔滿）；RF15 期望修正後第二輪 exit=0 |
| Test: Frontend | `pnpm test` | exit=0 |  |
| Type check: Frontend | `pnpm typecheck` | exit=0 |  |
| Build: Frontend | `pnpm build` | exit=0 |  |
| Invariants: Exec bits | `bash scripts/check-exec-bits.sh` | exit=0 |  |
| Invariants: Exec bit rules regression | `bash scripts/test-exec-bits-rules.sh` | exit=0 |  |
| Invariants: Prototype lint | `python scripts/lint-prototype.py` | exit=0 | ERROR 0 / WARN 136 |
| Invariants: Lint rules regression | `python scripts/test-lint-rules.py` | exit=0 |  |
| Invariants: Dead-control baseline | `python scripts/check-baseline-raise.py` | exit=0 |  |
| Invariants: Doc claims | `ruby scripts/check-doc-claims.rb` | exit=0 |  |
| Invariants: Doc claim rules regression | `ruby scripts/test-doc-claims-rules.rb` | exit=0 |  |
| Invariants: Tenant isolation | `ruby scripts/check-tenant-isolation.rb` | exit=0 |  |
| Invariants: Design token single source | `ruby scripts/check-tokens-sync.rb` | exit=0 |  |
| Invariants: Reversal naming | `ruby scripts/check-reversal-naming.rb` | exit=0 |  |
| Invariants: Money unit boundary | `ruby scripts/check-money-boundary.rb` | exit=0 |  |
| Invariants: Money rules regression | `ruby scripts/test-money-rules.rb` | exit=0 |  |
| Invariants: Limits key types | `ruby scripts/check-limits-keys.rb` | exit=0 |  |
| Invariants: Limits key rules regression | `ruby scripts/test-limits-key-rules.rb` | exit=0 |  |
| Invariants: Rem token integrity | `ruby scripts/check-rem-tokens.rb` | exit=0 |  |
| Invariants: Rem token rules regression | `ruby scripts/test-rem-token-rules.rb` | exit=0 |  |
| Invariants: CI parity (ci.yml ⊆ config/ci.rb) | `ruby scripts/check-ci-parity.rb` | exit=0 |  |
| Invariants: CI parity rules regression | `ruby scripts/test-ci-parity-rules.rb` | exit=0 |  |
| Invariants: Workflow syntax | `ruby scripts/check-workflow-syntax.rb` | exit=0 |  |
| Invariants: Workflow syntax rules regression | `ruby scripts/test-workflow-syntax-rules.rb` | exit=0 |  |
| doc-claims 兩支（worklog 閘門表寫入後補跑） | `ruby scripts/check-doc-claims.rb`／`ruby scripts/test-doc-claims-rules.rb` | 見 PR body | |

### 突變（commit `df1c0621` 後跑 scratchpad `t10/mutate_e19.py`＋`mutate_e19_m205.py`；每格改一處 → 目標規格轉紅 → `git checkout --` 還原；工作樹還原後 clean）

| 突變 | 改處 | 目標 | 結果 |
|---|---|---|---|
| M203 x-default 不移到首 | content_for_header.rb | C1 | RED ✓ |
| M204 商品頁不出 oembed link | content_for_header.rb | C1 | RED ✓ |
| M205 集合頁不出 atom link | content_for_header.rb | C2 | RED ✓ |
| M206 `__st` 對集合頁也出 rtyp／rid | content_for_header.rb | C2 | RED ✓ |
| M207 hreflang 保留 sort_by | content_for_header.rb | C2 | RED ✓ |
| M208 placeholder 不代入 | request_values.rb | C5 | RED ✓ |
| M209 compiled scripts 不含 block JS | compiled_assets.rb | C7 | RED ✓ |
| M210 snippet 檔不記錄 | tags.rb | C7 | RED ✓ |
| M211 oembed price 出 cents | feeds_controller.rb | C8 | RED ✓ |
| M212 Normalizer 不抹 `pageurl` 主機 | normalizer.rb | C9 | RED ✓ |
| M213 全域 script 多出 formatMoney | shopify_global.rb | C4 | RED ✓ |

## 尚未完成或需注意的風險 (Pending / TODO)

- bt3 部署後 `__head__` 段對表（Normalizer 後 hoko vs mirror 逐節點）與公開 mirror 端點抽查——收尾 PR。
- E19b：同意 API／驗證碼／web pixels／分析收集端落庫／`/api/mcp`（T11）——stub 介面已立。
- 91 §3.88 V 清單（`__st.u` 語義、旗標值、themeCityHash／apiClientId、article／policies 頁型、`rel=next`、block 歸屬與壓縮、非 200 頁、hreflang 其餘 query 鍵、oEmbed in_stock／description、Atom updated／排序、designMode 位置）。
- 🔴 平台不再注 canonical／JSON-LD：主題必須自出（Ella 有；其他主題對表時檢查）。
- 🔴 heredoc 補丁教訓（91 §3.88 末條）：長 Bash heredoc 含引號整段解析失敗——補丁一律寫檔再執行。
