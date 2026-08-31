import { RefreshCw, Search, UserPlus } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Badge } from "../components/Badge";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Button } from "../components/Button";
import { LoadMore } from "../components/LoadMore";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useCursorPagination } from "../lib/useCursorPagination";

const CUSTOMERS_QUERY = `
  query CustomersIndex($first: Int!, $after: String, $query: String) {
    customers(first: $first, after: $after, query: $query) {
      nodes {
        id
        displayName
        email
        emailMarketingConsent
        ordersCount
        amountSpent { amount currencyCode }
        lastOrderAt
        defaultAddress { city province countryCode }
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`;

/** 顧客列表 GraphQL node（G6-7；欄位面＝74 §1 預設五欄所需）。 */
export interface CustomerNode {
  id: string;
  displayName: string;
  email: string | null;
  emailMarketingConsent: boolean;
  ordersCount: number;
  /** 消費總額（鐵律 3：API 面是 MoneyV2，不是裸 cents）。 */
  amountSpent: { amount: string; currencyCode: string };
  lastOrderAt: string | null;
  defaultAddress: { city: string; province: string | null; countryCode: string } | null;
}

interface CustomersQueryData {
  customers: {
    nodes: CustomerNode[];
    pageInfo: { hasNextPage: boolean; endCursor: string | null };
  };
}

/**
 * 取得顧客列表（28 §0.1 Admin GraphQL POST；cursor 分頁）。
 *
 * @param signal - 頁面卸載時中止網路請求。
 * @returns 一頁顧客與 pageInfo。
 */
export async function fetchCustomers(
  signal?: AbortSignal,
  query?: string,
  after: string | null = null,
): Promise<CustomersQueryData> {
  return requestAdminGraphQL<CustomersQueryData, { first: number; after: string | null; query: string | null }>(
    CUSTOMERS_QUERY,
    { first: DEFAULT_PAGE_SIZE, after, query: query?.trim() ? query.trim() : null },
    signal,
  );
}

/** 金額顯示：MoneyV2 → 幣別符號＋千分位（HKD/USD 用 $；tabular-nums 由表格欄位類承擔）。 */
function formatAmount(money: { amount: string; currencyCode: string }): string {
  const symbols: Record<string, string> = {
    HKD: "$", USD: "$", AUD: "$", CAD: "$", SGD: "$", TWD: "$",
    EUR: "€", GBP: "£", JPY: "¥", CNY: "¥", KRW: "₩",
  };
  const symbol = symbols[money.currencyCode] ?? `${money.currencyCode} `;
  const [whole, fraction] = money.amount.split(".");
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return `${symbol}${grouped}${fraction ? `.${fraction}` : ""}`;
}

/**
 * 顧客列表頁（G6-7；74 §1 預設五欄：名稱／email 訂閱／地點／訂單／消費金額）。
 *
 * @remarks
 * - 資料源＝`customers` query（鐵律 7：訂單數與消費額直讀 rollup 快取欄，
 *   與詳情 KPI、報表同源）。
 * - 搜尋在伺服器（Customers::SearchScope：姓名/email/電話 CONTAINS）。
 * - 三態要求（23 §4）：loading 骨架／error banner＋retry／空態二形。
 * - 欄位選擇器（18 欄）、排序鍵 7×2、分群、匯入匯出＝顧客模組全量包（74 §1）。
 */
export function CustomersPage() {
  const t = useT();
  const [searchValue, setSearchValue] = useState("");

  const [debouncedQuery, setDebouncedQuery] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(searchValue.trim()), 300);
    return () => clearTimeout(timer);
  }, [searchValue]);

  const fetchPage = useCallback(
    (cursor: string | null, signal: AbortSignal) =>
      fetchCustomers(signal, debouncedQuery, cursor).then((data) => data.customers),
    [debouncedQuery],
  );
  const {
    items: customers, error, loadMoreError, hasNextPage, loadingMore, loadMore, reload: retry,
  } = useCursorPagination(fetchPage, [ debouncedQuery ], t("customers.loadError"));
  const searching = debouncedQuery.length > 0;

  const columns = useMemo<IndexTableColumn<CustomerNode>[]>(() => [
    {
      key: "name",
      header: t("customers.column.name"),
      render: (row) => (
        <div>
          <strong>{row.displayName}</strong>
          {row.email && row.displayName !== row.email ? (
            <div className="cl-muted">{row.email}</div>
          ) : null}
        </div>
      ),
    },
    {
      key: "subscription",
      header: t("customers.column.emailSubscription"),
      render: (row) => (
        <Badge tone={row.emailMarketingConsent ? "success" : "default"}>
          {t(row.emailMarketingConsent ? "customers.subscription.subscribed" : "customers.subscription.notSubscribed")}
        </Badge>
      ),
    },
    {
      key: "location",
      header: t("customers.column.location"),
      render: (row) =>
        row.defaultAddress
          ? [ row.defaultAddress.city, row.defaultAddress.province, row.defaultAddress.countryCode ]
              .filter(Boolean)
              .join(", ")
          : "—",
    },
    {
      key: "orders",
      header: t("customers.column.orders"),
      align: "right",
      render: (row) => String(row.ordersCount),
    },
    {
      key: "amountSpent",
      header: t("customers.column.amountSpent"),
      align: "right",
      render: (row) => formatAmount(row.amountSpent),
    },
  ], [ t ]);

  return (
    <Page title={t("customers.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("customers.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={retry} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : customers === null ? (
        <Card aria-label={t("customers.loading")}>
          <span className="cl-sr-only" role="status">
            {t("customers.loading")}
          </span>
          {Array.from({ length: 5 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : customers.length === 0 && !searching ? (
        <Card>
          <EmptyState
            description={t("customers.empty.description")}
            illustration={<UserPlus size={30} strokeWidth={1.7} />}
            title={t("customers.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <div className="cl-listbar">
            <span className="cl-view-chip">{t("customers.view.all")}</span>
            <div className="cl-product-search">
              <Search aria-hidden="true" size={14} />
              <TextField
                label={t("customers.search.label")}
                labelHidden
                onChange={(event) => setSearchValue(event.currentTarget.value)}
                placeholder={t("customers.search.placeholder")}
                type="search"
                value={searchValue}
              />
            </div>
          </div>
          {customers.length > 0 ? (
            <IndexTable
              caption={t("customers.title")}
              columns={columns}
              getRowKey={(row) => row.id}
              getRowLabel={(row) => row.displayName}
              rows={customers}
            />
          ) : (
            <EmptyState
              description={t("customers.noMatch.description")}
              illustration={<Search size={28} strokeWidth={1.7} />}
              title={t("customers.noMatch.title")}
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
