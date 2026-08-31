import { ArrowLeft, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { formatMoney } from "./OrdersPage";

const REFUND_ORDER_QUERY = `
  query RefundOrder($id: ID!) {
    order(id: $id) {
      id
      name
      currencyCode
      displayFinancialStatus
      totalShippingPriceSet { shopMoney { amount currencyCode } }
      lineItems {
        id title variantTitle sku quantity fulfillableQuantity
        unitPriceSet { shopMoney { amount currencyCode } }
      }
      refunds { id status totalRefundedSet { shopMoney { amount currencyCode } } refundLineItems { quantity lineItem { id } } }
    }
  }
`;

const SUGGEST_QUERY = `
  query SuggestRefund($id: ID!, $lines: [RefundLineItemInput!], $refundShipping: Boolean, $shippingAmountCents: Int) {
    order(id: $id) {
      suggestedRefund(refundLineItems: $lines, refundShipping: $refundShipping, shippingAmountCents: $shippingAmountCents) {
        amountSet { shopMoney { amount currencyCode } }
        subtotalSet { shopMoney { amount currencyCode } }
        totalTaxSet { shopMoney { amount currencyCode } }
        shippingSet { shopMoney { amount currencyCode } }
        maximumRefundableSet { shopMoney { amount currencyCode } }
      }
    }
  }
`;

const REFUND_MUTATION = `
  mutation RefundCreate($input: RefundInput!, $idempotencyKey: String!) {
    refundCreate(input: $input, idempotencyKey: $idempotencyKey) {
      refund { id status }
      userErrors { field message code }
    }
  }
`;

interface Money { amount: string; currencyCode: string }
interface RefundOrder {
  id: string;
  name: string;
  currencyCode: string;
  displayFinancialStatus: string;
  totalShippingPriceSet: { shopMoney: Money };
  lineItems: {
    id: string; title: string; variantTitle: string | null; sku: string | null;
    quantity: number; fulfillableQuantity: number; unitPriceSet: { shopMoney: Money };
  }[];
  refunds: {
    id: string; status: string; totalRefundedSet: { shopMoney: Money };
    refundLineItems: { quantity: number; lineItem: { id: string } }[];
  }[];
}
interface Suggestion {
  amountSet: { shopMoney: Money };
  subtotalSet: { shopMoney: Money };
  totalTaxSet: { shopMoney: Money };
  shippingSet: { shopMoney: Money };
  maximumRefundableSet: { shopMoney: Money };
}

function newIdempotencyKey(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return crypto.randomUUID();
  return `refund-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/**
 * 退款頁（G6-8 步 5；88 §4 骨架：行項步進器＋Refund shipping＋Reason＋
 * 右欄 Summary（suggestedRefund 動態）＋上限句＋金額活字主鈕）。
 *
 * 🔴 restock 自動判定（官方兩型語義）：已出貨（fulfillableQuantity < quantity 的
 * 已出部分）＝return；未出貨＝cancel——勾「Restock」時逐行自動選型，
 * 商家不用理解兩個術語（88 §4 的 restock 是條件顯示，同一個簡化方向）。
 */
export function RefundPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const navigate = useNavigate();
  const t = useT();
  const { showToast } = useToast();
  const [order, setOrder] = useState<RefundOrder | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [quantities, setQuantities] = useState<Record<string, number>>({});
  const [restock, setRestock] = useState(true);
  const [refundShipping, setRefundShipping] = useState(false);
  const [note, setNote] = useState("");
  const [suggestion, setSuggestion] = useState<Suggestion | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  const gid = `gid://chilllove/Order/${orderId}`;

  useEffect(() => {
    const controller = new AbortController();
    requestAdminGraphQL<{ order: RefundOrder | null }, { id: string }>(
      REFUND_ORDER_QUERY, { id: gid }, controller.signal,
    )
      .then((data) => {
        if (data.order === null) setError(t("orders.detail.notFound"));
        else setOrder(data.order);
      })
      .catch((requestError: unknown) => {
        if (controller.signal.aborted) return;
        setError(requestError instanceof Error ? requestError.message : t("orders.loadError"));
      });
    return () => controller.abort();
  }, [gid, reloadNonce, t]);

  // 各行已退量（成功/處理中退款佔用；failure 不佔——與伺服器 Calculator 同判準）
  const refundedByLine = useMemo(() => {
    const map: Record<string, number> = {};
    for (const refund of order?.refunds ?? []) {
      if (refund.status === "failure") continue;
      for (const line of refund.refundLineItems) {
        map[line.lineItem.id] = (map[line.lineItem.id] ?? 0) + line.quantity;
      }
    }
    return map;
  }, [order]);

  const selectedLines = useMemo(() => {
    if (!order) return [];
    return order.lineItems
      .filter((line) => (quantities[line.id] ?? 0) > 0)
      .map((line) => ({
        lineItemId: line.id,
        quantity: quantities[line.id] ?? 0,
        // 🔴 兩型 restock：未出貨（fulfillable 還有）＝cancel（撤銷承諾）；
        //   已出貨＝return（貨回來了）。不勾 restock ⇒ no_restock。
        restockType: restock ? (line.fulfillableQuantity > 0 ? "cancel" : "return") : "no_restock",
      }));
  }, [order, quantities, restock]);

  // 預覽（與實退共用伺服器端同一份 Calculator——鐵律 7）
  useEffect(() => {
    if (!order || (selectedLines.length === 0 && !refundShipping)) {
      setSuggestion(null);
      return;
    }
    const controller = new AbortController();
    requestAdminGraphQL<{ order: { suggestedRefund: Suggestion | null } | null }, Record<string, unknown>>(
      SUGGEST_QUERY,
      { id: gid, lines: selectedLines, refundShipping },
      controller.signal,
    )
      .then((data) => setSuggestion(data.order?.suggestedRefund ?? null))
      .catch(() => { /* 預覽失敗不擋操作；實退仍有伺服器端驗證 */ });
    return () => controller.abort();
  }, [gid, order, selectedLines, refundShipping]);

  const submit = useCallback(async () => {
    if (!order || submitting) return;
    setSubmitting(true);
    setConfirming(false);
    try {
      const data = await requestAdminGraphQL<{
        refundCreate: { refund: { id: string } | null; userErrors: { message: string }[] };
      }, Record<string, unknown>>(REFUND_MUTATION, {
        input: {
          orderId: order.id,
          note: note || null,
          refundLineItems: selectedLines,
          shipping: refundShipping ? { fullRefund: true } : null,
        },
        idempotencyKey: newIdempotencyKey(),
      });
      const payload = data.refundCreate;
      if (payload.userErrors.length > 0 || !payload.refund) {
        showToast(payload.userErrors[0]?.message ?? t("orders.refund.failed"));
      } else {
        showToast(t("orders.refund.done"));
        navigate(`/admin/orders/${orderId}`);
      }
    } catch (mutationError: unknown) {
      showToast(mutationError instanceof Error ? mutationError.message : t("orders.refund.failed"));
    } finally {
      setSubmitting(false);
    }
  }, [order, submitting, note, selectedLines, refundShipping, showToast, t, navigate, orderId]);

  const backLink = (
    <Link className="cl-back-link" to={`/admin/orders/${orderId}`}>
      <ArrowLeft aria-hidden="true" size={14} /> {order?.name ?? t("orders.title")}
    </Link>
  );

  if (error) {
    return (
      <Page title={t("orders.refund.title")} width="detail">
        {backLink}
        <div className="cl-error-banner" role="alert">
          <div><strong>{t("orders.loadFailed")}</strong><p>{error}</p></div>
          <Button onClick={() => setReloadNonce((nonce) => nonce + 1)} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      </Page>
    );
  }

  if (!order) {
    return (
      <Page title={t("orders.loading")} width="detail">
        <Card aria-label={t("orders.loading")}>
          <span className="cl-sr-only" role="status">{t("orders.loading")}</span>
          {Array.from({ length: 3 }, (_, index) => <span className="cl-skeleton" key={index} />)}
        </Card>
      </Page>
    );
  }

  const amountLabel = suggestion ? formatMoney(suggestion.amountSet.shopMoney) : formatMoney({ amount: "0.00", currencyCode: order.currencyCode });
  const canSubmit = suggestion !== null && suggestion.amountSet.shopMoney.amount !== "0.00" && !submitting;

  return (
    <Page title={`${t("orders.refund.title")} ${order.name}`} width="detail">
      {backLink}
      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          <Card>
            <h3>{t("orders.refund.items")}</h3>
            {order.lineItems.map((line) => {
              const refundable = line.quantity - (refundedByLine[line.id] ?? 0);
              const value = quantities[line.id] ?? 0;
              return (
                <div className="cl-order-line" key={line.id}>
                  <div>
                    <strong>{line.title}</strong>
                    {line.variantTitle && line.variantTitle !== "Default Title" ? (
                      <div className="cl-muted">{line.variantTitle}</div>
                    ) : null}
                    {line.sku ? <div className="cl-muted">SKU: {line.sku}</div> : null}
                    <div className="cl-muted">{formatMoney(line.unitPriceSet.shopMoney)}</div>
                  </div>
                  <div className="cl-order-line__qty">
                    <input
                      aria-label={t("orders.refund.quantityFor", { title: line.title })}
                      className="cl-input cl-input--qty"
                      max={refundable}
                      min={0}
                      onChange={(event) => {
                        const next = Math.max(0, Math.min(refundable, Number(event.target.value) || 0));
                        setQuantities((state) => ({ ...state, [line.id]: next }));
                      }}
                      type="number"
                      value={value}
                    />
                    <span className="cl-muted"> / {refundable}</span>
                  </div>
                </div>
              );
            })}
            <label className="cl-checkbox">
              <input checked={restock} onChange={(event) => setRestock(event.target.checked)} type="checkbox" />
              {t("orders.refund.restock")}
            </label>
          </Card>

          <Card>
            <h3>{t("orders.refund.shipping")}</h3>
            <label className="cl-checkbox">
              <input
                checked={refundShipping}
                onChange={(event) => setRefundShipping(event.target.checked)}
                type="checkbox"
              />
              {t("orders.refund.shippingFull", { amount: formatMoney(order.totalShippingPriceSet.shopMoney) })}
            </label>
          </Card>

          <Card>
            <h3>{t("orders.refund.reason")}</h3>
            <input
              className="cl-input"
              onChange={(event) => setNote(event.target.value)}
              placeholder={t("orders.refund.reasonPlaceholder")}
              type="text"
              value={note}
            />
            <p className="cl-muted">{t("orders.refund.reasonHint")}</p>
          </Card>
        </div>

        <div className="cl-od-grid__aside">
          <Card>
            <h3>{t("orders.refund.summary")}</h3>
            {suggestion ? (
              <>
                <div className="cl-order-cost">
                  <span>{t("orders.detail.subtotal")}</span><span />
                  <span>{formatMoney(suggestion.subtotalSet.shopMoney)}</span>
                </div>
                {suggestion.totalTaxSet.shopMoney.amount !== "0.00" ? (
                  <div className="cl-order-cost">
                    <span>{t("orders.refund.tax")}</span><span />
                    <span>{formatMoney(suggestion.totalTaxSet.shopMoney)}</span>
                  </div>
                ) : null}
                {suggestion.shippingSet.shopMoney.amount !== "0.00" ? (
                  <div className="cl-order-cost">
                    <span>{t("orders.detail.shipping")}</span><span />
                    <span>{formatMoney(suggestion.shippingSet.shopMoney)}</span>
                  </div>
                ) : null}
                <div className="cl-order-cost cl-order-cost--total">
                  <span>{t("orders.refund.total")}</span><span />
                  <span>{formatMoney(suggestion.amountSet.shopMoney)}</span>
                </div>
                <p className="cl-muted">
                  {t("orders.refund.available", { amount: formatMoney(suggestion.maximumRefundableSet.shopMoney) })}
                </p>
              </>
            ) : (
              <p className="cl-muted">{t("orders.refund.noSelection")}</p>
            )}
            <Button disabled={!canSubmit} onClick={() => setConfirming(true)} variant="primary">
              {t("orders.refund.action", { amount: amountLabel })}
            </Button>
          </Card>
        </div>
      </div>

      <ConfirmDialog
        busy={submitting}
        confirmLabel={t("orders.refund.confirm")}
        message={<p>{t("orders.refund.confirmBody", { amount: amountLabel })}</p>}
        onCancel={() => setConfirming(false)}
        onConfirm={() => void submit()}
        open={confirming}
        title={t("orders.refund.title")}
      />
    </Page>
  );
}
