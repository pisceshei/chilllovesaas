import { useEffect, useMemo, useState } from "react";
import { useNavigate, useParams, useSearchParams } from "react-router-dom";
import { ArrowLeft, ClipboardList, RefreshCw } from "lucide-react";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { ACTIVITY_KEY_PREFIX, ADJUSTMENT_HISTORY_RETENTION_DAYS } from "../lib/inventoryLimits";

/**
 * 調整記錄頁 `/admin/inventory/:itemId/history`（排程第 18 包 C 塊）。
 *
 * ①這是什麼：某 (品項, 地點) 的 ledger 歷程，一列＝一次調整（實測 `docs/research/94` §2.5）。
 * ②欄集（實測 7 欄）：Date｜Activity｜Created by｜Unavailable｜Committed｜Available｜On hand。
 *   🔴 **Incoming 是條件性欄**：該品項歷程中從未出現 incoming 變動就不顯示
 *   （help 列 8 欄、實測 7 欄，差異即在此——總裁定 §四b 第 4 點的方向）。
 * ③怎麼做：儲存格格式「(+1) 10」＝delta ＋ quantityAfterChange（實測是「increased by 1
 *   for a total of 10」的緊湊版）。無變動的欄留白——顯示 0 會讓人以為「這次調成 0」。
 *   Activity 標籤由 reason 識別字對照 i18n（後端回識別字，翻譯權在前端）。
 * ④跨功能影響：期後值來自後端 window running sum（第八式）——**前端不自行累加**；
 *   參考文件（referenceDocumentUri／ledgerDocumentUri）在同列展開顯示，
 *   對應本尊 Activity 儲存格的 popover（實測連手動調整都掛 TransferAdjustment gid）。
 */
interface HistoryChange {
  readonly name: string;
  readonly delta: number;
  readonly quantityAfterChange: number;
}

interface HistoryRow {
  readonly id: string;
  readonly createdAt: string;
  readonly reason: string;
  readonly mutationKind: string;
  readonly createdBy: string | null;
  readonly referenceDocumentUri: string | null;
  readonly ledgerDocumentUri: string | null;
  readonly changes: HistoryChange[];
}

interface HistoryQueryData {
  readonly inventoryHistory: HistoryRow[];
}

const HISTORY_QUERY = `
  query InventoryHistory($itemId: ID!, $locationId: ID) {
    inventoryHistory(inventoryItemId: $itemId, locationId: $locationId) {
      id
      createdAt
      reason
      mutationKind
      createdBy
      referenceDocumentUri
      ledgerDocumentUri
      changes { name delta quantityAfterChange }
    }
  }
`;

/** 顯示欄序＝實測欄序（94 §2.5）。 */
const QUANTITY_COLUMNS = [ "unavailable", "committed", "available", "on_hand" ] as const;

export function InventoryHistoryPage() {
  const navigate = useNavigate();
  const params = useParams<{ itemId: string }>();
  // 🔴 歷程是 (品項, **地點**) 的帳，不是品項的帳。
  // 不帶 locationId 時後端退回 priority 序第一個地點——單一地點的店看不出來，
  // 多地點的店會看到「別的倉庫」的歷程，而且畫面上沒有任何線索說它換了地點。
  const [searchParams] = useSearchParams();
  const t = useT();
  const [rows, setRows] = useState<HistoryRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);

  const itemId = decodeURIComponent(params.itemId ?? "");
  const locationId = searchParams.get("locationId");

  useEffect(() => {
    const controller = new AbortController();
    setError(null);
    void requestAdminGraphQL<HistoryQueryData, { itemId: string; locationId: string | null }>(
      HISTORY_QUERY,
      { itemId, locationId },
      controller.signal,
    )
      .then((data) => setRows(data.inventoryHistory))
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("inventory.history.loadError"));
      });
    return () => controller.abort();
  }, [itemId, locationId, requestKey, t]);

  // Incoming 條件性欄：整份歷程都沒有 incoming 變動就不顯示（實測 7 欄的成因）。
  const showIncoming = useMemo(
    () => (rows ?? []).some((row) => row.changes.some((change) => change.name === "incoming")),
    [rows],
  );

  const quantityColumns = useMemo(
    () => (showIncoming ? [ ...QUANTITY_COLUMNS, "incoming" as const ] : QUANTITY_COLUMNS),
    [showIncoming],
  );

  const columns = useMemo<readonly IndexTableColumn<HistoryRow>[]>(
    () => [
      {
        key: "date",
        header: t("inventory.history.col.date"),
        render: (row) => new Date(row.createdAt).toLocaleString(),
      },
      {
        key: "activity",
        header: t("inventory.history.col.activity"),
        render: (row) => (
          <span className="cl-history-activity">
            {t(`${ACTIVITY_KEY_PREFIX}${row.reason}`)}
            {(row.referenceDocumentUri ?? row.ledgerDocumentUri) ? (
              <small className="cl-history-activity__doc">
                {row.referenceDocumentUri ?? row.ledgerDocumentUri}
              </small>
            ) : null}
          </span>
        ),
      },
      {
        key: "createdBy",
        header: t("inventory.history.col.createdBy"),
        render: (row) => row.createdBy ?? "—",
      },
      ...quantityColumns.map((name) => ({
        align: "right" as const,
        key: name,
        header: t(`inventory.col.${name === "on_hand" ? "onHand" : name}`),
        render: (row: HistoryRow) => {
          const change = row.changes.find((entry) => entry.name === name);
          // 無變動留白：顯示 0 會被讀成「這次把它調成 0」
          if (!change) return "";
          const sign = change.delta > 0 ? "+" : "";
          return (
            <span className="cl-history-delta">
              <small>
                ({sign}
                {change.delta})
              </small>{" "}
              {change.quantityAfterChange}
            </span>
          );
        },
      })),
    ],
    [quantityColumns, t],
  );

  const actions = (
    <Button onClick={() => navigate("/admin/inventory")} size="small" variant="ghost">
      <ArrowLeft aria-hidden="true" size={14} />
      {t("inventory.history.back")}
    </Button>
  );

  return (
    <Page actions={actions} title={t("inventory.history.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("inventory.history.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={() => setRequestKey((key) => key + 1)} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : rows === null ? (
        <Card aria-label={t("inventory.history.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">
            {t("inventory.history.loading")}
          </span>
          {Array.from({ length: 4 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : rows.length === 0 ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={
              <Button onClick={() => navigate("/admin/inventory")} size="small">
                {t("inventory.history.back")}
              </Button>
            }
            description={t("inventory.history.empty.description")}
            illustration={<ClipboardList size={30} strokeWidth={1.7} />}
            title={t("inventory.history.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <p className="cl-history-note">{t("inventory.history.retentionNote", { days: ADJUSTMENT_HISTORY_RETENTION_DAYS })}</p>
          <IndexTable
            caption={t("inventory.history.caption")}
            columns={columns}
            getRowKey={(row) => row.id}
            getRowLabel={(row) => t(`${ACTIVITY_KEY_PREFIX}${row.reason}`)}
            rows={rows}
          />
        </Card>
      )}
    </Page>
  );
}
