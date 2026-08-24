import { PackagePlus, Plus, RefreshCw, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { BadgeProgress, BadgeTone } from "../components/Badge";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT, useUiLocale } from "../i18n/I18nContext";

const PRODUCTS_QUERY = `
  query ProductsIndex($first: Int!, $query: String) {
    products(first: $first, query: $query) {
      nodes {
        id
        title
        status
        vendor
        productType
        totalInventory
        mediaMissingAltCount
        featuredImage { thumbUrl status alt }
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
  /** 缺 alt 的媒體數（62 §F.1：不自動填、只度量）。 */
  mediaMissingAltCount?: number;
  /** 首圖；thumbUrl 為 null＝尚未處理完（不得改用原圖，20MB 原圖當縮圖會炸列表）。 */
  featuredImage?: { thumbUrl: string | null; status: string; alt: string | null } | null;
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
  labelKey: string;
  progress: BadgeProgress;
  tone: BadgeTone;
}

/**
 * 商品狀態的徽章呈現。
 *
 * 🔴 正典表＝原型 `docs/design/chilllove-admin-v2.html` 的 `P_STATUS`（約 3105 行），
 * 每一欄逐項對照，不自創（鐵律 8／12）：
 *
 * | 狀態 | 原型 `bt`（徽章文案） | 原型 `badge` | 原型 `pip` | 本檔 |
 * |---|---|---|---|---|
 * | ACTIVE | 啟用中 | b-success | full | success / full |
 * | UNLISTED | 未列出 | b-caution | `''`（裸圈） | attention / empty |
 * | DRAFT | 草稿 | b-info | `''`（裸圈） | info / empty |
 * | ARCHIVED | 已封存 | b-default | **blocked** | default / full ⚠ |
 *
 * ⚠️ **ARCHIVED 的 pip 尚未對齊，這是刻意留下的登記項不是遺漏**：
 * 原型用 `pip:'blocked'`（透明底＋斜線），而 `docs/design/23-interaction-css-spec.md`
 * §1 的 Badge 規格只定義**三種** pip（空圈=未開始／半圈=進行中／實圈=完成），
 * **沒有 `blocked`**。⇒ 原型與 CSS 規格本身不一致，補第四種 pip 是視覺語言的變更，
 * 不該夾在「加一個商品狀態」的改動裡靜默做掉。登記於 worklog Pending。
 *
 * 🔴 `label` 用「啟用中」不是「使用中」：原型 `bt:'啟用中'`（3106 行）。
 * 「使用中」是本檔原本自創的文案——它讀起來像「正在被某個東西使用」，
 * 而這個欄位講的是商家有沒有把商品**啟用**。
 */
const statusPresentation: Record<string, StatusPresentation> = {
  ACTIVE: { labelKey: "status.active", progress: "full", tone: "success" },
  ARCHIVED: { labelKey: "status.archived", progress: "full", tone: "default" },
  DRAFT: { labelKey: "status.draft", progress: "empty", tone: "info" },
  UNLISTED: { labelKey: "status.unlisted", progress: "empty", tone: "attention" },
};

/**
 * 取得商品列表，固定透過 docs/research/28 §0.1 的 Admin GraphQL POST。
 *
 * @param signal - 頁面卸載時中止網路請求。
 * @returns 首頁一頁商品（預設頁量見 api/pagination.ts）及 cursor pageInfo。
 */
export async function fetchProducts(signal?: AbortSignal, query?: string): Promise<ProductsQueryData> {
  return requestAdminGraphQL<ProductsQueryData, { first: number; query: string | null }>(
    PRODUCTS_QUERY,
    { first: DEFAULT_PAGE_SIZE, query: query?.trim() ? query.trim() : null },
    signal,
  );
}

/**
 * 狀態篩選的值域＝ProductStatusEnum 全集（值域窮舉：**四值**，ARCHIVED 不得省略）。
 * 送往伺服器時組成 `status:<value>` 併入 search query（Products::SearchScope 白名單）。
 */
const STATUS_FILTERS = ["ACTIVE", "DRAFT", "ARCHIVED", "UNLISTED"] as const;

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
  const t = useT();
  const locale = useUiLocale();
  const [products, setProducts] = useState<ProductNode[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);
  const [searchValue, setSearchValue] = useState("");
  const [statusFilter, setStatusFilter] = useState("");

  // 🔴 搜尋在伺服器（排程第 1 包）。舊版對已載入的一頁做記憶體過濾——
  // 第 51 筆之後的關鍵字永遠搜不到，且 vendor/productType 根本沒被選取（恆 undefined）。
  const composedQuery = useMemo(() => {
    const parts = [searchValue.trim()];
    if (statusFilter) parts.push(`status:${statusFilter.toLocaleLowerCase()}`);
    return parts.filter(Boolean).join(" ");
  }, [searchValue, statusFilter]);

  // 300ms 去抖：每個按鍵都打伺服器是浪費，也會讓結果閃爍。
  const [debouncedQuery, setDebouncedQuery] = useState("");
  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(composedQuery), 300);
    return () => clearTimeout(timer);
  }, [composedQuery]);

  useEffect(() => {
    const controller = new AbortController();
    setError(null);

    void fetchProducts(controller.signal, debouncedQuery)
      .then((data) => setProducts(data.products.nodes))
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("products.loadError"));
      });

    return () => controller.abort();
  }, [requestKey, debouncedQuery, t]);

  const retry = useCallback(() => setRequestKey((key) => key + 1), []);
  const hasActiveFilter = composedQuery.length > 0;

  const columns = useMemo<readonly IndexTableColumn<ProductNode>[]>(
    () => [
      {
        key: "thumb",
        header: t("products.col.image"),
        render: (product) => {
          const image = product.featuredImage;
          if (image?.thumbUrl) {
            return (
              <img
                alt={image.alt ?? ""}
                className="cl-product-thumb"
                height={40}
                loading="lazy"
                src={image.thumbUrl}
                width={40}
              />
            );
          }
          // 兩種空態要分開：處理中（有圖但衍生未產出）vs 根本沒圖
          const pending = image != null && image.status !== "READY";
          return (
            <span
              aria-label={pending ? t("products.image.processing") : t("products.image.none")}
              className={pending ? "cl-product-thumb cl-product-thumb--pending" : "cl-product-thumb cl-product-thumb--empty"}
              role="img"
              title={pending ? t("products.image.processing") : t("products.image.none")}
            />
          );
        },
      },
      {
        key: "title",
        header: t("products.col.product"),
        render: (product) => (
          <span className="cl-product-title">
            {product.title}
            {product.mediaMissingAltCount ? (
              <span className="cl-alt-warning" title={t("products.missingAlt.hint")}>
                {t("products.missingAlt", { count: product.mediaMissingAltCount })}
              </span>
            ) : null}
          </span>
        ),
      },
      {
        key: "status",
        header: t("products.col.status"),
        render: (product) => {
          const presentation = statusPresentation[product.status.toLocaleUpperCase()];
          return (
            <Badge progress={presentation?.progress ?? "empty"} tone={presentation?.tone ?? "default"}>
              {presentation ? t(presentation.labelKey) : product.status}
            </Badge>
          );
        },
      },
      {
        align: "right",
        key: "inventory",
        header: t("products.col.inventory"),
        render: (product) =>
          typeof product.totalInventory === "number"
            ? t("products.inventory.units", { count: product.totalInventory })
            : t("products.inventory.untracked"),
      },
      {
        key: "type",
        header: t("products.col.type"),
        render: (product) => product.productType || "—",
      },
      {
        key: "vendor",
        header: t("products.col.vendor"),
        render: (product) => product.vendor || "—",
      },
    ],
    [locale, t],
  );

  const actions = (
    <>
      <Button size="small" variant="ghost">
        {t("products.export")}
      </Button>
      <Button size="small" variant="ghost">
        {t("products.import")}
      </Button>
      <Button onClick={() => navigate("/admin/products/new")} variant="primary">
        <Plus aria-hidden="true" size={15} />
        {t("products.add")}
      </Button>
    </>
  );

  return (
    <Page actions={actions} title={t("products.title")}>
      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("products.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={retry} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : products === null ? (
        <Card aria-label={t("products.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">
            {t("products.loading")}
          </span>
          {Array.from({ length: 5 }, (_, index) => (
            <span className="cl-skeleton" key={index} />
          ))}
        </Card>
      ) : products.length === 0 && !hasActiveFilter ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={
              <Button onClick={() => navigate("/admin/products/new")} variant="primary">
                <Plus aria-hidden="true" size={15} />
                {t("products.add")}
              </Button>
            }
            description={t("products.empty.description")}
            illustration={<PackagePlus size={30} strokeWidth={1.7} />}
            title={t("products.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <div className="cl-listbar">
            <span className="cl-view-chip">{t("products.view.all")}</span>
            <div className="cl-product-search">
              <Search aria-hidden="true" size={14} />
              <TextField
                label={t("products.search.label")}
                labelHidden
                onChange={(event) => setSearchValue(event.currentTarget.value)}
                placeholder={t("products.search.placeholder")}
                type="search"
                value={searchValue}
              />
            </div>
            <label className="cl-status-filter">
              <span className="cl-sr-only">{t("products.filter.statusLabel")}</span>
              <select
                aria-label={t("products.filter.statusLabel")}
                onChange={(event) => setStatusFilter(event.currentTarget.value)}
                value={statusFilter}
              >
                <option value="">{t("products.filter.statusAll")}</option>
                {STATUS_FILTERS.map((status) => (
                  <option key={status} value={status}>
                    {t(statusPresentation[status].labelKey)}
                  </option>
                ))}
              </select>
            </label>
          </div>
          {products.length > 0 ? (
            <IndexTable
              caption={t("products.caption")}
              columns={columns}
              getRowKey={(product) => product.id}
              getRowLabel={(product) => product.title}
              onRowActivate={(product) => navigate(`/admin/products/${encodeURIComponent(product.id)}`)}
              rows={products}
            />
          ) : (
            <EmptyState
              action={
                <Button
                  onClick={() => {
                    setSearchValue("");
                    setStatusFilter("");
                  }}
                  size="small"
                >
                  {t("products.clearSearch")}
                </Button>
              }
              description={t("products.noMatch.description")}
              illustration={<Search size={28} strokeWidth={1.7} />}
              title={t("products.noMatch.title")}
            />
          )}
        </Card>
      )}
    </Page>
  );
}
