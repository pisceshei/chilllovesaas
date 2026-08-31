import { RefreshCw, Search, ShoppingCart } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Badge } from "../components/Badge";
import type { BadgeTone } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { LoadMore } from "../components/LoadMore";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useCursorPagination } from "../lib/useCursorPagination";

const ORDERS_QUERY = `
  query OrdersIndex($first: Int!, $after: String, $query: String) {
    orders(first: $first, after: $after, query: $query) {
      nodes {
        id
        name
        processedAt
        displayFinancialStatus
        displayFulfillmentStatus
        itemCount
        totalPriceSet { shopMoney { amount currencyCode } }
        customer { displayName }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`;

/** 訂單列表 GraphQL node（G6-6 步 4；欄位面＝88 §2 預設欄中資料已備者）。 */
export interface OrderNode {
  id: string;
  name: string;
  processedAt: string | null;
  displayFinancialStatus: string;
  displayFulfillmentStatus: string;
  itemCount: number;
  totalPriceSet: { shopMoney: { amount: string; currencyCode: string } };
  customer: { displayName: string } | null;
}

interface OrdersQueryData {
  orders: {
    nodes: OrderNode[];
    pageInfo: { hasNextPage: boolean; endCursor: string | null };
  };
}

export async function fetchOrders(
  signal?: AbortSignal,
  query?: string,
  after: string | null = null,
): Promise<OrdersQueryData> {
  return requestAdminGraphQL<OrdersQueryData, { first: number; after: string | null; query: string | null }>(
    ORDERS_QUERY,
    { first: DEFAULT_PAGE_SIZE, after, query: query?.trim() ? query.trim() : null },
    signal,
  );
}

/** 金額顯示（MoneyV2 → 符號＋千分位；與顧客頁同一 helper 形）。 */
export function formatMoney(money: { amount: string; currencyCode: string }): string {
  const symbols: Record<string, string> = {
    HKD: "$", USD: "$", AUD: "$", CAD: "$", SGD: "$", TWD: "$",
    EUR: "€", GBP: "£", JPY: "¥", CNY: "¥", KRW: "₩",
  };
  const symbol = symbols[money.currencyCode] ?? `${money.currencyCode} `;
  const [whole, fraction] = money.amount.split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${symbol}${grouped}${fraction ? `.${fraction}` : ""}`;
}

/** 付款狀態 badge tone（88 §2：Paid=灰、待款類=黃、作廢/逾期=紅、退款類=資訊）。 */
export function financialTone(status: string): BadgeTone {
  switch (status) {
    case "PAID": return "default";
    case "REFUNDED": case "PARTIALLY_REFUNDED": return "info";
    case "VOIDED": case "EXPIRED": return "critical";
    default: return "attention"; // PENDING / AUTHORIZED / PARTIALLY_PAID
  }
}

/** 出貨狀態 badge tone（88 §2：Fulfilled=灰、其餘=黃）。 */
export function fulfillmentTone(status: string): BadgeTone {
  return status === "FULFILLED" ? "default" : "attention";
}

/**
 * 付款狀態篩選值域＝OrderDisplayFinancialStatus 八值（值域窮舉；88 §7）。
 * 送伺服器組成 `financial_status:<value>`（Orders::SearchScope 白名單）。
 */
const FINANCIAL_FILTERS = [
  "PENDING", "AUTHORIZED", "PAID", "PARTIALLY_PAID",
  "PARTIALLY_REFUNDED", "REFUNDED", "VOIDED", "EXPIRED",
] as const;

/** 出貨狀態篩選值域＝v1 三值（enum 同源）。 */
const FULFILLMENT_FILTERS = [ "UNFULFILLED", "PARTIALLY_FULFILLED", "FULFILLED" ] as const;

/**
 * 訂單列表頁（G6-6 步 4；88 §2 預設欄的資料已備子集：單號/日期/顧客/總計/
 * 付款狀態/出貨狀態/商品數；Channel/Delivery status 等欄隨對應資料線）。
 *
 * @remarks
 * - 搜尋在伺服器（單號/email CONTAINS＋status 白名單——Orders::SearchScope）。
 * - 預設序＝processed_at desc（server 端；88 §1 雙證）。
 * - 三態（23 §4）＋cursor 載入更多；欄位選擇器/saved views/bulk＝列表全量包。
 */
export function OrdersPage() {
  const navigate = useNavigate();
  const t = useT();
  const [searchValue, setSearchValue] = useState("");
  const [financialFilter, setFinancialFilter] = useState("");
  const [fulfillmentFilter, setFulfillmentFilter] = useState("");

  const composedQuery = useMemo(() => {
    const parts = [searchValue.trim()];
    if (financialFilter) parts.push(`financial_status:${financialFilter.toLocaleLowerCase()}`);
    if (fulfillmentFilter) parts.push(`fulfillment_status:${fulfillmentFilter.toLocaleLowerCase()}`);
    return parts.filter(Boolean).join(" ");
  }, [searchValue, financialFilter, fulfillmentFilter]);

  const [debouncedQuery, setDebouncedQuery] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(composedQuery), 300);
    return () => clearTimeout(timer);
  }, [composedQuery]);

  const fetchPage = useCallback(
    (cursor: string | null, signal: AbortSignal) =>
      fetchOrders(signal, debouncedQuery, cursor).then((data) => data.orders),
    [debouncedQuery],
  );
  const {
    items: orders, error, loadMoreError, hasNextPage, loadingMore, loadMore, reload: retry,
  } = useCursorPagination(fetchPage, [ debouncedQuery ], t("orders.loadError"));
  const hasActiveFilter = composedQuery.length > 0;

  const columns = useMemo<IndexTableColumn<OrderNode>[]>(() => [
    {
      key: "name",
      header: t("orders.column.order"),
      render: (row) => <strong>{row.name}</strong>,
    },
    {
      key: "date",
      header: t("orders.column.date"),
      render: (row) => (row.processedAt ? new Date(row.processedAt).toLocaleString() : "—"),
    },
    {
      key: "customer",
      header: t("orders.column.customer"),
      render: (row) => row.customer?.displayName ?? t("orders.noCustomer"),
    },
    {
      key: "total",
      header: t("orders.column.total"),
      align: "right",
      render: (row) => formatMoney(row.totalPriceSet.shopMoney),
    },
    {
      key: "financial",
      header: t("orders.column.paymentStatus"),
      render: (row) => (
        <Badge tone={financialTone(row.displayFinancialStatus)}>
          {t(`orders.financial.${row.displayFinancialStatus}`)}
        </Badge>
      ),
    },
    {
      key: "fulfillment",
      header: t("orders.column.fulfillmentStatus"),
      render: (row) => (
        <Badge tone={fulfillmentTone(row.displayFulfillmentStatus)}>
          {t(`orders.fulfillment.${row.displayFulfillmentStatus}`)}
        </Badge>
      ),
    },
    {
      key: "items",
      header: t("orders.column.items"),
      align: "right",
      render: (row) => t("orders.itemCount", { count: row.itemCount }),
    },
  ], [ t ]);

  return (
    <Page title={t("orders.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("orders.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={retry} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : orders === null ? (
        <Card aria-label={t("orders.loading")}>
          <span className="cl-sr-only" role="status">
            {t("orders.loading")}
          </span>
          {Array.from({ length: 5 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : orders.length === 0 && !hasActiveFilter ? (
        <Card>
          <EmptyState
            action={null}
            description={t("orders.empty.description")}
            illustration={<ShoppingCart size={30} strokeWidth={1.7} />}
            title={t("orders.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <div className="cl-listbar">
            <span className="cl-view-chip">{t("orders.view.all")}</span>
            <div className="cl-product-search">
              <Search aria-hidden="true" size={14} />
              <TextField
                label={t("orders.search.label")}
                labelHidden
                onChange={(event) => setSearchValue(event.currentTarget.value)}
                placeholder={t("orders.search.placeholder")}
                type="search"
                value={searchValue}
              />
            </div>
            <label className="cl-status-filter">
              <span className="cl-sr-only">{t("orders.filter.paymentLabel")}</span>
              <select
                aria-label={t("orders.filter.paymentLabel")}
                onChange={(event) => setFinancialFilter(event.currentTarget.value)}
                value={financialFilter}
              >
                <option value="">{t("orders.filter.paymentAll")}</option>
                {FINANCIAL_FILTERS.map((status) => (
                  <option key={status} value={status}>
                    {t(`orders.financial.${status}`)}
                  </option>
                ))}
              </select>
            </label>
            <label className="cl-status-filter">
              <span className="cl-sr-only">{t("orders.filter.fulfillmentLabel")}</span>
              <select
                aria-label={t("orders.filter.fulfillmentLabel")}
                onChange={(event) => setFulfillmentFilter(event.currentTarget.value)}
                value={fulfillmentFilter}
              >
                <option value="">{t("orders.filter.fulfillmentAll")}</option>
                {FULFILLMENT_FILTERS.map((status) => (
                  <option key={status} value={status}>
                    {t(`orders.fulfillment.${status}`)}
                  </option>
                ))}
              </select>
            </label>
          </div>
          {orders.length > 0 ? (
            <IndexTable
              caption={t("orders.title")}
              columns={columns}
              getRowKey={(row) => row.id}
              getRowLabel={(row) => row.name}
              onRowActivate={(row) => {
                const numeric = row.id.split("/").pop();
                navigate(`/admin/orders/${numeric}`);
              }}
              rows={orders}
            />
          ) : (
            <EmptyState
              action={null}
              description={t("orders.noMatch.description")}
              illustration={<Search size={28} strokeWidth={1.7} />}
              title={t("orders.noMatch.title")}
            />
          )}
        </Card>
      )}

      <LoadMore
        error={loadMoreError}
        hasNextPage={hasNextPage}
        loading={loadingMore}
        onLoadMore={loadMore}
      />
    </Page>
  );
}
