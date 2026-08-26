import { FolderPlus, Plus, RefreshCw } from "lucide-react";
import { useCallback } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { LoadMore } from "../components/LoadMore";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useCursorPagination } from "../lib/useCursorPagination";

/**
 * 商品系列列表（ML-3）。與商品列表同一套 keyset 分頁與 IndexTable。
 *
 * 🔴 智慧系列的商品數：引擎（第 11 包）落地後由物化表計數；**尚未成功 rebuild**
 *    （rebuildStatus ≠ OK）時後端回 null、這裡顯示 `—`——「未求值」不是 0，
 * 顯示 0 是在說一件假的事（13 §F4；同 91 §5「未知與零是兩件事」）。
 */
const COLLECTIONS_QUERY = `
  query collectionsList($first: Int!, $after: String) {
    collections(first: $first, after: $after) {
      nodes { id title handle collectionType productsCount visibleProductsCount }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

interface CollectionNode {
  id: string;
  title: string;
  handle: string;
  collectionType: string;
  productsCount: number | null;
  /**
   * 前台可見件數（第 12 包）。判準是 **discoverable** 不是 purchasable——
   * 本尊官方：「An unlisted product doesn't display in Shopify-powered collection pages」
   * ⇒ Unlisted 商品可購買但不出現在系列頁。
   * null＝不知道（沒有 online_store 管道／智慧系列尚未 rebuild），**不是 0**。
   */
  visibleProductsCount: number | null;
}

interface CollectionsData {
  collections: { nodes: CollectionNode[]; pageInfo: { hasNextPage: boolean; endCursor: string | null } };
}

export function CollectionsPage() {
  const t = useT();
  const navigate = useNavigate();

  // D48：列表可翻頁（本尊如此；我方原本只取第一頁）。
  const fetchPage = useCallback(
    (cursor: string | null, signal: AbortSignal) =>
      requestAdminGraphQL<CollectionsData, { first: number; after: string | null }>(
        COLLECTIONS_QUERY, { first: DEFAULT_PAGE_SIZE, after: cursor }, signal,
      ).then((data) => data.collections),
    [],
  );
  const {
    items: collections, error, loadMoreError, hasNextPage, loadingMore, loadMore, reload: retry,
  } = useCursorPagination(fetchPage, [], t("collections.loadError"));

  const columns: readonly IndexTableColumn<CollectionNode>[] = [
    {
      key: "title",
      header: t("collections.col.title"),
      render: (row) => <span className="cl-product-title">{row.title}</span>,
    },
    {
      key: "type",
      header: t("collections.col.type"),
      render: (row) => (
        <Badge progress={row.collectionType === "smart" ? "half" : "full"} tone={row.collectionType === "smart" ? "info" : "default"}>
          {row.collectionType === "smart" ? t("collections.type.smart") : t("collections.type.manual")}
        </Badge>
      ),
    },
    {
      align: "right",
      key: "products",
      header: t("collections.col.products"),
      // 🔴 智慧系列尚未成功 rebuild ＝未知，不是 0。
      //
      // 第 12 包：同一格再顯示「（前台可見 M）」——計畫表第 12 列逐字的可見交付
      // 「系列列表出現『後台 N 件（前台可見 M 件）』兩個數字」。
      // 🔴 兩個數字放同一格而不是兩欄：它們是**同一個成員集合的兩個口徑**，
      //    分欄會讓人以為是兩組不同的東西（本尊的商品列表也把 Channels 做成單一格）。
      render: (row) => {
        if (row.productsCount === null) return "—";
        const total = t("collections.count", { count: row.productsCount });
        if (row.visibleProductsCount === null) return total;
        return (
          <>
            {total}
            <span className="cl-collections-visible">
              {t("collections.visibleCount", { count: row.visibleProductsCount })}
            </span>
          </>
        );
      },
    },
    { key: "handle", header: t("collections.col.handle"), render: (row) => row.handle },
  ];

  const actions = (
    <Button onClick={() => navigate("/admin/collections/new")} variant="primary">
      <Plus aria-hidden="true" size={15} />
      {t("collections.add")}
    </Button>
  );

  return (
    <Page actions={actions} title={t("collections.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("collections.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={retry} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : collections === null ? (
        <Card aria-label={t("collections.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">
            {t("collections.loading")}
          </span>
          {Array.from({ length: 4 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : collections.length === 0 ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={
              <Button onClick={() => navigate("/admin/collections/new")} variant="primary">
                <Plus aria-hidden="true" size={15} />
                {t("collections.add")}
              </Button>
            }
            description={t("collections.empty.description")}
            illustration={<FolderPlus size={30} strokeWidth={1.7} />}
            title={t("collections.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <IndexTable
            caption={t("collections.caption")}
            columns={columns}
            getRowKey={(row) => row.id}
            getRowLabel={(row) => row.title}
            onRowActivate={(row) => navigate(`/admin/collections/${encodeURIComponent(row.id)}`)}
            rows={collections}
          />
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
