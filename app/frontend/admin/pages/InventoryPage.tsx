import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Download, RefreshCw, Search, Upload } from "lucide-react";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { InventoryAdjustPopover } from "../components/InventoryAdjustPopover";
import type { StagedAdjustment } from "../components/InventoryAdjustPopover";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useSaveBarRegister } from "../lib/SaveBarContext";
import { useToast } from "../lib/ToastContext";
import { uuidV4 } from "../lib/uuid";
import { ADJUSTMENT_REASONS_MANUAL_UI } from "../lib/inventoryLimits";

/**
 * 庫存列表 `/admin/inventory`（排程第 18 包 A 塊）。
 *
 * ①這是什麼：單一地點視角的庫存列表，八欄（縮圖除外的七欄取自實測 `docs/research/94` §2.1）：
 *   商品｜SKU｜Unavailable｜Committed｜Available｜On hand｜Incoming。
 * ②值域與規則：
 *   - 可點開調整器的只有 **Available 與 On hand** 兩欄（實測；committed 由訂單線獨佔、
 *     incoming 由採購/轉移線獨佔，unavailable 是導出值）。
 *   - reason 下拉＝UI 7 值子集（`lib/inventoryLimits.ts` 鏡射 limits.yml，鐵律 6）。
 *   - Export／Import **disabled**：CSV 匯入匯出＝D43 明文延後。放可按卻沒反應的鈕更糟。
 * ③怎麼做：**兩段式**（help 明文）——✓ 只把調整標成 pending，儲存格顯示 `9 → 10`
 *   （Available 與 On hand 兩欄同時預覽，實測形態）；SaveBar 的 Save 才逐筆送 mutation。
 *   每筆 pending 各自一把 UUID 冪等鍵（G28 契約層必填）。離頁丟棄（未 Save 的 pending 不保留）。
 *   🔴 CAS 基準是**載入時的現值**，原樣送伺服器；stale 由伺服器回碼，前端只顯示並重載。
 * ④跨功能影響：調整器元件與商品頁庫存卡（B 塊）、第 29 包變體子頁共用；
 *   寫入一律經 `inventoryAdjustQuantities`／`inventorySetQuantities`（唯一入口，D43 cop 守著）；
 *   本頁不碰 committed／incoming（那兩條線各自的里程碑）。
 */
interface InventoryQuantities {
  readonly unavailable: number;
  readonly committed: number;
  readonly available: number;
  readonly onHand: number;
  readonly incoming: number;
}

interface InventoryRow {
  readonly id: string;
  readonly sku: string | null;
  readonly tracked: boolean;
  readonly productTitle: string;
  readonly variantTitle: string;
  readonly productId: string;
  readonly locationId: string;
  readonly quantities: InventoryQuantities;
}

interface LocationOption {
  readonly id: string;
  readonly name: string;
}

interface InventoryQueryData {
  readonly inventoryItems: { readonly nodes: InventoryRow[] };
  readonly locations: LocationOption[];
}

const INVENTORY_QUERY = `
  query InventoryIndex($first: Int!, $locationId: ID, $query: String) {
    inventoryItems(first: $first, locationId: $locationId, query: $query) {
      nodes {
        id
        sku
        tracked
        productTitle
        variantTitle
        productId
        locationId
        quantities { unavailable committed available onHand incoming }
      }
      pageInfo { hasNextPage endCursor }
    }
    locations { id name }
  }
`;

const ADJUST_MUTATION = `
  mutation InventoryAdjust($key: String!, $input: InventoryAdjustQuantitiesInput!) {
    inventoryAdjustQuantities(idempotencyKey: $key, input: $input) {
      inventoryAdjustmentGroup { id }
      userErrors { field message code }
    }
  }
`;

const SET_MUTATION = `
  mutation InventorySet($key: String!, $input: InventorySetQuantitiesInput!) {
    inventorySetQuantities(idempotencyKey: $key, input: $input) {
      inventoryAdjustmentGroup { id }
      userErrors { field message code }
    }
  }
`;

/** pending 的鍵＝品項 GID ＋ 數量名（同一格重複調整以最後一次為準）。 */
type PendingKey = `${string}::${"available" | "on_hand"}`;

function pendingKey(itemId: string, name: "available" | "on_hand"): PendingKey {
  return `${itemId}::${name}`;
}

export function InventoryPage() {
  const navigate = useNavigate();
  const t = useT();
  const { showToast } = useToast();
  const [rows, setRows] = useState<InventoryRow[] | null>(null);
  const [locations, setLocations] = useState<LocationOption[]>([]);
  const [locationId, setLocationId] = useState<string>("");
  const [searchValue, setSearchValue] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);
  const [openCell, setOpenCell] = useState<PendingKey | null>(null);
  const [pending, setPending] = useState<Map<PendingKey, StagedAdjustment>>(new Map());
  const [saving, setSaving] = useState(false);

  // 300ms 去抖（同商品列表：每個按鍵都打伺服器是浪費，也會讓結果閃爍）
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(searchValue.trim()), 300);
    return () => clearTimeout(timer);
  }, [searchValue]);

  useEffect(() => {
    const controller = new AbortController();
    setError(null);
    void requestAdminGraphQL<InventoryQueryData, { first: number; locationId: string | null; query: string | null }>(
      INVENTORY_QUERY,
      { first: DEFAULT_PAGE_SIZE, locationId: locationId || null, query: debouncedQuery || null },
      controller.signal,
    )
      .then((data) => {
        setRows(data.inventoryItems.nodes);
        setLocations(data.locations);
        if (!locationId && data.locations.length > 0) setLocationId(data.locations[0].id);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("inventory.loadError"));
      });
    return () => controller.abort();
  }, [requestKey, debouncedQuery, locationId, t]);

  const reload = useCallback(() => setRequestKey((key) => key + 1), []);

  const stage = useCallback((itemId: string, staged: StagedAdjustment) => {
    setPending((prev) => new Map(prev).set(pendingKey(itemId, staged.name), staged));
    setOpenCell(null);
  }, []);

  const discard = useCallback(() => {
    setPending(new Map());
    setOpenCell(null);
  }, []);

  const save = useCallback(async () => {
    if (pending.size === 0) return;
    setSaving(true);
    const failures: string[] = [];
    // 逐筆送：一次呼叫＝一把冪等鍵＝一筆 group（後端契約），不合併成一次多 change——
    // 合併會讓其中一格 stale 時整批被拒，商家看不出是哪一格。
    for (const [key, staged] of pending) {
      const itemId = key.split("::")[0];
      const base = {
        reason: staged.reason,
        name: staged.name,
        changes: [
          staged.mode === "set"
            ? {
                inventoryItemId: itemId,
                locationId,
                quantity: staged.value,
                compareQuantity: staged.compareAgainst,
              }
            : {
                inventoryItemId: itemId,
                locationId,
                delta: staged.value,
                changeFromQuantity: staged.compareAgainst,
              },
        ],
      };
      try {
        const data = await requestAdminGraphQL<Record<string, { userErrors: { message: string }[] }>, Record<string, unknown>>(
          staged.mode === "set" ? SET_MUTATION : ADJUST_MUTATION,
          { key: uuidV4(), input: base },
        );
        const payload = data[staged.mode === "set" ? "inventorySetQuantities" : "inventoryAdjustQuantities"];
        payload.userErrors.forEach((userError) => failures.push(userError.message));
      } catch (reason: unknown) {
        failures.push(reason instanceof Error ? reason.message : t("inventory.saveError"));
      }
    }
    setSaving(false);
    setPending(new Map());
    // 🔴 一律重載：CAS 判定在伺服器，前端的 projected 只是預覽——重載才是真相。
    reload();
    if (failures.length > 0) {
      failures.forEach((message) => showToast(message));
    } else {
      showToast(t("inventory.saved"));
    }
  }, [pending, locationId, reload, showToast, t]);

  const registerSaveBar = useSaveBarRegister();
  useEffect(() => {
    if (pending.size === 0) {
      registerSaveBar(null);
      return;
    }
    registerSaveBar({
      dirty: true,
      saving,
      onSave: () => void save(),
      onDiscard: discard,
      shakeSignal: 0,
    });
    return () => registerSaveBar(null);
  }, [pending, saving, save, discard, registerSaveBar]);

  const locationName = useMemo(
    () => locations.find((location) => location.id === locationId)?.name ?? "",
    [locations, locationId],
  );

  /** 數量儲存格：pending 時顯示 `9 → 10`；可調欄位點擊展開調整器。 */
  const quantityCell = useCallback(
    (row: InventoryRow, name: "available" | "on_hand", value: number) => {
      const staged = pending.get(pendingKey(row.id, name));
      const isOpen = openCell === pendingKey(row.id, name);
      // Available 的 pending 同時預覽 On hand（實測：兩欄一起顯示 9 → 10）
      const availableStaged = pending.get(pendingKey(row.id, "available"));
      const onHandStaged = pending.get(pendingKey(row.id, "on_hand"));
      const mirrored = name === "on_hand" ? availableStaged : onHandStaged;
      const delta = mirrored ? mirrored.projected - mirrored.compareAgainst : 0;
      const preview = staged ? staged.projected : mirrored ? value + delta : null;

      if (isOpen) {
        return (
          <InventoryAdjustPopover
            current={value}
            locationName={locationName}
            name={name}
            onCancel={() => setOpenCell(null)}
            onStage={(next) => stage(row.id, next)}
            reasons={ADJUSTMENT_REASONS_MANUAL_UI}
          />
        );
      }
      return (
        <button
          className="cl-inventory-qty"
          onClick={() => setOpenCell(pendingKey(row.id, name))}
          type="button"
        >
          {preview === null ? (
            <span>{value}</span>
          ) : (
            <span className="cl-inventory-qty__pending">
              {value} → <strong>{preview}</strong>
            </span>
          )}
        </button>
      );
    },
    [locationName, openCell, pending, stage],
  );

  const columns = useMemo<readonly IndexTableColumn<InventoryRow>[]>(
    () => [
      {
        key: "product",
        header: t("inventory.col.product"),
        render: (row) => (
          <span className="cl-product-title">
            {row.productTitle}
            <small>{row.variantTitle}</small>
          </span>
        ),
      },
      { key: "sku", header: t("inventory.col.sku"), render: (row) => row.sku || "—" },
      {
        align: "right",
        key: "unavailable",
        header: t("inventory.col.unavailable"),
        render: (row) => row.quantities.unavailable,
      },
      {
        align: "right",
        key: "committed",
        header: t("inventory.col.committed"),
        render: (row) => row.quantities.committed,
      },
      {
        align: "right",
        key: "available",
        header: t("inventory.col.available"),
        render: (row) =>
          row.tracked ? quantityCell(row, "available", row.quantities.available) : t("inventory.untracked"),
      },
      {
        align: "right",
        key: "onHand",
        header: t("inventory.col.onHand"),
        render: (row) =>
          row.tracked ? quantityCell(row, "on_hand", row.quantities.onHand) : t("inventory.untracked"),
      },
      {
        align: "right",
        key: "incoming",
        header: t("inventory.col.incoming"),
        render: (row) => row.quantities.incoming,
      },
      {
        key: "history",
        header: t("inventory.col.history"),
        render: (row) => (
          <Button
            onClick={() => navigate(`/admin/inventory/${encodeURIComponent(row.id)}/history`)}
            size="small"
            variant="ghost"
          >
            {t("inventory.viewHistory")}
          </Button>
        ),
      },
    ],
    [navigate, quantityCell, t],
  );

  const actions = (
    <>
      {/* D43：CSV 匯入匯出明文延後 ⇒ disabled 而不是可按卻沒反應 */}
      <Button disabled size="small" title={t("inventory.csvDeferred")} variant="ghost">
        <Download aria-hidden="true" size={14} />
        {t("inventory.export")}
      </Button>
      <Button disabled size="small" title={t("inventory.csvDeferred")} variant="ghost">
        <Upload aria-hidden="true" size={14} />
        {t("inventory.import")}
      </Button>
    </>
  );

  const hasFilter = debouncedQuery.length > 0;

  return (
    <Page actions={actions} title={t("inventory.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("inventory.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={reload} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : rows === null ? (
        <Card aria-label={t("inventory.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">
            {t("inventory.loading")}
          </span>
          {Array.from({ length: 5 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : rows.length === 0 && !hasFilter ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={
              <Button onClick={() => navigate("/admin/products/new")} variant="primary">
                {t("inventory.empty.action")}
              </Button>
            }
            description={t("inventory.empty.description")}
            illustration={<Search size={30} strokeWidth={1.7} />}
            title={t("inventory.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <div className="cl-listbar">
            <span className="cl-view-chip">{t("inventory.view.all")}</span>
            <div className="cl-product-search">
              <Search aria-hidden="true" size={14} />
              <TextField
                label={t("inventory.search.label")}
                labelHidden
                onChange={(event) => setSearchValue(event.currentTarget.value)}
                placeholder={t("inventory.search.placeholder")}
                type="search"
                value={searchValue}
              />
            </div>
            <label className="cl-status-filter">
              <span className="cl-sr-only">{t("inventory.location")}</span>
              <select
                aria-label={t("inventory.location")}
                onChange={(event) => setLocationId(event.currentTarget.value)}
                value={locationId}
              >
                {locations.map((location) => (
                  <option key={location.id} value={location.id}>
                    {location.name}
                  </option>
                ))}
              </select>
            </label>
          </div>
          {rows.length > 0 ? (
            <IndexTable
              caption={t("inventory.caption")}
              columns={columns}
              getRowKey={(row) => row.id}
              getRowLabel={(row) => row.productTitle}
              rows={rows}
            />
          ) : (
            <EmptyState
              action={
                <Button onClick={() => setSearchValue("")} size="small">
                  {t("inventory.clearSearch")}
                </Button>
              }
              description={t("inventory.noMatch.description")}
              illustration={<Search size={28} strokeWidth={1.7} />}
              title={t("inventory.noMatch.title")}
            />
          )}
        </Card>
      )}
    </Page>
  );
}
