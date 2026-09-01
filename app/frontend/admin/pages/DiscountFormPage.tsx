import { ArrowLeft } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 折扣表單頁（G6 步 9b；實測 2026-09-01 對位）：Method 分段（code/automatic）＋
 * code 欄＋Generate random code＋值（Percentage/Fixed）＋最低門檻 radio 三值＋
 * 用量上限勾選兩枚＋Combinations 三勾（shipping helper 逐字 "(best value wins)"）
 * ＋Active dates。BxGy/eligibility segment/銷售通路 ⚪。
 */
const DETAIL_QUERY = `
  query discountFor($id: ID!) {
    discount(id: $id) {
      id title code method discountClass valueType basisPoints valueCents
      combinesProduct combinesOrder combinesShipping conditions
      usageLimit oncePerCustomer startsAt endsAt status timesUsed
    }
  }
`;

interface DiscountDetail {
  id: string;
  title: string;
  code: string | null;
  method: string;
  discountClass: string;
  valueType: string;
  basisPoints: number | null;
  valueCents: number | null;
  combinesProduct: boolean;
  combinesOrder: boolean;
  combinesShipping: boolean;
  conditions: Record<string, unknown>;
  usageLimit: number | null;
  oncePerCustomer: boolean;
  startsAt: string | null;
  endsAt: string | null;
  status: string;
  timesUsed: number;
}

interface FormState {
  title: string;
  method: "code" | "automatic";
  code: string;
  valueType: "percentage" | "fixed_amount";
  valueText: string;
  minMode: "none" | "amount" | "quantity";
  minAmount: string;
  minQuantity: string;
  limitTotal: boolean;
  usageLimit: string;
  oncePerCustomer: boolean;
  combinesProduct: boolean;
  combinesOrder: boolean;
  combinesShipping: boolean;
  startsAt: string;
  endsAt: string;
}

const EMPTY: FormState = {
  title: "", method: "code", code: "", valueType: "percentage", valueText: "",
  minMode: "none", minAmount: "", minQuantity: "", limitTotal: false, usageLimit: "",
  oncePerCustomer: false, combinesProduct: false, combinesOrder: false, combinesShipping: false,
  startsAt: "", endsAt: "",
};

function randomCode() {
  // 產碼排除易混字元（17-F1.2：0/O、1/I/L）
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 8 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join("");
}

export function DiscountFormPage() {
  const t = useT();
  const navigate = useNavigate();
  const { type = "order", discountId } = useParams();
  const isNew = discountId === undefined;
  const { showToast } = useToast();
  const [form, setForm] = useState<FormState>(EMPTY);
  const [discountClass, setDiscountClass] = useState(type);
  const [status, setStatus] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState<string | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    if (isNew) return;
    try {
      const data = await requestAdminGraphQL<{ discount: DiscountDetail | null }, { id: string }>(
        DETAIL_QUERY, { id: `gid://chilllove/Discount/${discountId}` }, signal
      );
      const row = data.discount;
      if (!row) { setFormError(t("discounts.notFound")); return; }
      setDiscountClass(row.discountClass);
      setStatus(row.status);
      setForm({
        title: row.title, method: row.method as FormState["method"], code: row.code ?? "",
        valueType: row.valueType as FormState["valueType"],
        valueText: row.valueType === "percentage"
          ? String((row.basisPoints ?? 0) / 100)
          : String(((row.valueCents ?? 0) / 100).toFixed(2)),
        minMode: row.conditions["min_subtotal_cents"] ? "amount"
          : row.conditions["min_quantity"] ? "quantity" : "none",
        minAmount: row.conditions["min_subtotal_cents"] ? String((row.conditions["min_subtotal_cents"] as number) / 100) : "",
        minQuantity: row.conditions["min_quantity"] ? String(row.conditions["min_quantity"]) : "",
        limitTotal: row.usageLimit !== null, usageLimit: row.usageLimit ? String(row.usageLimit) : "",
        oncePerCustomer: row.oncePerCustomer,
        combinesProduct: row.combinesProduct, combinesOrder: row.combinesOrder,
        combinesShipping: row.combinesShipping,
        startsAt: row.startsAt ?? "", endsAt: row.endsAt ?? "",
      });
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setFormError(reason instanceof Error ? reason.message : t("discounts.loadFailed"));
    }
  }, [discountId, isNew, t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const save = async () => {
    setBusy(true);
    setFormError(null);
    try {
      const input: Record<string, unknown> = {
        title: form.title || form.code,
        discountClass,
        valueType: form.valueType,
        combinesProduct: form.combinesProduct,
        combinesOrder: form.combinesOrder,
        combinesShipping: discountClass === "shipping" ? false : form.combinesShipping,
        oncePerCustomer: form.oncePerCustomer,
      };
      if (form.method === "code") input.code = form.code;
      if (form.valueType === "percentage") {
        input.basisPoints = Math.round(Number(form.valueText || "0") * 100);
      } else {
        input.valueCents = Math.round(Number(form.valueText || "0") * 100);
      }
      input.minSubtotalCents = form.minMode === "amount" ? Math.round(Number(form.minAmount || "0") * 100) : null;
      input.minQuantity = form.minMode === "quantity" ? Number(form.minQuantity || "0") : null;
      input.usageLimit = form.limitTotal && form.usageLimit ? Number(form.usageLimit) : null;
      if (form.startsAt) input.startsAt = form.startsAt;
      if (form.endsAt) input.endsAt = form.endsAt;

      const mutationName = form.method === "code"
        ? (isNew ? "discountCodeBasicCreate" : "discountCodeBasicUpdate")
        : (isNew ? "discountAutomaticBasicCreate" : "discountAutomaticBasicUpdate");
      const gql = isNew
        ? `mutation($input: DiscountBasicInput!) { ${mutationName}(input: $input) { discount { id } userErrors { field message code } } }`
        : `mutation($id: ID!, $input: DiscountBasicInput!) { ${mutationName}(id: $id, input: $input) { discount { id } userErrors { field message code } } }`;
      const variables: Record<string, unknown> = isNew
        ? { input }
        : { id: `gid://chilllove/Discount/${discountId}`, input };

      const data = await requestAdminGraphQL<Record<string, { discount: { id: string } | null; userErrors: { message: string }[] }>, Record<string, unknown>>(gql, variables);
      const payload = data[mutationName];
      if (payload.userErrors.length > 0) {
        setFormError(payload.userErrors[0].message);
        return;
      }
      showToast(t("discounts.saved"));
      navigate("/admin/discounts");
    } catch (reason: unknown) {
      setFormError(reason instanceof Error ? reason.message : t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  const lifecycle = async (mutationName: "discountActivate" | "discountDeactivate" | "discountDelete") => {
    setBusy(true);
    try {
      const field = mutationName === "discountDelete" ? "deletedDiscountId" : "discount { id status }";
      const gql = `mutation($id: ID!) { ${mutationName}(id: $id) { ${field} userErrors { field message code } } }`;
      const data = await requestAdminGraphQL<Record<string, { userErrors: { message: string }[] }>, { id: string }>(
        gql, { id: `gid://chilllove/Discount/${discountId}` }
      );
      const payload = data[mutationName];
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t("discounts.saved"));
      if (mutationName === "discountDelete") navigate("/admin/discounts");
      else await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  const title = t(`discounts.class.${discountClass}`);

  return (
    <Page title={isNew ? `${t("discounts.create")} — ${title}` : form.title || title}>
      <p className="cl-page-backlink">
        <Link className="cl-backlink" to="/admin/discounts">
          <ArrowLeft aria-hidden="true" size={14} />
          {t("discounts.title")}
        </Link>
      </p>
      {formError ? <p className="cl-field__error" role="alert">{formError}</p> : null}

      <Card padded>
        <h3 className="cl-section-title">{title}</h3>
        <div className="cl-segmented" role="radiogroup" aria-label={t("discounts.method")}>
          <label className={`cl-segment${form.method === "code" ? " cl-segment--active" : ""}`}>
            <input checked={form.method === "code"} disabled={!isNew} name="method"
              onChange={() => setForm({ ...form, method: "code" })} type="radio" />
            {t("discounts.method.code")}
          </label>
          <label className={`cl-segment${form.method === "automatic" ? " cl-segment--active" : ""}`}>
            <input checked={form.method === "automatic"} disabled={!isNew} name="method"
              onChange={() => setForm({ ...form, method: "automatic" })} type="radio" />
            {t("discounts.method.automatic")}
          </label>
        </div>

        {form.method === "code" ? (
          <div className="cl-sender-row">
            <TextField
              hint={t("discounts.codeHint")}
              label={t("discounts.codeLabel")}
              onChange={(event) => setForm({ ...form, code: event.target.value.toUpperCase() })}
              value={form.code}
            />
            <Button onClick={() => setForm({ ...form, code: randomCode() })}>
              {t("discounts.generateCode")}
            </Button>
          </div>
        ) : (
          <TextField
            label={t("discounts.titleLabel")}
            onChange={(event) => setForm({ ...form, title: event.target.value })}
            value={form.title}
          />
        )}
      </Card>

      {discountClass !== "shipping" ? (
        <Card padded>
          <h3 className="cl-section-title">{t("discounts.valueTitle")}</h3>
          <div className="cl-sender-row">
            <select
              aria-label={t("discounts.valueTitle")}
              className="cl-field__input"
              onChange={(event) => setForm({ ...form, valueType: event.target.value as FormState["valueType"] })}
              value={form.valueType}
            >
              <option value="percentage">{t("discounts.percentage")}</option>
              <option value="fixed_amount">{t("discounts.fixedAmount")}</option>
            </select>
            <TextField
              label={t("discounts.valueTitle")}
              labelHidden
              onChange={(event) => setForm({ ...form, valueText: event.target.value })}
              placeholder={form.valueType === "percentage" ? "10" : "100.00"}
              value={form.valueText}
            />
          </div>
        </Card>
      ) : null}

      <Card padded>
        <h3 className="cl-section-title">{t("discounts.minTitle")}</h3>
        {([ [ "none", t("discounts.minNone") ], [ "amount", t("discounts.minAmount") ],
            [ "quantity", t("discounts.minQuantity") ] ] as const).map(([ mode, label ]) => (
          <label className="cl-choice" key={mode}>
            <input checked={form.minMode === mode} name="min-mode"
              onChange={() => setForm({ ...form, minMode: mode })} type="radio" />
            <span className="cl-choice__text"><strong>{label}</strong></span>
          </label>
        ))}
        {form.minMode === "amount" ? (
          <TextField label={t("discounts.minAmount")} labelHidden
            onChange={(event) => setForm({ ...form, minAmount: event.target.value })}
            placeholder="500.00" value={form.minAmount} />
        ) : null}
        {form.minMode === "quantity" ? (
          <TextField label={t("discounts.minQuantity")} labelHidden
            onChange={(event) => setForm({ ...form, minQuantity: event.target.value })}
            placeholder="3" value={form.minQuantity} />
        ) : null}
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("discounts.usesTitle")}</h3>
        <label className="cl-choice">
          <input checked={form.limitTotal}
            onChange={(event) => setForm({ ...form, limitTotal: event.target.checked })} type="checkbox" />
          <span className="cl-choice__text"><strong>{t("discounts.limitTotal")}</strong></span>
        </label>
        {form.limitTotal ? (
          <TextField label={t("discounts.limitTotal")} labelHidden
            onChange={(event) => setForm({ ...form, usageLimit: event.target.value })}
            placeholder="100" value={form.usageLimit} />
        ) : null}
        <label className="cl-choice">
          <input checked={form.oncePerCustomer}
            onChange={(event) => setForm({ ...form, oncePerCustomer: event.target.checked })} type="checkbox" />
          <span className="cl-choice__text"><strong>{t("discounts.oncePerCustomer")}</strong></span>
        </label>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("discounts.combTitle")}</h3>
        <p className="cl-card-note">{t("discounts.combHint")}</p>
        <label className="cl-choice">
          <input checked={form.combinesProduct}
            onChange={(event) => setForm({ ...form, combinesProduct: event.target.checked })} type="checkbox" />
          <span className="cl-choice__text">
            <strong>{t("discounts.combProduct")}</strong>
            <small>{t("discounts.combMultiple")}</small>
          </span>
        </label>
        <label className="cl-choice">
          <input checked={form.combinesOrder}
            onChange={(event) => setForm({ ...form, combinesOrder: event.target.checked })} type="checkbox" />
          <span className="cl-choice__text">
            <strong>{t("discounts.combOrder")}</strong>
            <small>{t("discounts.combMultiple")}</small>
          </span>
        </label>
        {discountClass !== "shipping" ? (
          <label className="cl-choice">
            <input checked={form.combinesShipping}
              onChange={(event) => setForm({ ...form, combinesShipping: event.target.checked })} type="checkbox" />
            <span className="cl-choice__text">
              <strong>{t("discounts.combShipping")}</strong>
              <small>{t("discounts.combShippingOnly")}</small>
            </span>
          </label>
        ) : null}
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("discounts.datesTitle")}</h3>
        <div className="cl-sender-row">
          <TextField label={t("discounts.startsAt")}
            onChange={(event) => setForm({ ...form, startsAt: event.target.value })}
            type="datetime-local" value={form.startsAt.slice(0, 16)} />
          <TextField label={t("discounts.endsAt")}
            onChange={(event) => setForm({ ...form, endsAt: event.target.value })}
            type="datetime-local" value={form.endsAt.slice(0, 16)} />
        </div>
      </Card>

      <div className="cl-section-title-row">
        <span>
          {!isNew && status === "archived" ? (
            <Button disabled={busy} onClick={() => void lifecycle("discountActivate")}>{t("discounts.activate")}</Button>
          ) : null}
          {!isNew && status !== "archived" ? (
            <Button disabled={busy} onClick={() => void lifecycle("discountDeactivate")}>{t("discounts.deactivate")}</Button>
          ) : null}
          {!isNew ? (
            <Button disabled={busy} onClick={() => void lifecycle("discountDelete")} variant="critical">{t("discounts.delete")}</Button>
          ) : null}
        </span>
        <Button disabled={busy || (form.method === "code" && !form.code)}
          onClick={() => void save()} variant="primary">
          {busy ? t("settings.payments.saving") : t("common.save")}
        </Button>
      </div>
    </Page>
  );
}
