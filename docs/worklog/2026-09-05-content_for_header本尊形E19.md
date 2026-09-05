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
| `app/services/render_parity/normalizer.rb` | E19 規則；收尾 PR：`compiled_assets` 路徑主題 id ⇒ `ID`（RP8） |
| `spec/services/render_parity/render_parity_spec.rb` | 收尾 PR：RP8（hoko `/t/2/` vs mirror `/t/7/` 抹後相等、`?v=` 已去） |
| `Seo::HeadTags`（原 app/services/seo/ 下的服務，已從樹上移除） | 刪除 |
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

## bt3 部署後複驗（收尾 PR；main `38debcbe`＝#344 squash）

部署：`ssh bt3-wan 'bash -s' < scratchpad/t10/bt3_deploy_e19.sh`（`scripts/deploy.sh origin/main` → puma 重啟 → `Rails.cache.clear` → `/up`）：pending migration 0、`demo /up 200`、
mirror 十頁型 200（`/products/nope` 404）；E19 端點（Host: mirror）：load_feature／trekkie／perf-kit／privacy-banner／shop-js loader／preloads／`cdn/shop/t/7/compiled_assets/scripts.js`／
oembed／atom 皆 200，`sf_private_access_tokens` 401、`POST /api/collect` 200；商品頁 Set-Cookie `_shopify_y`（一年）＋`_shopify_s`（30 分）`samesite=lax`。

`__head__` 逐節點對表（本機 `bash scratchpad/t10/verify_bt3_e19.sh`：公開 `https://mirror.chilling.com.hk` 抓頁 → `t10/head_diff.rb` 對 hoko 快照，經 `RenderParity::Normalizer`）：

| 頁 | hoko | mirror | 首跑 | RP8 後 |
|---|---|---|---|---|
| `/products/acme-tee` | 48 | 48 | 46/48 | 48/48 |
| `/zh-hant/products/acme-tee` | 48 | 48 | 46/48 | 48/48 |
| `/collections/all`／`?page=2`／`?sort_by=price-ascending` | 42／43／42 | 同 | 全同 | 全同 |
| `/collections`、`/`、`/cart`、`/search?q=tee`、`/pages/contact` | 41 | 41 | 全同 | 全同 |
| `/products/nope`（404） | 35 | 35 | 35/35 | 35/35 |

首跑兩節點差＝`sections-script`／`snippets-script` 的 `src` 主題 id（hoko `/cdn/shop/t/2/`、mirror `/cdn/shop/t/7/`）——本機 mirror 店主題 id 恰為 2 才碰巧全同；
主題 id 是身分值（同 shop id／theme-instance-id），本 PR 在 Normalizer 補 `compiled_assets` 路徑主題 id ⇒ `ID`（RP8），以已抓下的 bt3 HTML 重跑 `head_diff.rb` 後 48/48。
headless post-JS（`computed-parity.mjs evaljs`，等 6 秒）：`Shopify.loadFeatures`／`analytics.publish`／`captcha.protect` 皆 function、`PaymentButton` object、`window.trekkie` object、
`__st` 在、`#global-shopify-accelerated-checkout-styles` 在、頁面錯誤 0。

### 收尾 PR 閘門（凍結 tree （收尾 PR 首候選；commit 前的工作樹＝本 commit 內容） 後全跑，本機，dev server 已停；scratchpad `gates_e8b.py` 逐支以 bash.exe 執行 config/ci.rb 步驟）

| 閘門 | 命令 | 退出碼 | 摘要 |
|---|---|---|---|
| Style: Ruby | `bin/rubocop` | exit=0 | 1004 files inspected, no offenses detected |
| Security: Gem audit | `bin/bundler-audit` | exit=0 | No vulnerabilities found |
| Security: Frontend audit | `pnpm audit --audit-level high` | exit=0 | No known vulnerabilities found |
| Security: Brakeman code analysis | `bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error` | exit=0 | No warnings found |
| Test: Rails | `bundle exec rspec` | exit=0 | （未解析） |
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
| doc-claims 兩支（本表寫入後補跑） | `ruby scripts/check-doc-claims.rb --base origin/main --require-base`／`ruby scripts/test-doc-claims-rules.rb` | 見 PR body | |

### 收尾 PR 突變（commit 後跑 scratchpad `t10/mutate_closure.py`；改一處 → 目標規格轉紅 → `git checkout --` 還原；工作樹還原後 clean）

| 突變 | 改處 | 目標 | 結果 |
|---|---|---|---|
| M214 移除 `compiled_assets` 主題 id 規則 | normalizer.rb | RP8 | RED ✓（v2 腳本實跑：rspec exit=1、`8 examples, 1 failure`＝RP8 `expected …/t/7/… got …/t/2/…`；還原後 `git status` 乾淨、規則在） |

🔴 事故更正（2026-09-05，鐵律 19.5／20.4；20.2 類型 5「管道尾端吞退出碼」＋類型 7「Windows 編碼假結果」）：本 PR 首推 head `0b1e19fd` 的上列曾寫「RED ✓」，
但當時的突變腳本 v1 ①把 rspec 接在 `| tail` 之後 ⇒ 取到 tail 的退出碼 0、印出 NOT RED；②隨後 `print` 在 cp950 主控台遇 `⇒` 崩潰，**還原步驟排在崩潰之後、沒有執行**；
③外層 Bash 鏈也把腳本接在 `| grep | head` 後，非零退出被吞、`&&` 鏈沒停 ⇒ `git add -A`＋`commit --amend` 把**突變後（規則已移除）的 normalizer.rb** 連同「RED ✓」一起推出。
復發錨＝記憶 `mutation-revert-trap`（E3c：突變還原沖掉未 commit 修法）的同型第二例，方向相反：這次是還原沒發生。既有防線「先 commit 再突變」有做；漏掉的是「突變腳本自身的退出碼判讀與還原
不得受管線／主控台編碼影響」。固定處理＝腳本 v2（scratchpad `t10/mutate_closure.py`）：rspec 不走管線、`sys.stdout.reconfigure(utf-8)`、還原放 `finally`、還原後斷言工作樹乾淨且規則存在；
外層不再用管線接突變腳本。反向複驗（可重跑）：`git show 0b1e19fd:app/services/render_parity/normalizer.rb | grep -c 'compiled_assets/)}'` ⇒ 0（壞 head）；
`git show HEAD:app/services/render_parity/normalizer.rb | grep -c 'compiled_assets/)}'` ⇒ 1；`git diff --stat 489e135d HEAD -- app spec config` 空（程式樹逐位元＝閘門樹 `489e135d`，
故閘門表仍有效；docs 變更只補跑 doc-claims 兩支）。更正 commit＝「更正①」（還原規則）＋「更正②」（本段與上列）。

## 尚未完成或需注意的風險 (Pending / TODO)

- bt3 複驗已收（上節）。T12（主題資產 URL 本尊形）時，Normalizer 的 `CDN_ASSET_RE`（`/cdn/shop/t/{n}/assets/` ⇒ `/theme-assets/`）與本 PR 的 `compiled_assets` 主題 id 規則要收成同一組主題路徑規則，別各抹各的。
- E19b：同意 API／驗證碼／web pixels／分析收集端落庫／`/api/mcp`（T11）——stub 介面已立。
- 91 §3.88 V 清單（`__st.u` 語義、旗標值、themeCityHash／apiClientId、article／policies 頁型、`rel=next`、block 歸屬與壓縮、非 200 頁、hreflang 其餘 query 鍵、oEmbed in_stock／description、Atom updated／排序、designMode 位置）。
- 🔴 平台不再注 canonical／JSON-LD：主題必須自出（Ella 有；其他主題對表時檢查）。
- 🔴 heredoc 補丁教訓（91 §3.88 末條）：長 Bash heredoc 含引號整段解析失敗——補丁一律寫檔再執行。
