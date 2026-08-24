import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Button } from "./Button";
import { InventoryAdjustPopover } from "./InventoryAdjustPopover";
import type { StagedAdjustment } from "./InventoryAdjustPopover";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { uuidV4 } from "../lib/uuid";
import { ADJUSTMENT_REASONS_MANUAL_UI } from "../lib/inventoryLimits";

/**
 * 商品頁的庫存卡（排程第 18 包 B 塊）。
 *
 * ①這是什麼：該商品每個 (變體 × 地點) 一列，Available 與 Total（＝on_hand，本尊商品頁
 *   把這欄叫 Total——實測 `docs/research/94` §2b⑤）可點開**同一個** `InventoryAdjustPopover`。
 * ②值域：與庫存列表完全相同（reason 7 值、模式二值、可調欄二值）——刻意共用元件，
 *   兩處值域不可能漂移。
 * ③怎麼做：**兩段式**（stage → 儲存），但用**卡內自己的儲存鈕**，不掛頁面 SaveBar。
 *   🔴 這是一條**與本尊的刻意差異**（本尊商品頁的庫存調整走頁面同一個 Save）：
 *   商品頁的 SaveBar 屬於 `productSet` 那棵樹，把庫存寫入併進去會讓**一顆按鈕觸發兩條
 *   非原子的 API**——其中一條失敗時商家看不出哪一半存進去了。分開的按鈕語義誠實。
 *   已登記為待驗證項（見 worklog）；若日後裁定要合併，改的是本檔與 ProductDetailPage 的
 *   save handler，資料契約不動。
 * ④跨功能影響：元件與庫存列表（A 塊）、第 29 包變體子頁共用 `StagedAdjustment` 契約；
 *   寫入一律經唯一入口（D43 cop 守著）；歷程連結指向 C 塊。
 */
interface InventoryRow {
  readonly id: string;
  readonly sku: string | null;
  readonly tracked: boolean;
  readonly variantTitle: string;
  readonly locationId: string;
  readonly quantities: { readonly available: number; readonly onHand: number };
}

interface CardQueryData {
  readonly inventoryItems: { readonly nodes: InventoryRow[] };
  readonly locations: { readonly id: string; readonly name: string }[];
}

const CARD_QUERY = `
  query ProductInventory($first: Int!, $productId: ID!, $locationId: ID) {
    inventoryItems(first: $first, productId: $productId, locationId: $locationId) {
      nodes {
        id
        sku
        tracked
        variantTitle
        locationId
        quantities { available onHand }
      }
    }
    locations { id name }
  }
`;

const ADJUST_MUTATION = `
  mutation ProductInventoryAdjust($key: String!, $input: InventoryAdjustQuantitiesInput!) {
    inventoryAdjustQuantities(idempotencyKey: $key, input: $input) {
      inventoryAdjustmentGroup { id }
      userErrors { field message code }
    }
  }
`;

const SET_MUTATION = `
  mutation ProductInventorySet($key: String!, $input: InventorySetQuantitiesInput!) {
    inventorySetQuantities(idempotencyKey: $key, input: $input) {
      inventoryAdjustmentGroup { id }
      userErrors { field message code }
    }
  }
`;

interface InventoryCardProps {
  /** 商品 GID。 */
  readonly productId: string;
}

export function InventoryCard({ productId }: InventoryCardProps) {
  const navigate = useNavigate();
  const t = useT();
  const { showToast } = useToast();
  const [rows, setRows] = useState<InventoryRow[] | null>(null);
  const [locations, setLocations] = useState<{ id: string; name: string }[]>([]);
  // 🔴 選取地點與「目前資料屬於哪個地點」是兩件事。
  // `selection` 只在使用者**主動改選**時才有值；null＝用伺服器解析的預設地點。
  // 兩者混成一個 state 會 mount 時抓兩次（"" → 抓 → 設成 L1 → 又抓），
  // 白抓的那次還會蓋掉使用者在等待期間 stage 的東西。
  const [selection, setSelection] = useState<string | null>(null);
  const [resolvedLocationId, setResolvedLocationId] = useState("");
  const [openCell, setOpenCell] = useState<string | null>(null);
  const [pending, setPending] = useState<Map<string, StagedAdjustment>>(new Map());
  const [saving, setSaving] = useState(false);
  const [requestKey, setRequestKey] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    // 🔴 頁量引鏡像常數不硬編（鐵律 6）。單一商品最多 product.max_variants=2048 個變體，
    // 超過一頁的部分本包不分頁——已記進 docs/dev/m1-inventory-ui.md 的限制段。
    void requestAdminGraphQL<CardQueryData, { first: number; productId: string; locationId: string | null }>(
      CARD_QUERY,
      { first: DEFAULT_PAGE_SIZE, productId, locationId: selection },
      controller.signal,
    )
      .then((data) => {
        setRows(data.inventoryItems.nodes);
        setLocations(data.locations);
        // 資料屬於哪個地點由回應自己說（第一列的 locationId），不由前端猜
        setResolvedLocationId(selection ?? data.inventoryItems.nodes[0]?.locationId ?? data.locations[0]?.id ?? "");
      })
      .catch(() => {
        if (!controller.signal.aborted) setRows([]);
      });
    return () => controller.abort();
  }, [productId, selection, requestKey]);

  const locationId = selection ?? resolvedLocationId;
  const locationName = useMemo(
    () => locations.find((location) => location.id === locationId)?.name ?? "",
    [locations, locationId],
  );

  const save = useCallback(async () => {
    if (pending.size === 0) return;
    setSaving(true);
    const failures: string[] = [];
    for (const [key, staged] of pending) {
      const itemId = key.split("::")[0];
      const change =
        staged.mode === "set"
          ? { inventoryItemId: itemId, locationId, quantity: staged.value, compareQuantity: staged.compareAgainst }
          : { inventoryItemId: itemId, locationId, delta: staged.value, changeFromQuantity: staged.compareAgainst };
      try {
        const data = await requestAdminGraphQL<Record<string, { userErrors: { message: string }[] }>, Record<string, unknown>>(
          staged.mode === "set" ? SET_MUTATION : ADJUST_MUTATION,
          { key: uuidV4(), input: { reason: staged.reason, name: staged.name, changes: [ change ] } },
        );
        const payload = data[staged.mode === "set" ? "inventorySetQuantities" : "inventoryAdjustQuantities"];
        payload.userErrors.forEach((userError) => failures.push(userError.message));
      } catch (reason: unknown) {
        failures.push(reason instanceof Error ? reason.message : t("inventory.saveError"));
      }
    }
    setSaving(false);
    setPending(new Map());
    setRequestKey((key) => key + 1);
    if (failures.length > 0) failures.forEach((message) => showToast(message));
    else showToast(t("inventory.saved"));
  }, [pending, locationId, showToast, t]);

  function cell(row: InventoryRow, name: "available" | "on_hand", value: number) {
    const key = `${row.id}::${name}`;
    if (!row.tracked) return <span>{t("inventory.untracked")}</span>;
    if (openCell === key) {
      return (
        <InventoryAdjustPopover
          current={value}
          locationName={locationName}
          name={name}
          onCancel={() => setOpenCell(null)}
          onStage={(staged) => {
            setPending((prev) => new Map(prev).set(key, staged));
            setOpenCell(null);
          }}
          reasons={ADJUSTMENT_REASONS_MANUAL_UI}
        />
      );
    }
    const staged = pending.get(key);
    return (
      <button className="cl-inventory-qty" onClick={() => setOpenCell(key)} type="button">
        {staged ? (
          <span className="cl-inventory-qty__pending">
            {value} → <strong>{staged.projected}</strong>
          </span>
        ) : (
          <span>{value}</span>
        )}
      </button>
    );
  }

  if (rows === null) return <p className="cl-muted">{t("inventory.loading")}</p>;
  if (rows.length === 0) return <p className="cl-muted">{t("product.inventory.none")}</p>;

  return (
    <div className="cl-inventory-card">
      {locations.length > 1 ? (
        <label className="cl-field">
          <span className="cl-field__label">{t("inventory.location")}</span>
          <select
            aria-label={t("inventory.location")}
            className="cl-field__input"
            onChange={(event) => setSelection(event.currentTarget.value)}
            value={locationId}
          >
            {locations.map((location) => (
              <option key={location.id} value={location.id}>
                {location.name}
              </option>
            ))}
          </select>
        </label>
      ) : null}

      <table className="cl-inventory-card__table">
        <caption className="cl-sr-only">{t("product.inventory.caption")}</caption>
        <thead>
          <tr>
            <th scope="col">{t("product.inventory.variant")}</th>
            <th scope="col">{t("inventory.col.available")}</th>
            {/* 本尊商品頁把 on_hand 這一欄叫 Total（實測 94 §2b⑤） */}
            <th scope="col">{t("product.inventory.total")}</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr key={row.id}>
              <th scope="row">
                {row.variantTitle}
                {row.sku ? <small>{row.sku}</small> : null}
              </th>
              <td>{cell(row, "available", row.quantities.available)}</td>
              <td>{cell(row, "on_hand", row.quantities.onHand)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <div className="cl-inventory-card__actions">
        <Button
          onClick={() => navigate(`/admin/inventory/${encodeURIComponent(rows[0].id)}/history`)}
          size="small"
          variant="ghost"
        >
          {t("inventory.viewHistory")}
        </Button>
        {pending.size > 0 ? (
          <Button loading={saving} loadingLabel={t("common.saving")} onClick={() => void save()} size="small" variant="primary">
            {t("product.inventory.save")}
          </Button>
        ) : null}
      </div>
    </div>
  );
}
