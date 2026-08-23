import { FolderPlus, Plus, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";

/**
 * 商品系列列表（ML-3）。與商品列表同一套 keyset 分頁與 IndexTable。
 *
 * 🔴 智慧系列的商品數顯示 `—` 而不是 0：規則引擎落地前我方**不知道**成員數，
 * 顯示 0 是在說一件假的事（13 §F4；同 91 §5「未知與零是兩件事」）。
 */
const COLLECTIONS_QUERY = `
  query collectionsList($first: Int!) {
    collections(first: $first) {
      nodes { id title handle collectionType productsCount }
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
}

interface CollectionsData {
  collections: { nodes: CollectionNode[]; pageInfo: { hasNextPage: boolean; endCursor: string | null } };
}

export function CollectionsPage() {
  const t = useT();
  const navigate = useNavigate();
  const [collections, setCollections] = useState<CollectionNode[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);

  useEffect(() => {
    const controller = new AbortController();
    setCollections(null);
    setError(null);
    requestAdminGraphQL<CollectionsData, { first: number }>(
      COLLECTIONS_QUERY,
      { first: DEFAULT_PAGE_SIZE },
      controller.signal,
    )
      .then((data) => setCollections(data.collections.nodes))
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("collections.loadError"));
      });
    return () => controller.abort();
  }, [requestKey, t]);

  const retry = useCallback(() => setRequestKey((key) => key + 1), []);

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
      // 🔴 智慧系列＝未知（規則引擎未落地），不是 0。
      render: (row) => (row.productsCount === null ? "—" : t("collections.count", { count: row.productsCount })),
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
    </Page>
  );
}
