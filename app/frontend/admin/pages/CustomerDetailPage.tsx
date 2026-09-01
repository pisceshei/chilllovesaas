import { ArrowLeft, ChevronDown, MoreHorizontal } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { Modal } from "../components/Modal";
import { Page } from "../components/Page";
import { Popover } from "../components/Popover";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { formatMoney } from "./OrdersPage";

/**
 * 顧客詳情頁（G6 步 8b；74 §4＋docs/dev/g6-customer-mutations.md §5 實測對位）：
 * KPI 四格（RFM ⚪ 佔位）／最近訂單卡／右欄（聯絡卡 ⋯ 三 modal／預設地址／
 * 行銷訂閱／稅務／標籤／備註）／More actions（Merge／Erase／Cancel erasure／Delete）。
 * ⚪：時間軸 composer／寄送 email／商店抵用金／Request customer data／建立訂單。
 */
const DETAIL_QUERY = `
  query customerDetail($id: ID!) {
    customer(id: $id) {
      id email firstName lastName displayName phone locale note tags taxExempt
      emailMarketingState smsMarketingState
      redactionScheduledAt anonymizedAt
      ordersCount amountSpent { amount currencyCode }
      lastOrderAt createdAt
      addresses { id firstName lastName address1 address2 city province postalCode countryCode phone default }
      lastOrder {
        id name financialStatus fulfillmentStatus processedAt
        totalPriceSet { shopMoney { amount currencyCode } }
        lineItems { id title quantity }
      }
    }
  }
`;

const UPDATE_MUTATION = `
  mutation customerUpdate($id: ID!, $firstName: String, $lastName: String, $email: String, $phone: String, $note: String, $tags: [String!], $taxExempt: Boolean, $locale: String) {
    customerUpdate(id: $id, firstName: $firstName, lastName: $lastName, email: $email, phone: $phone, note: $note, tags: $tags, taxExempt: $taxExempt, locale: $locale) {
      customer { id }
      userErrors { field message code }
    }
  }
`;

const CONSENT_EMAIL_MUTATION = `
  mutation customerEmailMarketingConsentUpdate($customerId: ID!, $emailMarketingConsent: MarketingConsentInput!) {
    customerEmailMarketingConsentUpdate(customerId: $customerId, emailMarketingConsent: $emailMarketingConsent) {
      customer { id emailMarketingState }
      userErrors { field message code }
    }
  }
`;

const CONSENT_SMS_MUTATION = `
  mutation customerSmsMarketingConsentUpdate($customerId: ID!, $smsMarketingConsent: MarketingConsentInput!) {
    customerSmsMarketingConsentUpdate(customerId: $customerId, smsMarketingConsent: $smsMarketingConsent) {
      customer { id smsMarketingState }
      userErrors { field message code }
    }
  }
`;

const ERASURE_REQUEST_MUTATION = `
  mutation customerRequestDataErasure($customerId: ID!) {
    customerRequestDataErasure(customerId: $customerId) {
      customer { id redactionScheduledAt }
      userErrors { field message code }
    }
  }
`;

const ERASURE_CANCEL_MUTATION = `
  mutation customerCancelDataErasure($customerId: ID!) {
    customerCancelDataErasure(customerId: $customerId) {
      customer { id redactionScheduledAt }
      userErrors { field message code }
    }
  }
`;

const DELETE_MUTATION = `
  mutation customerDelete($id: ID!) {
    customerDelete(id: $id) {
      deletedCustomerId
      userErrors { field message code }
    }
  }
`;

const MERGE_MUTATION = `
  mutation customerMerge($customerOneId: ID!, $customerTwoId: ID!) {
    customerMerge(customerOneId: $customerOneId, customerTwoId: $customerTwoId) {
      customer { id }
      userErrors { field message code }
    }
  }
`;

const SEARCH_QUERY = `
  query customerMergeSearch($query: String) {
    customers(first: 10, query: $query) {
      nodes { id displayName email }
    }
  }
`;

interface AddressRow {
  id: string;
  firstName: string | null;
  lastName: string | null;
  address1: string;
  address2: string | null;
  city: string;
  province: string | null;
  postalCode: string | null;
  countryCode: string;
  phone: string | null;
  default: boolean;
}

interface CustomerDetail {
  id: string;
  email: string | null;
  firstName: string | null;
  lastName: string | null;
  displayName: string;
  phone: string | null;
  locale: string | null;
  note: string | null;
  tags: string[];
  taxExempt: boolean;
  emailMarketingState: string;
  smsMarketingState: string;
  redactionScheduledAt: string | null;
  anonymizedAt: string | null;
  ordersCount: number;
  amountSpent: { amount: string; currencyCode: string };
  lastOrderAt: string | null;
  createdAt: string;
  addresses: AddressRow[];
  lastOrder: {
    id: string;
    name: string;
    financialStatus: string;
    fulfillmentStatus: string;
    processedAt: string | null;
    totalPriceSet: { shopMoney: { amount: string; currencyCode: string } };
    lineItems: { id: string; title: string; quantity: number }[];
  } | null;
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function CustomerDetailPage() {
  const t = useT();
  const { customerId = "" } = useParams();
  const gid = `gid://chilllove/Customer/${customerId}`;
  const navigate = useNavigate();
  const { showToast } = useToast();
  const [data, setData] = useState<CustomerDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const [dialog, setDialog] = useState<"none" | "contact" | "marketing" | "merge" | "erase" | "delete">("none");
  const [contactDraft, setContactDraft] = useState({ firstName: "", lastName: "", email: "", phone: "", locale: "" });
  const [noteDraft, setNoteDraft] = useState("");
  const [tagsDraft, setTagsDraft] = useState("");
  const [mergeQuery, setMergeQuery] = useState("");
  const [mergeResults, setMergeResults] = useState<{ id: string; displayName: string; email: string | null }[]>([]);
  const [mergeTarget, setMergeTarget] = useState<{ id: string; displayName: string } | null>(null);
  const moreRef = useRef<HTMLButtonElement | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<{ customer: CustomerDetail | null }, { id: string }>(
        DETAIL_QUERY, { id: gid }, signal
      );
      if (result.customer === null) {
        setError(t("customer.notFound"));
        return;
      }
      setData(result.customer);
      setContactDraft({
        firstName: result.customer.firstName ?? "", lastName: result.customer.lastName ?? "",
        email: result.customer.email ?? "", phone: result.customer.phone ?? "",
        locale: result.customer.locale ?? "",
      });
      setNoteDraft(result.customer.note ?? "");
      setTagsDraft(result.customer.tags.join(", "));
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("customer.loadFailed"));
    }
  }, [gid, t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const runMutation = async <T extends Record<string, MutationErrors | null>>(
    mutation: string, variables: Record<string, unknown>, key: keyof T, successMessage: string
  ) => {
    setBusy(true);
    try {
      const result = await requestAdminGraphQL<T, Record<string, unknown>>(mutation, variables);
      const payload = result[key] as MutationErrors | null;
      if (payload && payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return false;
      }
      showToast(successMessage);
      await load();
      return true;
    } catch {
      showToast(t("settings.payments.actionFailed"));
      return false;
    } finally {
      setBusy(false);
    }
  };

  const saveContact = async () => {
    const ok = await runMutation(UPDATE_MUTATION, {
      id: gid,
      firstName: contactDraft.firstName, lastName: contactDraft.lastName,
      email: contactDraft.email || null, phone: contactDraft.phone || null,
      locale: contactDraft.locale || null,
    }, "customerUpdate", t("customer.saved"));
    if (ok) setDialog("none");
  };

  const toggleConsent = async (channel: "email" | "sms", next: boolean) => {
    const state = next ? "SUBSCRIBED" : "UNSUBSCRIBED";
    if (channel === "email") {
      await runMutation(CONSENT_EMAIL_MUTATION,
        { customerId: gid, emailMarketingConsent: { marketingState: state } },
        "customerEmailMarketingConsentUpdate", t("customer.consentSaved"));
    } else {
      await runMutation(CONSENT_SMS_MUTATION,
        { customerId: gid, smsMarketingConsent: { marketingState: state } },
        "customerSmsMarketingConsentUpdate", t("customer.consentSaved"));
    }
  };

  const searchMerge = async (query: string) => {
    setMergeQuery(query);
    try {
      const result = await requestAdminGraphQL<{ customers: { nodes: { id: string; displayName: string; email: string | null }[] } }, { query: string }>(
        SEARCH_QUERY, { query }
      );
      setMergeResults(result.customers.nodes.filter((node) => node.id !== gid));
    } catch {
      setMergeResults([]);
    }
  };

  const stateLabel = (state: string) =>
    state === "SUBSCRIBED" ? t("customer.subscribed")
      : state === "UNSUBSCRIBED" ? t("customer.unsubscribed")
        : state === "PENDING" ? t("customer.pendingConsent")
          : state === "REDACTED" ? t("customer.redacted")
            : t("customer.notSubscribed");

  if (error) {
    return (
      <Page title={t("customer.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("customer.title")}>
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      </Page>
    );
  }

  const defaultAddress = data.addresses.find((row) => row.default) ?? null;
  const erased = data.anonymizedAt !== null;

  return (
    <Page title={data.displayName}>
      <p className="cl-page-backlink">
        <Link className="cl-backlink" to="/admin/customers">
          <ArrowLeft aria-hidden="true" size={14} />
          {t("nav.customers")}
        </Link>
      </p>

      <div className="cl-section-title-row">
        {data.redactionScheduledAt ? (
          <Badge progress="half" tone="attention">
            {t("customer.erasureScheduled", { date: new Date(data.redactionScheduledAt).toLocaleDateString() })}
          </Badge>
        ) : erased ? (
          <Badge progress="full" tone="default">{t("customer.redacted")}</Badge>
        ) : <span />}
        <Button aria-expanded={menuOpen} aria-haspopup="menu" onClick={() => setMenuOpen(true)} ref={moreRef}>
          {t("customer.moreActions")}
          <ChevronDown aria-hidden="true" size={14} />
        </Button>
      </div>
      <Popover anchorRef={moreRef} dismissOnOutsideClick label={t("customer.moreActions")}
        onClose={() => setMenuOpen(false)} open={menuOpen}>
        <ul className="cl-menu-list" role="menu">
          <li role="none">
            <button className="cl-menu-list__item" disabled={erased}
              onClick={() => { setMenuOpen(false); setDialog("merge"); void searchMerge(""); }} role="menuitem" type="button">
              {t("customer.mergeAction")}
            </button>
          </li>
          {data.redactionScheduledAt ? (
            <li role="none">
              <button className="cl-menu-list__item"
                onClick={() => { setMenuOpen(false); void runMutation(ERASURE_CANCEL_MUTATION, { customerId: gid }, "customerCancelDataErasure", t("customer.erasureCancelled")); }}
                role="menuitem" type="button">
                {t("customer.cancelErasure")}
              </button>
            </li>
          ) : (
            <li role="none">
              <button className="cl-menu-list__item" disabled={erased}
                onClick={() => { setMenuOpen(false); setDialog("erase"); }} role="menuitem" type="button">
                {t("customer.eraseAction")}
              </button>
            </li>
          )}
          <li role="none">
            <button className="cl-menu-list__item cl-menu-list__item--danger"
              onClick={() => { setMenuOpen(false); setDialog("delete"); }} role="menuitem" type="button">
              {t("customer.deleteAction")}
            </button>
          </li>
        </ul>
      </Popover>

      <Card padded>
        <div className="cl-kpi-row">
          <div className="cl-kpi-cell">
            <small>{t("customer.kpi.amountSpent")}</small>
            <strong>{formatMoney(data.amountSpent)}</strong>
          </div>
          <div className="cl-kpi-cell">
            <small>{t("customer.kpi.orders")}</small>
            <strong>{data.ordersCount}</strong>
          </div>
          <div className="cl-kpi-cell">
            <small>{t("customer.kpi.customerSince")}</small>
            <strong>{new Date(data.createdAt).toLocaleDateString()}</strong>
          </div>
          <div className="cl-kpi-cell">
            <small>{t("customer.kpi.rfmGroup")}</small>
            <strong>—</strong>
          </div>
        </div>
      </Card>

      <div className="cl-detail-columns">
        <div className="cl-detail-main">
          <Card padded>
            <div className="cl-section-title-row">
              <h3 className="cl-section-title">{t("customer.lastOrder")}</h3>
              <Link to="/admin/orders"><Button variant="secondary">{t("customer.viewAllOrders")}</Button></Link>
            </div>
            {data.lastOrder ? (
              <div>
                <p>
                  <button className="cl-link-button" onClick={() => navigate(`/admin/orders/${data.lastOrder!.id.replace("gid://chilllove/Order/", "")}`)} type="button">
                    <strong>{data.lastOrder.name}</strong>
                  </button>
                  {" "}
                  <Badge progress="full" tone="default">{data.lastOrder.financialStatus}</Badge>
                  {" "}
                  <Badge progress="half" tone="attention">{data.lastOrder.fulfillmentStatus}</Badge>
                  <span className="cl-order-total"> {formatMoney(data.lastOrder.totalPriceSet.shopMoney)}</span>
                </p>
                <p className="cl-card-note">
                  {data.lastOrder.processedAt ? new Date(data.lastOrder.processedAt).toLocaleString() : "—"}
                </p>
                <ul className="cl-config-list">
                  {data.lastOrder.lineItems.map((line) => (
                    <li className="cl-config-list__row" key={line.id}>
                      <span>{line.title} × {line.quantity}</span>
                    </li>
                  ))}
                </ul>
              </div>
            ) : (
              <p className="cl-card-note">{t("customer.noOrders")}</p>
            )}
          </Card>

          <Card padded>
            <h3 className="cl-section-title">{t("customer.notes")}</h3>
            <textarea
              className="cl-field__input cl-field__textarea"
              onChange={(event) => setNoteDraft(event.target.value)}
              rows={3}
              value={noteDraft}
            />
            <Button disabled={busy || erased}
              onClick={() => void runMutation(UPDATE_MUTATION, { id: gid, note: noteDraft }, "customerUpdate", t("customer.saved"))}>
              {t("common.save")}
            </Button>
          </Card>
        </div>

        <div className="cl-detail-side">
          <Card padded>
            <div className="cl-section-title-row">
              <h3 className="cl-section-title">{t("customer.contactInfo")}</h3>
              <Button aria-label={t("customer.editContact")} disabled={erased}
                onClick={() => setDialog("contact")} variant="ghost">
                <MoreHorizontal aria-hidden="true" size={16} />
              </Button>
            </div>
            <p>{data.email ?? t("customer.noEmail")}</p>
            {data.phone ? <p>{data.phone}</p> : null}
            <p className="cl-card-note">{t("customer.notificationLanguage", { locale: data.locale ?? t("customer.storeDefault") })}</p>

            <h4 className="cl-section-title">{t("customer.defaultAddress")}</h4>
            {defaultAddress ? (
              <p className="cl-card-note">
                {[ defaultAddress.firstName, defaultAddress.lastName ].filter(Boolean).join(" ")}<br />
                {defaultAddress.address1}{defaultAddress.address2 ? <><br />{defaultAddress.address2}</> : null}<br />
                {defaultAddress.city} {defaultAddress.province ?? ""} {defaultAddress.postalCode ?? ""}<br />
                {defaultAddress.countryCode}
              </p>
            ) : (
              <p className="cl-card-note">{t("customer.noAddress")}</p>
            )}

            <h4 className="cl-section-title">{t("customer.marketing")}</h4>
            <p className="cl-card-note">
              Email：{stateLabel(data.emailMarketingState)}／SMS：{stateLabel(data.smsMarketingState)}
            </p>
            <Button disabled={erased} onClick={() => setDialog("marketing")} variant="secondary">
              {t("customer.editMarketing")}
            </Button>

            <h4 className="cl-section-title">{t("customer.taxDetails")}</h4>
            <label className="cl-choice">
              <input
                checked={data.taxExempt}
                disabled={busy || erased}
                onChange={(event) => void runMutation(UPDATE_MUTATION, { id: gid, taxExempt: event.target.checked }, "customerUpdate", t("customer.saved"))}
                type="checkbox"
              />
              <span className="cl-choice__text"><strong>{t("customer.taxExempt")}</strong></span>
            </label>
          </Card>

          <Card padded>
            <h3 className="cl-section-title">{t("customer.tags")}</h3>
            <TextField
              label={t("customer.tags")}
              labelHidden
              onChange={(event) => setTagsDraft(event.target.value)}
              placeholder={t("customer.tagsPlaceholder")}
              value={tagsDraft}
            />
            <Button disabled={busy || erased}
              onClick={() => void runMutation(UPDATE_MUTATION,
                { id: gid, tags: tagsDraft.split(",").map((tag) => tag.trim()).filter(Boolean) },
                "customerUpdate", t("customer.saved"))}>
              {t("common.save")}
            </Button>
          </Card>
        </div>
      </div>

      {dialog === "contact" ? (
        <Modal
          dismissable={!busy}
          footer={
            <>
              <Button disabled={busy} onClick={() => setDialog("none")}>{t("common.cancel")}</Button>
              <Button disabled={busy} onClick={() => void saveContact()} variant="primary">{t("common.save")}</Button>
            </>
          }
          onClose={() => setDialog("none")}
          open
          title={t("customer.editContact")}
        >
          <TextField data-autofocus label={t("customer.firstName")} onChange={(event) => setContactDraft({ ...contactDraft, firstName: event.target.value })} value={contactDraft.firstName} />
          <TextField label={t("customer.lastName")} onChange={(event) => setContactDraft({ ...contactDraft, lastName: event.target.value })} value={contactDraft.lastName} />
          <TextField hint={t("customer.localeHint")} label={t("customer.language")} onChange={(event) => setContactDraft({ ...contactDraft, locale: event.target.value })} placeholder="zh-Hant" value={contactDraft.locale} />
          <TextField label="Email" onChange={(event) => setContactDraft({ ...contactDraft, email: event.target.value })} type="email" value={contactDraft.email} />
          <TextField label={t("customer.phone")} onChange={(event) => setContactDraft({ ...contactDraft, phone: event.target.value })} value={contactDraft.phone} />
        </Modal>
      ) : null}

      {dialog === "marketing" ? (
        <Modal
          dismissable={!busy}
          footer={<Button disabled={busy} onClick={() => setDialog("none")}>{t("common.cancel")}</Button>}
          onClose={() => setDialog("none")}
          open
          title={t("customer.marketingTitle")}
        >
          <p className="cl-card-note">{t("customer.marketingDesc")}</p>
          <label className="cl-choice">
            <input
              checked={data.emailMarketingState === "SUBSCRIBED"}
              disabled={busy || !data.email}
              onChange={(event) => void toggleConsent("email", event.target.checked)}
              type="checkbox"
            />
            <span className="cl-choice__text">
              <strong>Email</strong>
              <small>{data.email ?? t("customer.noEmail")}</small>
            </span>
          </label>
          <label className="cl-choice">
            <input
              checked={data.smsMarketingState === "SUBSCRIBED"}
              disabled={busy || !data.phone}
              onChange={(event) => void toggleConsent("sms", event.target.checked)}
              type="checkbox"
            />
            <span className="cl-choice__text">
              <strong>SMS</strong>
              <small>{data.phone ?? t("customer.phoneNotProvided")}</small>
            </span>
          </label>
        </Modal>
      ) : null}

      {dialog === "merge" ? (
        <Modal
          dismissable={!busy}
          footer={
            <>
              <Button disabled={busy} onClick={() => setDialog("none")}>{t("common.cancel")}</Button>
              <Button disabled={busy || mergeTarget === null}
                onClick={() => {
                  if (!mergeTarget) return;
                  void runMutation(MERGE_MUTATION, { customerOneId: gid, customerTwoId: mergeTarget.id }, "customerMerge", t("customer.merged"))
                    .then((ok) => { if (ok) setDialog("none"); });
                }}
                variant="primary">
                {t("customer.mergeConfirm")}
              </Button>
            </>
          }
          onClose={() => setDialog("none")}
          open
          title={t("customer.mergeAction")}
        >
          <p className="cl-card-note">{t("customer.mergeHint")}</p>
          <TextField
            data-autofocus
            label={t("customer.mergeSearch")}
            onChange={(event) => void searchMerge(event.target.value)}
            value={mergeQuery}
          />
          <ul className="cl-menu-list">
            {mergeResults.map((row) => (
              <li key={row.id}>
                <button
                  className={`cl-menu-list__item${mergeTarget?.id === row.id ? " cl-menu-list__item--selected" : ""}`}
                  onClick={() => setMergeTarget({ id: row.id, displayName: row.displayName })}
                  type="button"
                >
                  {row.displayName}{row.email ? `（${row.email}）` : ""}
                </button>
              </li>
            ))}
          </ul>
        </Modal>
      ) : null}

      <ConfirmDialog
        busy={busy}
        confirmLabel={t("customer.eraseConfirm")}
        danger
        message={t("customer.eraseMessage")}
        onCancel={() => setDialog("none")}
        onConfirm={() => {
          void runMutation(ERASURE_REQUEST_MUTATION, { customerId: gid }, "customerRequestDataErasure", t("customer.erasureRequested"))
            .then((ok) => { if (ok) setDialog("none"); });
        }}
        open={dialog === "erase"}
      title={t("customer.eraseTitle")}
      />

      <ConfirmDialog
        busy={busy}
        confirmLabel={t("customer.deleteAction")}
        danger
        message={t("customer.deleteMessage")}
        onCancel={() => setDialog("none")}
        onConfirm={() => {
          void runMutation(DELETE_MUTATION, { id: gid }, "customerDelete", t("customer.deleted"))
            .then((ok) => { if (ok) navigate("/admin/customers"); });
        }}
        open={dialog === "delete"}
        title={t("customer.deleteTitle")}
      />
    </Page>
  );
}
