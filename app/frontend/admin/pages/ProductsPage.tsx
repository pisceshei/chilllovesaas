import { PackagePlus, Plus, RefreshCw, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { BadgeProgress, BadgeTone } from "../components/Badge";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";

const PRODUCTS_QUERY = `
  query ProductsIndex($first: Int!) {
    products(first: $first) {
      nodes {
        id
        title
        status
      }
      pageInfo {
        hasNextPage
        endCursor
      }
    }
  }
`;

/** 商品列表 GraphQL node。 */
export interface ProductNode {
  id: string;
  title: string;
  status: "ACTIVE" | "DRAFT" | "ARCHIVED" | "UNLISTED" | string;
  totalInventory?: number | null;
  productType?: string | null;
  vendor?: string | null;
}

interface ProductsQueryData {
  products: {
    nodes: ProductNode[];
    pageInfo: {
      hasNextPage: boolean;
      endCursor: string | null;
    };
  };
}

interface StatusPresentation {
  label: string;
  progress: BadgeProgress;
  tone: BadgeTone;
}

const statusPresentation: Record<string, StatusPresentation> = {
  ACTIVE: { label: "使用中", progress: "full", tone: "success" },
  ARCHIVED: { label: "已封存", progress: "full", tone: "default" },
  DRAFT: { label: "草稿", progress: "empty", tone: "info" },
  UNLISTED: { label: "未列出", progress: "half", tone: "attention" },
};

/**
 * 取得商品列表，固定透過 docs/research/28 §0.1 的 Admin GraphQL POST。
 *
 * @param signal - 頁面卸載時中止網路請求。
 * @returns 首頁最多 50 筆商品及 cursor pageInfo。
 */
export async function fetchProducts(signal?: AbortSignal): Promise<ProductsQueryData> {
  return requestAdminGraphQL<ProductsQueryData, { first: number }>(
    PRODUCTS_QUERY,
    { first: 50 },
    signal,
  );
}

/**
 * 呈現商品 Index 頁面的 loading/error/empty/data 四態。
 *
 * @remarks
 * 三態要求來自 `docs/design/23-interaction-css-spec.md` §4；商品欄位與操作對照
 * `docs/research/22-admin-button-inventory.md` §2。
 *
 * @returns M0 驗收使用的商品頁。
 */
export function ProductsPage() {
  const navigate = useNavigate();
  const [products, setProducts] = useState<ProductNode[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);
  const [searchValue, setSearchValue] = useState("");

  useEffect(() => {
    const controller = new AbortController();
    setProducts(null);
    setError(null);

    void fetchProducts(controller.signal)
      .then((data) => setProducts(data.products.nodes))
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : "無法載入商品，請稍後再試。");
      });

    return () => controller.abort();
  }, [requestKey]);

  const retry = useCallback(() => setRequestKey((key) => key + 1), []);
  const filteredProducts = useMemo(() => {
    const normalizedQuery = searchValue.trim().toLocaleLowerCase();
    if (!normalizedQuery || !products) return products ?? [];
    return products.filter((product) =>
      [product.title, product.vendor, product.productType]
        .filter(Boolean)
        .some((value) => value?.toLocaleLowerCase().includes(normalizedQuery)),
    );
  }, [products, searchValue]);

  const columns = useMemo<readonly IndexTableColumn<ProductNode>[]>(
    () => [
      {
        key: "title",
        header: "商品",
        render: (product) => <span className="cl-product-title">{product.title}</span>,
      },
      {
        key: "status",
        header: "狀態",
        render: (product) => {
          const presentation = statusPresentation[product.status.toLocaleUpperCase()] ?? {
            label: product.status,
            progress: "empty" as const,
            tone: "default" as const,
          };
          return (
            <Badge progress={presentation.progress} tone={presentation.tone}>
              {presentation.label}
            </Badge>
          );
        },
      },
      {
        align: "right",
        key: "inventory",
        header: "庫存",
        render: (product) =>
          typeof product.totalInventory === "number"
            ? `${product.totalInventory.toLocaleString("zh-TW")} 件`
            : "未追蹤",
      },
      {
        key: "type",
        header: "類型",
        render: (product) => product.productType || "—",
      },
      {
        key: "vendor",
        header: "供應商",
        render: (product) => product.vendor || "—",
      },
    ],
    [],
  );

  const actions = (
    <>
      <Button size="small" variant="ghost">
        匯出
      </Button>
      <Button size="small" variant="ghost">
        匯入
      </Button>
      <Button onClick={() => navigate("/admin/products/new")} variant="primary">
        <Plus aria-hidden="true" size={15} />
        新增商品
      </Button>
    </>
  );

  return (
    <Page actions={actions} title="商品">
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>商品載入失敗</strong>
            <p>{error}</p>
          </div>
          <Button onClick={retry} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            再試一次
          </Button>
        </div>
      ) : products === null ? (
        <Card aria-label="正在載入商品" className="cl-products-loading">
          <span className="cl-sr-only" role="status">
            正在載入商品
          </span>
          {Array.from({ length: 5 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : products.length === 0 ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={
              <Button onClick={() => navigate("/admin/products/new")} variant="primary">
                <Plus aria-hidden="true" size={15} />
                新增商品
              </Button>
            }
            description="建立第一項商品，開始整理你的商店目錄。"
            illustration={<PackagePlus size={30} strokeWidth={1.7} />}
            title="還沒有商品"
          />
        </Card>
      ) : (
        <Card>
          <div className="cl-listbar">
            <span className="cl-view-chip">全部</span>
            <div className="cl-product-search">
              <Search aria-hidden="true" size={14} />
              <TextField
                label="搜尋商品"
                labelHidden
                onChange={(event) => setSearchValue(event.currentTarget.value)}
                placeholder="搜尋商品、類型或供應商…"
                type="search"
                value={searchValue}
              />
            </div>
          </div>
          {filteredProducts.length > 0 ? (
            <IndexTable
              caption="商品列表"
              columns={columns}
              getRowKey={(product) => product.id}
              getRowLabel={(product) => product.title}
              onRowActivate={(product) => navigate(`/admin/products/${encodeURIComponent(product.id)}`)}
              rows={filteredProducts}
            />
          ) : (
            <EmptyState
              action={
                <Button onClick={() => setSearchValue("")} size="small">
                  清除搜尋
                </Button>
              }
              description="請調整搜尋字詞後再試一次。"
              illustration={<Search size={28} strokeWidth={1.7} />}
              title="找不到符合的商品"
            />
          )}
        </Card>
      )}
    </Page>
  );
}
