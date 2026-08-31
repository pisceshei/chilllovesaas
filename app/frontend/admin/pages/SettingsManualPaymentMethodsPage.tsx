import { ArrowLeft, Plus } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";
import { Link } from "react-router-dom";
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

/**
 * 設定 › 付款 › Manual payment methods 子頁（G6-3 步 2；docs/research/86 §3 對位）：
 * ①說明句（86 §3 逐字譯）＋「manual 單需先核准才能出貨」提示
 * ②⊕ 選單恰四值（Create custom／Bank Deposit／Money Order／COD）——
 *   已存在的內建型別從選單消失（86 §3：每店至多一列；custom 不受限）
 * ③setup 表單恰兩欄（Additional details→結帳頁；Payment instructions→下單確認頁；
 *   helper 逐字譯）＋custom 專屬 name 欄
 * ④Deactivate 確認逐字對位（設定保留、可隨時再啟用）；停用列仍列出（Inactive 徽章）。
 */
const LIST_QUERY = `
  query manualPaymentMethods {
    shopPaymentMethods {
      id methodType name additionalDetails paymentInstructions active position
    }
  }
`;

const CREATE_MUTATION = `
  mutation shopPaymentMethodCreate($methodType: String!, $name: String, $additionalDetails: String, $paymentInstructions: String) {
    shopPaymentMethodCreate(methodType: $methodType, name: $name, additionalDetails: $additionalDetails, paymentInstructions: $paymentInstructions) {
      shopPaymentMethod { id }
      userErrors { field message code }
    }
  }
`;

const UPDATE_MUTATION = `
  mutation shopPaymentMethodUpdate($id: ID!, $name: String, $additionalDetails: String, $paymentInstructions: String) {
    shopPaymentMethodUpdate(id: $id, name: $name, additionalDetails: $additionalDetails, paymentInstructions: $paymentInstructions) {
      shopPaymentMethod { id }
      userErrors { field message code }
    }
  }
`;

const ACTIVATE_MUTATION = `
  mutation shopPaymentMethodActivate($id: ID!) {
    shopPaymentMethodActivate(id: $id) {
      shopPaymentMethod { id active }
      userErrors { field message code }
    }
  }
`;

const DEACTIVATE_MUTATION = `
  mutation shopPaymentMethodDeactivate($id: ID!) {
    shopPaymentMethodDeactivate(id: $id) {
      shopPaymentMethod { id active }
      userErrors { field message code }
    }
  }
`;

interface MethodRow {
  id: string;
  methodType: string;
  name: string;
  additionalDetails: string | null;
  paymentInstructions: string | null;
  active: boolean;
  position: number;
}

interface MutationPayload {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

/** ⊕ 選單的內建三值（86 §3 DOM 逐字順序：custom 第一、內建其後）。 */
const BUILTIN_TYPES = ["bank_deposit", "money_order", "cash_on_delivery"] as const;

/** setup 表單狀態：null＝關閉；id null＝新建。 */
interface FormState {
  id: string | null;
  methodType: string;
  name: string;
  additionalDetails: string;
  paymentInstructions: string;
}

export function SettingsManualPaymentMethodsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [rows, setRows] = useState<MethodRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const [form, setForm] = useState<FormState | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [deactivating, setDeactivating] = useState<MethodRow | null>(null);
  const addButtonRef = useRef<HTMLButtonElement | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const data = await requestAdminGraphQL<{ shopPaymentMethods: MethodRow[] }, Record<string, never>>(
        LIST_QUERY, {}, signal
      );
      setRows(data.shopPaymentMethods);
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.payments.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const builtinLabel = (type: string) =>
    type === "bank_deposit"
      ? t("settings.payments.manual.bankDeposit")
      : type === "money_order"
        ? t("settings.payments.manual.moneyOrder")
        : t("settings.payments.manual.cod");

  // 86 §3：已存在的內建型別從 ⊕ 選單消失（存在即隱藏，含停用中的——那些走
  // 「Activate」不走「新增」；custom 恆可再建）。
  const availableBuiltins = BUILTIN_TYPES.filter(
    (type) => !(rows ?? []).some((row) => row.methodType === type)
  );

  const openCreate = (methodType: string) => {
    setMenuOpen(false);
    setFormError(null);
    setForm({ id: null, methodType, name: "", additionalDetails: "", paymentInstructions: "" });
  };

  const openEdit = (row: MethodRow) => {
    setFormError(null);
    setForm({
      id: row.id,
      methodType: row.methodType,
      name: row.name,
      additionalDetails: row.additionalDetails ?? "",
      paymentInstructions: row.paymentInstructions ?? ""
    });
  };

  const submitForm = async () => {
    if (!form) return;
    setBusy(true);
    setFormError(null);
    try {
      const variables: Record<string, unknown> = {
        additionalDetails: form.additionalDetails,
        paymentInstructions: form.paymentInstructions
      };
      let payload: MutationPayload;
      if (form.id) {
        variables.id = form.id;
        if (form.methodType === "custom") variables.name = form.name;
        const data = await requestAdminGraphQL<{ shopPaymentMethodUpdate: MutationPayload }, Record<string, unknown>>(
          UPDATE_MUTATION, variables
        );
        payload = data.shopPaymentMethodUpdate;
      } else {
        variables.methodType = form.methodType;
        if (form.methodType === "custom") variables.name = form.name;
        const data = await requestAdminGraphQL<{ shopPaymentMethodCreate: MutationPayload }, Record<string, unknown>>(
          CREATE_MUTATION, variables
        );
        payload = data.shopPaymentMethodCreate;
      }
      if (payload.userErrors.length > 0) {
        setFormError(payload.userErrors[0].message);
        return;
      }
      setForm(null);
      showToast(t("settings.payments.manual.saved"));
      await load();
    } catch (reason: unknown) {
      setFormError(reason instanceof Error ? reason.message : t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  const toggleActive = async (row: MethodRow, nextActive: boolean) => {
    setBusy(true);
    try {
      const mutation = nextActive ? ACTIVATE_MUTATION : DEACTIVATE_MUTATION;
      const key = nextActive ? "shopPaymentMethodActivate" : "shopPaymentMethodDeactivate";
      const data = await requestAdminGraphQL<Record<string, MutationPayload>, { id: string }>(mutation, { id: row.id });
      const payload = data[key];
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t(nextActive ? "settings.payments.manual.activated" : "settings.payments.manual.deactivated"));
      await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
      setDeactivating(null);
    }
  };

  if (error) {
    return (
      <Page title={t("settings.payments.manual.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  return (
    <Page title={t("settings.payments.manual.title")}>
      <p className="cl-page-backlink">
        <Link className="cl-backlink" to="/admin/settings/payments">
          <ArrowLeft aria-hidden="true" size={14} />
          {t("settings.payments.backToList")}
        </Link>
      </p>

      <Card padded>
        <div className="cl-section-title-row">
          <p className="cl-card-note">{t("settings.payments.manual.desc")}</p>
          <Button
            aria-expanded={menuOpen}
            aria-haspopup="menu"
            onClick={() => setMenuOpen((open) => !open)}
            ref={addButtonRef}
            variant="primary"
          >
            <Plus aria-hidden="true" size={14} />
            {t("settings.payments.manual.add")}
          </Button>
        </div>
        <Popover
          anchorRef={addButtonRef}
          dismissOnOutsideClick
          label={t("settings.payments.manual.add")}
          onClose={() => setMenuOpen(false)}
          open={menuOpen}
        >
          <ul className="cl-menu-list" role="menu">
            <li role="none">
              <button className="cl-menu-list__item" onClick={() => openCreate("custom")} role="menuitem" type="button">
                {t("settings.payments.manual.createCustom")}
              </button>
            </li>
            {availableBuiltins.map((type) => (
              <li key={type} role="none">
                <button className="cl-menu-list__item" onClick={() => openCreate(type)} role="menuitem" type="button">
                  {builtinLabel(type)}
                </button>
              </li>
            ))}
          </ul>
        </Popover>

        {rows === null ? (
          <p className="cl-card-note">{t("common.loading")}</p>
        ) : rows.length === 0 ? (
          <p className="cl-card-note">{t("settings.payments.manual.empty")}</p>
        ) : (
          <ul className="cl-config-list">
            {rows.map((row) => (
              <li className="cl-config-list__row" key={row.id}>
                <span className="cl-provider-row__text">
                  <strong>{row.name}</strong>
                  {row.additionalDetails ? <small>{row.additionalDetails}</small> : null}
                </span>
                {row.active ? (
                  <Badge progress="full" tone="success">{t("settings.payments.active")}</Badge>
                ) : (
                  <Badge progress="empty" tone="default">{t("settings.payments.manual.inactive")}</Badge>
                )}
                <Button disabled={busy} onClick={() => openEdit(row)} variant="ghost">
                  {t("settings.payments.manual.edit")}
                </Button>
                {row.active ? (
                  <Button disabled={busy} onClick={() => setDeactivating(row)} variant="secondary">
                    {t("settings.payments.deactivate")}
                  </Button>
                ) : (
                  <Button disabled={busy} onClick={() => void toggleActive(row, true)} variant="secondary">
                    {t("settings.payments.activate")}
                  </Button>
                )}
              </li>
            ))}
          </ul>
        )}
      </Card>

      {form ? (
        <Modal
          dismissable={!busy}
          footer={
            <>
              <Button disabled={busy} onClick={() => setForm(null)}>{t("common.cancel")}</Button>
              <Button disabled={busy || (form.methodType === "custom" && form.name.trim() === "")}
                onClick={() => void submitForm()} variant="primary">
                {busy ? t("settings.payments.saving") : t("common.save")}
              </Button>
            </>
          }
          onClose={() => setForm(null)}
          open
          title={form.methodType === "custom"
            ? t("settings.payments.manual.createCustom")
            : builtinLabel(form.methodType)}
        >
          {formError ? <p className="cl-field__error" role="alert">{formError}</p> : null}
          {form.methodType === "custom" ? (
            <TextField
              data-autofocus
              label={t("settings.payments.manual.name")}
              onChange={(event) => setForm({ ...form, name: event.target.value })}
              value={form.name}
            />
          ) : null}
          <div className="cl-field">
            <label className="cl-field__label" htmlFor="manual-additional-details">
              {t("settings.payments.manual.additionalDetails")}
            </label>
            <textarea
              className="cl-field__input cl-field__textarea"
              id="manual-additional-details"
              onChange={(event) => setForm({ ...form, additionalDetails: event.target.value })}
              rows={3}
              value={form.additionalDetails}
            />
            <p className="cl-field__hint">{t("settings.payments.manual.additionalDetailsHint")}</p>
          </div>
          <div className="cl-field">
            <label className="cl-field__label" htmlFor="manual-payment-instructions">
              {t("settings.payments.manual.paymentInstructions")}
            </label>
            <textarea
              className="cl-field__input cl-field__textarea"
              id="manual-payment-instructions"
              onChange={(event) => setForm({ ...form, paymentInstructions: event.target.value })}
              rows={3}
              value={form.paymentInstructions}
            />
            <p className="cl-field__hint">{t("settings.payments.manual.paymentInstructionsHint")}</p>
          </div>
        </Modal>
      ) : null}

      <ConfirmDialog
        busy={busy}
        confirmLabel={t("settings.payments.deactivate")}
        message={deactivating
          ? t("settings.payments.manual.deactivateMessage", { name: deactivating.name })
          : ""}
        onCancel={() => setDeactivating(null)}
        onConfirm={() => { if (deactivating) void toggleActive(deactivating, false); }}
        open={deactivating !== null}
        title={deactivating ? t("settings.payments.manual.deactivateTitle", { name: deactivating.name }) : ""}
      />
    </Page>
  );
}
