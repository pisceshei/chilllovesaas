# M2 — 上架事件層（S8／D74）

> 對應規格：`docs/plans/2026-08-26-發布與可見性-分步執行方案.md` §S8；
> 裁定＝`docs/DECISIONS.md` D74；範圍外登記＝`docs/specs/91-pit-register.md` §3.45。
> 官方錨（取證日期見 D74）：WebhookSubscriptionTopic 的 ADD／REMOVE／UPDATE 三句逐字
> ＋ scheduled-product-publishing 的「At the scheduled datetime …」。

## ①這是什麼

發布狀態變更 → 對外上架事件（`product_listings/add|remove|update`；
變體＝ours 的 `variant_listings/*`）。事件只進 `event_outbox`（EXTERNAL topic），
**訂閱與投遞面是未來包**（§3.45 W-1）。

## ②事件矩陣（規則本體）

| 轉場 | 事件 | 閘 |
|---|---|---|
| 未發布 → 已發布（立即 publish） | ADD | 🔴 `PURCHASABLE_STATUSES`（變體看父商品）；不合格＝不發 |
| 排程未來（寫入當下） | —（無） | 到點才由 translator 發 ADD（官方逐字） |
| 到點 ∧ 列已生效 ∧ 閘通過 | ADD（translator） | 同上；冪等靠 `dedupe_key` |
| 已發布 → 已發布但改 `published_at` | UPDATE | 無閘 |
| 刪**已發布**列（unpublish） | REMOVE | 無閘（draft 也發，官方無 active 限定） |
| 刪「排程中未到點」列 | —（fail-closed） | 從未 listed 過（§3.45） |
| 已發布 → 改排程未來（R6） | —（fail-closed） | 本尊語義未取得（§3.45 W-3） |
| `status_transition` 形狀 | —（fail-closed） | 逐管道 diff 未取得（§3.45 W-2） |
| Collection 任何轉場 | —（無） | 本尊無 collection listing topic |

## ③怎麼做出來

- 即時面：`Publications::Write#emit_listing_transition!`（`apply_publication!` 落地後、
  同一交易內；鐵律 5）＋ `remove_publication!` 的已發布判定。
- 到點面：`Publications::ListingEventTranslator`（`product.publication.changed` 的
  第二個消費者）。🔴 **判準依 DB 現值不比對 payload**——PR-C 消費者到點會改寫
  `published_at`，兩消費者順序不保證；比 payload 的實作在「排後面跑」時每筆都
  誤判 superseded（全文＝該檔 ②）。
- 冪等：即時面在寫入交易內單次執行；到點面 `dedupe_key = "listing-add:<event_id>"`
  ＋ `uq_event_outbox_dedupe_key` 唯一索引，重放 rescue `RecordNotUnique` 成 no-op。

## ④跨功能影響

`Events::Topics`（EXTERNAL +6）／`Events::Consumers::REGISTRY`（同 topic 兩消費者）／
`Publications::Write`（發射點）／未來 webhook 訂閱白名單（EXTERNAL 即種子）。
快取失效面不變：stamp bump 仍由 Write（立即）與 PR-C 消費者（到點）負責，
本層**不碰** `publications_updated_at`。

## 驗收

`spec/services/publications/listing_events_spec.rb` 13 格（🔴 假綠殺手 5 格）；
五個活突變全部轉紅（D74 列表）；PR-C 24 格照綠。
