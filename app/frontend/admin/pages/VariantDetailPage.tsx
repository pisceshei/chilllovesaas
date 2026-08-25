import { ChevronDown, ChevronUp, RefreshCw, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Breadcrumb } from "../components/Breadcrumb";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { MediaThumb } from "../components/MediaThumb";
import { TextField } from "../components/TextField";
import { VariantImageSlot } from "../components/VariantImageSlot";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { buildVariantsPayload } from "../lib/variantMatrix";
import type { VariantRowData } from "../lib/variantMatrix";
import { centsToApiString, isValidMoneyInput, parseMoneyToCents } from "../lib/money";
import { uuidV4 } from "../lib/uuid";

/**
 * 變體子頁 `/admin/products/:productId/variants/:variantId`（第 29 包）。
 *
 * ①形態來源＝93 §2 的本尊實測：頁首麵包屑（商品名 › S）＋變體間導航；
 *   左欄商品卡→搜尋→變體清單（當前高亮）；主欄變體圖＋選項值／價格／庫存／運送四卡。
 *
 * ②🔴 **儲存必須整份回送**（本頁最容易出事的一條）：`productSet` 是宣告式全量
 *   ——沒列在 `variants` 裡的變體會被**刪掉**，沒送的欄位會回落預設。
 *   所以子頁載入的是**整個商品**（不是單一變體），編輯只改記憶體裡那一列，
 *   送出時走與商品頁**同一支** `buildVariantsPayload`。
 *   自己組 payload 或只送被編的那一列＝把其他變體刪光。
 *
 * ③🔴 **庫存不走 productSet**：庫存調整是 ledger（append-only 稽核帳），
 *   只能經 `inventoryAdjustQuantities`（D43「庫存唯一入口」）。本頁的庫存卡是
 *   **唯讀顯示＋連到調整**，不把數量塞進商品儲存。
 *
 * ④跨功能影響：`MediaThumb`／`FilePickerModal`／`buildVariantsPayload` 三者與
 *   商品頁共用——改它們兩邊都會變。變體圖的掛卸走
 *   `productVariantAppendMedia`（見 `VariantImageSlot` 檔頭）。
 */
const VARIANT_PAGE_QUERY = `
  query variantDetail($id: ID!) {
    product(id: $id) {
      id
      title
      status
      handle
      lockVersion
      featuredImage { thumbUrl status alt }
      options { name position values { value position } }
      variants(first: 250) {
        nodes {
          id title position price compareAtPrice cost sku barcode taxable
          weightGrams requiresShipping
          selectedOptions { name value }
          image { thumbUrl status alt }
          inventoryLevels {
            inventoryItemId
            location { id name }
            quantities { available onHand committed }
          }
        }
      }
    }
  }
`;

const SAVE_MUTATION = `
  mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
    productSet(input: $input, idempotencyKey: $idempotencyKey) {
      product { id lockVersion }
      userErrors { field message code }
    }
  }
`;

interface VariantNode {
  id: string;
  title: string;
  position: number;
  price: string;
  compareAtPrice: string | null;
  cost: string | null;
  sku: string | null;
  barcode: string | null;
  taxable: boolean;
  weightGrams: number;
  requiresShipping: boolean;
  selectedOptions: { name: string; value: string }[];
  image: { thumbUrl: string | null; status: string; alt: string | null } | null;
  inventoryLevels: {
    inventoryItemId: string;
    location: { id: string; name: string };
    quantities: { available: number; onHand: number; committed: number };
  }[];
}

interface ProductNode {
  id: string;
  title: string;
  status: string;
  handle: string;
  lockVersion: number;
  featuredImage: { thumbUrl: string | null; status: string; alt: string | null } | null;
  options: { name: string; position: number; values: { value: string; position: number }[] }[];
  variants: { nodes: VariantNode[] };
}

/** 本頁可編輯的欄位（庫存不在其中——見檔頭③）。 */
interface VariantDraft {
  price: string;
  compare: string;
  cost: string;
  sku: string;
  barcode: string;
  taxable: boolean;
  weightGrams: string;
  requiresShipping: boolean;
  /** 選項名 → 值（本尊的選項值 input 可直接改值）。 */
  coords: Record<string, string>;
}

function draftOf(node: VariantNode): VariantDraft {
  return {
    price: node.price,
    compare: node.compareAtPrice ?? "",
    cost: node.cost ?? "",
    sku: node.sku ?? "",
    barcode: node.barcode ?? "",
    taxable: node.taxable,
    weightGrams: String(node.weightGrams ?? 0),
    requiresShipping: node.requiresShipping,
    coords: Object.fromEntries(node.selectedOptions.map((o) => [ o.name, o.value ])),
  };
}

export function VariantDetailPage() {
  const t = useT();
  const navigate = useNavigate();
  const { showToast } = useToast();
  const params = useParams();
  const productGid = decodeURIComponent(params.productId ?? "");
  const variantGid = decodeURIComponent(params.variantId ?? "");

  const [product, setProduct] = useState<ProductNode | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [requestKey, setRequestKey] = useState(0);
  const [draft, setDraft] = useState<VariantDraft | null>(null);
  const [saving, setSaving] = useState(false);
  const [search, setSearch] = useState("");

  useEffect(() => {
    const controller = new AbortController();
    setProduct(null);
    setError(null);
    requestAdminGraphQL<{ product: ProductNode | null }, { id: string }>(
      VARIANT_PAGE_QUERY, { id: productGid }, controller.signal,
    )
      .then((data) => {
        if (!data.product) {
          setError(t("variant.notFound"));
          return;
        }
        setProduct(data.product);
        const node = data.product.variants.nodes.find((v) => v.id === variantGid);
        setDraft(node ? draftOf(node) : null);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("variant.loadError"));
      });
    return () => controller.abort();
  }, [productGid, variantGid, requestKey, t]);

  const reload = useCallback(() => setRequestKey((key) => key + 1), []);

  const variants = useMemo(
    () => [ ...(product?.variants.nodes ?? []) ].sort((a, b) => a.position - b.position),
    [product],
  );
  const index = variants.findIndex((v) => v.id === variantGid);
  const current = index >= 0 ? variants[index] : null;

  const filtered = useMemo(() => {
    const needle = search.trim().toLocaleLowerCase();
    if (!needle) return variants;
    return variants.filter((v) => v.title.toLocaleLowerCase().includes(needle));
  }, [search, variants]);

  const goTo = useCallback((id: string) => {
    navigate(`/admin/products/${encodeURIComponent(productGid)}/variants/${encodeURIComponent(id)}`);
  }, [navigate, productGid]);

  const setField = useCallback(<K extends keyof VariantDraft>(key: K, value: VariantDraft[K]) => {
    setDraft((current) => (current ? { ...current, [key]: value } : current));
  }, []);

  const save = useCallback(async () => {
    if (!product || !current || !draft || saving) return;
    if (!isValidMoneyInput(draft.price)) {
      showToast(t("product.validation.priceRequired"));
      return;
    }
    const weight = Number(draft.weightGrams);
    if (!Number.isInteger(weight) || weight < 0) {
      showToast(t("variant.shipping.weightInvalid"));
      return;
    }

    setSaving(true);
    try {
      // 🔴 整份回送（見檔頭②）：只把**這一列**換成 draft，其餘原樣。
      const options = [ ...product.options ].sort((a, b) => a.position - b.position);
      const rows: VariantRowData[] = variants.map((node) => {
        const editing = node.id === current.id;
        const source = editing ? draft : draftOf(node);
        return {
          id: node.id,
          coords: options.map((option) => source.coords[option.name] ?? ""),
          price: source.price,
          sku: source.sku,
          quantity: "",
          compare: source.compare,
          cost: source.cost,
          barcode: source.barcode,
          taxable: source.taxable,
          weightGrams: Number(source.weightGrams) || 0,
          requiresShipping: source.requiresShipping,
        };
      });

      const data = await requestAdminGraphQL<
        { productSet: { product: { lockVersion: number } | null; userErrors: { field: string[] | null; message: string }[] } },
        Record<string, unknown>
      >(SAVE_MUTATION, {
        input: {
          id: product.id,
          title: product.title,
          lockVersion: product.lockVersion,
          options: options.map((option) => ({
            name: option.name,
            values: [ ...option.values ].sort((a, b) => a.position - b.position).map((v) => v.value),
          })),
          variants: buildVariantsPayload(rows, options, (raw) => centsToApiString(parseMoneyToCents(raw) ?? null)),
        },
        idempotencyKey: uuidV4(),
      });
      const errors = data.productSet.userErrors;
      if (errors.length > 0) {
        showToast(errors[0].message);
        return;
      }
      showToast(t("product.saved"));
      reload();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("variant.saveError"));
    } finally {
      setSaving(false);
    }
  }, [current, draft, product, reload, saving, showToast, t, variants]);

  if (error) {
    return (
      <div className="cl-page cl-page--detail">
        <div className="cl-error-banner" role="alert">
          <div><strong>{t("variant.loadFailed")}</strong><p>{error}</p></div>
          <Button onClick={reload} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />{t("common.retry")}
          </Button>
        </div>
      </div>
    );
  }

  if (!product || !current || !draft) {
    return (
      <div className="cl-page cl-page--detail">
        <Card aria-label={t("variant.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">{t("variant.loading")}</span>
          {Array.from({ length: 4 }, (_, i) => <span className="cl-skeleton" key={i} />)}
        </Card>
      </div>
    );
  }

  const productPath = `/admin/products/${encodeURIComponent(product.id)}`;
  const previous = index > 0 ? variants[index - 1] : null;
  const next = index < variants.length - 1 ? variants[index + 1] : null;

  return (
    <div className="cl-page cl-page--detail cl-product-detail">
      <header className="cl-detail-head">
        <div>
          <Breadcrumb
            items={[ { label: product.title, to: productPath }, { label: current.title } ]}
            label={t("variant.breadcrumb")}
          />
          <h1>{current.title}</h1>
        </div>
        <div className="cl-detail-head__actions">
          {/* 變體間導航（93 §2：右上 ︿﹀）。無上／下一個時 disable 而非隱藏——
              位置固定比較好按，且「這是第一個」本身是有用的資訊。 */}
          <Button
            aria-label={t("variant.nav.previous")}
            disabled={!previous}
            onClick={() => previous && goTo(previous.id)}
            size="small"
            variant="secondary"
          >
            <ChevronUp aria-hidden="true" size={15} />
          </Button>
          <Button
            aria-label={t("variant.nav.next")}
            disabled={!next}
            onClick={() => next && goTo(next.id)}
            size="small"
            variant="secondary"
          >
            <ChevronDown aria-hidden="true" size={15} />
          </Button>
          <Button loading={saving} onClick={() => void save()} variant="primary">
            {t("common.save")}
          </Button>
        </div>
      </header>

      <div className="cl-od-grid">
        <aside className="cl-od-grid__aside">
          <Card>
            <div className="cl-variant-nav__product">
              <span className="cl-variant-nav__thumb">
                <MediaThumb
                  alt={product.featuredImage?.alt ?? null}
                  status={product.featuredImage?.status ?? "UPLOADED"}
                  thumbUrl={product.featuredImage?.thumbUrl ?? null}
                />
              </span>
              <div>
                <a href={productPath}>{product.title}</a>
                <p>{t("variant.nav.count", { count: variants.length })}</p>
              </div>
            </div>

            <label className="cl-variant-nav__search">
              <Search aria-hidden="true" size={14} />
              <input
                aria-label={t("variant.nav.search")}
                onChange={(event) => setSearch(event.target.value)}
                placeholder={t("variant.nav.search")}
                type="search"
                value={search}
              />
            </label>

            <ul aria-label={t("variant.nav.list")} className="cl-variant-nav__list">
              {filtered.map((node) => (
                <li key={node.id}>
                  <button
                    aria-current={node.id === current.id ? "page" : undefined}
                    className={node.id === current.id
                      ? "cl-variant-nav__item cl-variant-nav__item--on"
                      : "cl-variant-nav__item"}
                    onClick={() => goTo(node.id)}
                    type="button"
                  >
                    <span className="cl-variant-nav__thumb">
                      <MediaThumb
                        alt={node.image?.alt ?? null}
                        status={node.image?.status ?? "UPLOADED"}
                        thumbUrl={node.image?.thumbUrl ?? null}
                      />
                    </span>
                    <span>{node.title}</span>
                  </button>
                </li>
              ))}
            </ul>
            {filtered.length === 0 ? <p className="cl-variant-nav__empty">{t("variant.nav.noMatch")}</p> : null}
          </Card>
        </aside>

        <div className="cl-od-grid__main">
          <Card title={t("variant.card.options")}>
            <div className="cl-variant-head">
              <VariantImageSlot
                image={current.image ? { id: current.id, ...current.image } : null}
                onChange={reload}
                productGid={product.id}
                variantGid={current.id}
              />
              <div className="cl-variant-head__meta">
                <Badge tone={product.status === "ACTIVE" ? "success" : "default"}>
                  {t(`status.${product.status.toLocaleLowerCase()}`)}
                </Badge>
              </div>
            </div>
            {/* 選項值可直接改（93 §2 實測：「選項值 input（尺寸=S，可直接改值）」）。
                🔴 改這裡等於改選項值本身——它會影響**所有**用到該值的變體，
                因為 productSet 的 options 樹是全域的。 */}
            {product.options.map((option) => (
              <TextField
                key={option.name}
                label={option.name}
                onChange={(event) => setField("coords", { ...draft.coords, [option.name]: event.target.value })}
                value={draft.coords[option.name] ?? ""}
              />
            ))}
          </Card>

          <Card title={t("variant.card.pricing")}>
            <TextField label={t("product.price.label")} onChange={(e) => setField("price", e.target.value)} value={draft.price} />
            <TextField label={t("product.compare.label")} onChange={(e) => setField("compare", e.target.value)} value={draft.compare} />
            <TextField label={t("product.cost.label")} onChange={(e) => setField("cost", e.target.value)} value={draft.cost} />
            <label className="cl-check">
              <input
                checked={draft.taxable}
                onChange={(event) => setField("taxable", event.target.checked)}
                type="checkbox"
              />
              <span>{t("product.tax.checkbox")}</span>
            </label>
          </Card>

          <Card title={t("variant.card.inventory")}>
            <TextField label={t("product.sku.label")} onChange={(e) => setField("sku", e.target.value)} value={draft.sku} />
            <TextField label={t("product.barcode.label")} onChange={(e) => setField("barcode", e.target.value)} value={draft.barcode} />
            {/* 🔴 唯讀（見檔頭③）：庫存只能經 inventoryAdjustQuantities 改，
                不隨商品儲存送出。要調整請到庫存頁或商品頁的庫存卡。 */}
            {current.inventoryLevels.length === 0 ? (
              <p className="cl-variant-inventory__empty">{t("variant.inventory.none")}</p>
            ) : (
              <table className="cl-inventory-card__table">
                <caption className="cl-sr-only">{t("variant.inventory.caption")}</caption>
                <thead>
                  <tr>
                    <th scope="col">{t("variant.inventory.location")}</th>
                    <th scope="col">{t("inventory.col.available")}</th>
                    <th scope="col">{t("inventory.col.committed")}</th>
                    <th scope="col">{t("inventory.col.onHand")}</th>
                  </tr>
                </thead>
                <tbody>
                  {current.inventoryLevels.map((level) => (
                    <tr key={level.location.id}>
                      <th scope="row">{level.location.name}</th>
                      <td className="cl-index-table__number">{level.quantities.available}</td>
                      <td className="cl-index-table__number">{level.quantities.committed}</td>
                      <td className="cl-index-table__number">{level.quantities.onHand}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
            <p className="cl-variant-inventory__note">{t("variant.inventory.readOnly")}</p>
          </Card>

          <Card title={t("variant.card.shipping")}>
            <label className="cl-check">
              <input
                checked={draft.requiresShipping}
                onChange={(event) => setField("requiresShipping", event.target.checked)}
                type="checkbox"
              />
              <span>{t("variant.shipping.physical")}</span>
            </label>
            {draft.requiresShipping ? (
              <TextField
                label={t("variant.shipping.weight")}
                onChange={(e) => setField("weightGrams", e.target.value)}
                value={draft.weightGrams}
              />
            ) : null}
          </Card>
        </div>
      </div>
    </div>
  );
}
