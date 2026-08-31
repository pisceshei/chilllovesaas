import { ArrowLeft, RefreshCw } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { financialTone, formatMoney, fulfillmentTone } from "./OrdersPage";

const ORDER_QUERY = `
  query OrderDetail($id: ID!) {
    order(id: $id) {
      id
      name
      status
      email
      note
      tags
      processedAt
      displayFinancialStatus
      displayFulfillmentStatus
      itemCount
      currencyCode
      subtotalPriceSet { shopMoney { amount currencyCode } }
      totalShippingPriceSet { shopMoney { amount currencyCode } }
      totalDiscountsSet { shopMoney { amount currencyCode } }
      totalPriceSet { shopMoney { amount currencyCode } }
      lineItems {
        id title variantTitle sku quantity fulfillableQuantity
        unitPriceSet { shopMoney { amount currencyCode } }
        totalSet { shopMoney { amount currencyCode } }
      }
      fulfillmentOrders { id status }
      fulfillments {
        id status trackingCompany shippedAt
        trackingInfo { number url }
        lineItems { quantity lineItem { id title } }
      }
      refunds { id status processedAt totalRefundedSet { shopMoney { amount currencyCode } } }
      transactions { id kind status gateway amountSet { shopMoney { amount currencyCode } } }
      customer { id displayName email }
      shippingAddress { firstName lastName address1 address2 city province postalCode countryCode phone }
      billingAddress { firstName lastName address1 address2 city province postalCode countryCode phone }
    }
  }
`;

const FULFILLMENT_CREATE_MUTATION = `
  mutation FulfillmentCreate($fulfillment: FulfillmentInput!) {
    fulfillmentCreate(fulfillment: $fulfillment) {
      fulfillment { id status }
      userErrors { field message code }
    }
  }
`;

const FULFILLMENT_CANCEL_MUTATION = `
  mutation FulfillmentCancel($id: ID!) {
    fulfillmentCancel(id: $id) {
      fulfillment { id status }
      userErrors { field message code }
    }
  }
`;

const MARK_AS_PAID_MUTATION = `
  mutation OrderMarkAsPaid($id: ID!, $idempotencyKey: String!) {
    orderMarkAsPaid(id: $id, idempotencyKey: $idempotencyKey) {
      order { id displayFinancialStatus }
      userErrors { field message code }
    }
  }
`;

interface Money { amount: string; currencyCode: string }
interface AddressShape {
  firstName: string | null; lastName: string | null; address1: string | null;
  address2: string | null; city: string | null; province: string | null;
  postalCode: string | null; countryCode: string | null; phone: string | null;
}

/** 訂單詳情 GraphQL 形（G6-6 步 4；88 §3 卡片序的資料已備子集）。 */
export interface OrderDetail {
  id: string;
  name: string;
  status: string;
  email: string | null;
  note: string | null;
  tags: string[];
  processedAt: string | null;
  displayFinancialStatus: string;
  displayFulfillmentStatus: string;
  itemCount: number;
  currencyCode: string;
  subtotalPriceSet: { shopMoney: Money };
  totalShippingPriceSet: { shopMoney: Money };
  totalDiscountsSet: { shopMoney: Money };
  totalPriceSet: { shopMoney: Money };
  lineItems: {
    id: string; title: string; variantTitle: string | null; sku: string | null;
    quantity: number; fulfillableQuantity: number;
    unitPriceSet: { shopMoney: Money }; totalSet: { shopMoney: Money };
  }[];
  fulfillmentOrders: { id: string; status: string }[];
  fulfillments: {
    id: string; status: string; trackingCompany: string | null; shippedAt: string | null;
    trackingInfo: { number: string | null; url: string | null }[];
    lineItems: { quantity: number; lineItem: { id: string; title: string } | null }[];
  }[];
  refunds: {
    id: string; status: string; processedAt: string | null;
    totalRefundedSet: { shopMoney: Money };
  }[];
  transactions: {
    id: string; kind: string; status: string; gateway: string;
    amountSet: { shopMoney: Money };
  }[];
  customer: { id: string; displayName: string; email: string | null } | null;
  shippingAddress: AddressShape | null;
  billingAddress: AddressShape | null;
}

function addressLines(address: AddressShape): string[] {
  return [
    [ address.firstName, address.lastName ].filter(Boolean).join(" "),
    address.address1 ?? "",
    address.address2 ?? "",
    [ address.city, address.province, address.postalCode ].filter(Boolean).join(" "),
    address.countryCode ?? "",
    address.phone ?? "",
  ].filter((line) => line.length > 0);
}

/** idempotency key（secure context 有 randomUUID；jsdom/明文後備走時間戳）。 */
function newIdempotencyKey(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) return crypto.randomUUID();
  return `mark-paid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

/**
 * 訂單詳情頁（G6-6 步 4；88 §3 骨架的資料已備子集：badges＋行項卡＋付款卡＋
 * 右欄顧客/地址卡＋Mark as paid）。Timeline/風險卡/編輯動作＝後續包。
 */
export function OrderDetailPage() {
  const { orderId } = useParams<{ orderId: string }>();
  const t = useT();
  const { showToast } = useToast();
  const [order, setOrder] = useState<OrderDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notFound, setNotFound] = useState(false);
  const [confirmMarkPaid, setConfirmMarkPaid] = useState(false);
  const [fulfillDialog, setFulfillDialog] = useState(false);
  const [fulfilling, setFulfilling] = useState(false);
  const [trackingCompany, setTrackingCompany] = useState("");
  const [trackingNumber, setTrackingNumber] = useState("");
  const [trackingUrl, setTrackingUrl] = useState("");
  const [notifyCustomer, setNotifyCustomer] = useState(false);
  const [cancelFulfillmentId, setCancelFulfillmentId] = useState<string | null>(null);
  const [cancelling, setCancelling] = useState(false);
  const [markingPaid, setMarkingPaid] = useState(false);
  const [reloadNonce, setReloadNonce] = useState(0);

  const gid = `gid://chilllove/Order/${orderId}`;

  useEffect(() => {
    const controller = new AbortController();
    setError(null);
    requestAdminGraphQL<{ order: OrderDetail | null }, { id: string }>(
      ORDER_QUERY, { id: gid }, controller.signal,
    )
      .then((data) => {
        if (data.order === null) setNotFound(true);
        else setOrder(data.order);
      })
      .catch((requestError: unknown) => {
        if (controller.signal.aborted) return;
        setError(requestError instanceof Error ? requestError.message : t("orders.loadError"));
      });
    return () => controller.abort();
  }, [gid, reloadNonce, t]);

  const markAsPaid = useCallback(async () => {
    if (!order || markingPaid) return;
    setMarkingPaid(true);
    setConfirmMarkPaid(false);
    try {
      const data = await requestAdminGraphQL<{
        orderMarkAsPaid: {
          order: { id: string; displayFinancialStatus: string } | null;
          userErrors: { message: string }[];
        };
      }, { id: string; idempotencyKey: string }>(
        MARK_AS_PAID_MUTATION, { id: order.id, idempotencyKey: newIdempotencyKey() },
      );
      const payload = data.orderMarkAsPaid;
      if (payload.userErrors.length > 0 || !payload.order) {
        showToast(payload.userErrors[0]?.message ?? t("orders.markPaid.failed"));
      } else {
        showToast(t("orders.markPaid.done"));
        setReloadNonce((nonce) => nonce + 1);
      }
    } catch (mutationError: unknown) {
      showToast(mutationError instanceof Error ? mutationError.message : t("orders.markPaid.failed"));
    } finally {
      setMarkingPaid(false);
    }
  }, [order, markingPaid, showToast, t]);

  const fulfill = useCallback(async () => {
    if (!order || fulfilling) return;
    setFulfilling(true);
    try {
      const fo = order.fulfillmentOrders.find((candidate) => candidate.status === "open" || candidate.status === "in_progress");
      if (!fo) {
        showToast(t("orders.fulfill.noFo"));
        return;
      }
      const trackingInfo = trackingNumber
        ? { company: trackingCompany || null, number: trackingNumber, url: trackingUrl || null }
        : (trackingCompany ? { company: trackingCompany } : null);
      const data = await requestAdminGraphQL<{
        fulfillmentCreate: { fulfillment: { id: string } | null; userErrors: { message: string }[] };
      }, Record<string, unknown>>(FULFILLMENT_CREATE_MUTATION, {
        fulfillment: {
          lineItemsByFulfillmentOrder: [ { fulfillmentOrderId: fo.id } ],
          notifyCustomer: notifyCustomer,
          trackingInfo,
        },
      });
      const payload = data.fulfillmentCreate;
      if (payload.userErrors.length > 0 || !payload.fulfillment) {
        showToast(payload.userErrors[0]?.message ?? t("orders.fulfill.failed"));
      } else {
        showToast(t("orders.fulfill.done"));
        setFulfillDialog(false);
        setReloadNonce((nonce) => nonce + 1);
      }
    } catch (mutationError: unknown) {
      showToast(mutationError instanceof Error ? mutationError.message : t("orders.fulfill.failed"));
    } finally {
      setFulfilling(false);
    }
  }, [order, fulfilling, trackingCompany, trackingNumber, trackingUrl, notifyCustomer, showToast, t]);

  const cancelFulfillment = useCallback(async () => {
    if (!cancelFulfillmentId || cancelling) return;
    setCancelling(true);
    try {
      const data = await requestAdminGraphQL<{
        fulfillmentCancel: { fulfillment: { id: string } | null; userErrors: { message: string }[] };
      }, { id: string }>(FULFILLMENT_CANCEL_MUTATION, { id: cancelFulfillmentId });
      const payload = data.fulfillmentCancel;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0]?.message ?? t("orders.fulfillCancel.failed"));
      } else {
        showToast(t("orders.fulfillCancel.done"));
        setReloadNonce((nonce) => nonce + 1);
      }
    } catch (mutationError: unknown) {
      showToast(mutationError instanceof Error ? mutationError.message : t("orders.fulfillCancel.failed"));
    } finally {
      setCancelling(false);
      setCancelFulfillmentId(null);
    }
  }, [cancelFulfillmentId, cancelling, showToast, t]);

  const backLink = (
    <Link className="cl-back-link" to="/admin/orders">
      <ArrowLeft aria-hidden="true" size={14} /> {t("orders.title")}
    </Link>
  );

  if (notFound) {
    return (
      <Page title={t("orders.detail.notFound")} width="detail">
        {backLink}
        <Card><p>{t("orders.detail.notFoundBody")}</p></Card>
      </Page>
    );
  }

  if (error) {
    return (
      <Page title={t("orders.title")} width="detail">
        {backLink}
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("orders.loadFailed")}</strong>
            <p>{error}</p>
          </div>
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
          {Array.from({ length: 4 }, (_, index) => <span className="cl-skeleton" key={index} />)}
        </Card>
      </Page>
    );
  }

  const canMarkPaid = order.displayFinancialStatus === "PENDING" && order.status === "open";
  // 88 §3 實測：Refund 鈕存在性是金額狀態函數（$0 已付單無 Refund）
  const canRefund = order.status !== "cancelled" &&
    [ "PAID", "PARTIALLY_PAID", "PARTIALLY_REFUNDED" ].includes(order.displayFinancialStatus);
  const unfulfilledLines = order.lineItems.filter((line) => line.fulfillableQuantity > 0);
  const activeFulfillments = order.fulfillments.filter((fulfillment) => fulfillment.status === "success");

  return (
    <Page
      actions={(canMarkPaid || canRefund) ? (
        <>
          {canRefund ? (
            <Link className="cl-button cl-button--secondary" to={`/admin/orders/${orderId}/refund`}>
              {t("orders.refund.title")}
            </Link>
          ) : null}
          {canMarkPaid ? (
            <Button disabled={markingPaid} onClick={() => setConfirmMarkPaid(true)} variant="primary">
              {t("orders.markPaid.action")}
            </Button>
          ) : null}
        </>
      ) : undefined}
      title={order.name}
      width="detail"
    >
      {backLink}
      <p className="cl-muted">
        <Badge tone={financialTone(order.displayFinancialStatus)}>
          {t(`orders.financial.${order.displayFinancialStatus}`)}
        </Badge>{" "}
        <Badge tone={fulfillmentTone(order.displayFulfillmentStatus)}>
          {t(`orders.fulfillment.${order.displayFulfillmentStatus}`)}
        </Badge>{" "}
        {order.processedAt ? new Date(order.processedAt).toLocaleString() : ""}
      </p>
      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          {unfulfilledLines.length > 0 ? (
            <Card>
              <h3>
                <Badge tone="warning">{t("orders.fulfillment.UNFULFILLED")}</Badge>{" "}
                ({unfulfilledLines.reduce((sum, line) => sum + line.fulfillableQuantity, 0)})
              </h3>
              {unfulfilledLines.map((line) => (
                <div className="cl-order-line" key={line.id}>
                  <div>
                    <strong>{line.title}</strong>
                    {line.variantTitle && line.variantTitle !== "Default Title" ? (
                      <div className="cl-muted">{line.variantTitle}</div>
                    ) : null}
                    {line.sku ? <div className="cl-muted">SKU: {line.sku}</div> : null}
                  </div>
                  <div className="cl-order-line__qty">
                    {formatMoney(line.unitPriceSet.shopMoney)} × {line.fulfillableQuantity}
                  </div>
                  <div className="cl-order-line__total">{formatMoney(line.totalSet.shopMoney)}</div>
                </div>
              ))}
              {order.status !== "cancelled" ? (
                <Button onClick={() => setFulfillDialog(true)} variant="primary">
                  {t("orders.fulfill.action")}
                </Button>
              ) : null}
            </Card>
          ) : null}

          {activeFulfillments.map((fulfillment, index) => (
            <Card key={fulfillment.id}>
              <h3>
                <Badge tone="success">{t("orders.fulfillment.FULFILLED")}</Badge>{" "}
                {order.name}-F{index + 1}
              </h3>
              {fulfillment.shippedAt ? (
                <p className="cl-muted">{new Date(fulfillment.shippedAt).toLocaleString()}</p>
              ) : null}
              {fulfillment.trackingCompany ? (
                <p className="cl-muted">{fulfillment.trackingCompany}</p>
              ) : null}
              {fulfillment.trackingInfo.map((info) => (
                <p className="cl-muted" key={info.number ?? ""}>
                  {info.url ? (
                    <a href={info.url} rel="noreferrer" target="_blank">{info.number}</a>
                  ) : info.number}
                </p>
              ))}
              {fulfillment.lineItems.map((entry, entryIndex) => (
                <div className="cl-order-line" key={entryIndex}>
                  <div><strong>{entry.lineItem?.title ?? t("orders.fulfill.removedItem")}</strong></div>
                  <div className="cl-order-line__qty">× {entry.quantity}</div>
                  <div />
                </div>
              ))}
              <Button onClick={() => setCancelFulfillmentId(fulfillment.id)} size="small" variant="secondary">
                {t("orders.fulfillCancel.action")}
              </Button>
            </Card>
          ))}

          {order.refunds.length > 0 ? (
            <Card>
              <h3>{t("orders.refund.historyTitle")}</h3>
              {order.refunds.map((refund) => (
                <div className="cl-order-cost" key={refund.id}>
                  <span>{refund.processedAt ? new Date(refund.processedAt).toLocaleString() : ""}</span>
                  <span className="cl-muted">{t(`orders.refundStatus.${refund.status}`)}</span>
                  <span>-{formatMoney(refund.totalRefundedSet.shopMoney)}</span>
                </div>
              ))}
            </Card>
          ) : null}

          <Card>
            <h3>{t(`orders.financial.${order.displayFinancialStatus}`)}</h3>
            <div className="cl-order-cost">
              <span>{t("orders.detail.subtotal")}</span>
              <span className="cl-muted">{t("orders.itemCount", { count: order.itemCount })}</span>
              <span>{formatMoney(order.subtotalPriceSet.shopMoney)}</span>
            </div>
            {order.totalDiscountsSet.shopMoney.amount !== "0.00" ? (
              <div className="cl-order-cost">
                <span>{t("orders.detail.discount")}</span>
                <span />
                <span>-{formatMoney(order.totalDiscountsSet.shopMoney)}</span>
              </div>
            ) : null}
            <div className="cl-order-cost">
              <span>{t("orders.detail.shipping")}</span>
              <span />
              <span>{formatMoney(order.totalShippingPriceSet.shopMoney)}</span>
            </div>
            <div className="cl-order-cost cl-order-cost--total">
              <span>{t("orders.detail.total")}</span>
              <span />
              <span>{formatMoney(order.totalPriceSet.shopMoney)}</span>
            </div>
            {order.transactions.map((transaction) => (
              <div className="cl-muted" key={transaction.id}>
                {t(`orders.transaction.${transaction.kind}`)} ·{" "}
                {t(`orders.transactionStatus.${transaction.status}`)} · {transaction.gateway} ·{" "}
                {formatMoney(transaction.amountSet.shopMoney)}
              </div>
            ))}
          </Card>
        </div>

        <div className="cl-od-grid__aside">
          <Card>
            <h3>{t("orders.detail.customer")}</h3>
            {order.customer ? (
              <>
                <p>{order.customer.displayName}</p>
                {order.customer.email ? <p className="cl-muted">{order.customer.email}</p> : null}
              </>
            ) : (
              <p className="cl-muted">{t("orders.noCustomer")}</p>
            )}
            {order.email && !order.customer ? <p className="cl-muted">{order.email}</p> : null}
          </Card>
          <Card>
            <h3>{t("orders.detail.shippingAddress")}</h3>
            {order.shippingAddress ? (
              addressLines(order.shippingAddress).map((line) => <p key={line}>{line}</p>)
            ) : (
              <p className="cl-muted">{t("orders.detail.noAddress")}</p>
            )}
          </Card>
          <Card>
            <h3>{t("orders.detail.billingAddress")}</h3>
            {order.billingAddress ? (
              addressLines(order.billingAddress).map((line) => <p key={line}>{line}</p>)
            ) : (
              <p className="cl-muted">{t("orders.detail.noAddress")}</p>
            )}
          </Card>
          {order.tags.length > 0 ? (
            <Card>
              <h3>{t("orders.detail.tags")}</h3>
              <p>{order.tags.join(", ")}</p>
            </Card>
          ) : null}
        </div>
      </div>

      <ConfirmDialog
        busy={fulfilling}
        confirmLabel={t("orders.fulfill.confirm")}
        message={(
          <div className="cl-form-stack">
            <label>
              {t("orders.fulfill.trackingCompany")}
              <input className="cl-input" onChange={(event) => setTrackingCompany(event.target.value)} type="text" value={trackingCompany} />
            </label>
            <label>
              {t("orders.fulfill.trackingNumber")}
              <input className="cl-input" onChange={(event) => setTrackingNumber(event.target.value)} type="text" value={trackingNumber} />
            </label>
            <label>
              {t("orders.fulfill.trackingUrl")}
              <input className="cl-input" onChange={(event) => setTrackingUrl(event.target.value)} type="text" value={trackingUrl} />
            </label>
            <label className="cl-checkbox">
              <input checked={notifyCustomer} onChange={(event) => setNotifyCustomer(event.target.checked)} type="checkbox" />
              {t("orders.fulfill.notify")}
            </label>
          </div>
        )}
        onCancel={() => setFulfillDialog(false)}
        onConfirm={() => void fulfill()}
        open={fulfillDialog}
        title={t("orders.fulfill.title")}
      />
      <ConfirmDialog
        busy={cancelling}
        confirmLabel={t("orders.fulfillCancel.confirm")}
        message={<p>{t("orders.fulfillCancel.body")}</p>}
        onCancel={() => setCancelFulfillmentId(null)}
        onConfirm={() => void cancelFulfillment()}
        open={cancelFulfillmentId !== null}
        title={t("orders.fulfillCancel.action")}
      />
      <ConfirmDialog
        busy={markingPaid}
        confirmLabel={t("orders.markPaid.confirm")}
        message={<p>{t("orders.markPaid.body", { total: formatMoney(order.totalPriceSet.shopMoney) })}</p>}
        onCancel={() => setConfirmMarkPaid(false)}
        onConfirm={() => void markAsPaid()}
        open={confirmMarkPaid}
        title={t("orders.markPaid.title")}
      />
    </Page>
  );
}
