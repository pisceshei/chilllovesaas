import { AlertTriangle, ChevronRight, CreditCard, Wallet } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Modal } from "../components/Modal";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 設定 › 付款——主頁（G6-3；佈局照 docs/research/86 §1 實測結構）：
 * ①test-mode 橫幅（任一 provider 在 sandbox 時；對位本尊 dev 店橫幅）
 * ②主收單 provider 卡（本尊 Shopify Payments 卡位 → 我方＝Airwallex）
 * ③Additional payment providers（PayPal 卡）
 * ④Payment configuration 清單（capture／manual methods／customizations——
 *   後兩者功能隨 G6-3 本體，列出以保 86 §1 版面完整，標「即將推出」不可點）。
 * 憑證與逐方法 toggle 在 provider 詳情頁（SettingsPaymentProviderPage）。
 */
const PROVIDERS_QUERY = `
  query shopPaymentProviderList {
    shopPaymentProviders {
      provider environment status apiSecretFingerprint enabledMethods
    }
    paymentCaptureMethod
  }
`;

const CAPTURE_MUTATION = `
  mutation paymentCaptureMethodUpdate($captureMethod: String!) {
    paymentCaptureMethodUpdate(captureMethod: $captureMethod) {
      paymentCaptureMethod
      userErrors { field message code }
    }
  }
`;

const PROVIDER_ACTIVATE_MUTATION = `
  mutation shopPaymentProviderActivate($provider: String!) {
    shopPaymentProviderActivate(provider: $provider) {
      shopPaymentProvider { provider status }
      userErrors { field message code }
    }
  }
`;

const PROVIDER_DEACTIVATE_MUTATION = `
  mutation shopPaymentProviderDeactivate($provider: String!) {
    shopPaymentProviderDeactivate(provider: $provider) {
      shopPaymentProvider { provider status }
      userErrors { field message code }
    }
  }
`;

/** capture modal 三值（86 §2 逐字對位；Plus 專屬第四值不展示——後端同樣拒收）。 */
const CAPTURE_OPTIONS = [
  { value: "automatic_at_checkout", labelKey: "settings.payments.captureAuto", descKey: "settings.payments.captureAutoDesc" },
  { value: "automatic_after_fulfilled", labelKey: "settings.payments.captureFulfill", descKey: "settings.payments.captureFulfillDesc" },
  { value: "manual", labelKey: "settings.payments.captureManual", descKey: "settings.payments.captureManualDesc" }
] as const;

export interface ProviderRow {
  provider: string;
  environment: string;
  status: string;
  apiSecretFingerprint: string | null;
  enabledMethods: string[];
}

interface ProvidersData {
  shopPaymentProviders: ProviderRow[];
  paymentCaptureMethod: string;
}

interface ProviderMutationPayload {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function SettingsPaymentsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<ProvidersData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [captureOpen, setCaptureOpen] = useState(false);
  const [captureDraft, setCaptureDraft] = useState<string>("automatic_at_checkout");
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setData(await requestAdminGraphQL<ProvidersData, Record<string, never>>(PROVIDERS_QUERY, {}, signal));
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

  if (error) {
    return (
      <Page title={t("settings.payments.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("settings.payments.title")}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  const rows = data.shopPaymentProviders;
  const rowFor = (code: string) => rows.find((row) => row.provider === code);
  const sandboxActive = rows.some((row) => row.environment === "sandbox" && row.apiSecretFingerprint);

  // 三態徽章：active（結帳頁會出現）＞ configured（憑證在但未啟用）＞ unconfigured。
  const providerBadge = (row: ProviderRow | undefined) =>
    row?.status === "active" ? (
      <Badge progress="full" tone="success">{t("settings.payments.active")}</Badge>
    ) : row?.apiSecretFingerprint ? (
      <Badge progress="half" tone="attention">{t("settings.payments.configured")}</Badge>
    ) : (
      <Badge progress="full" tone="default">{t("settings.payments.unconfigured")}</Badge>
    );

  const saveCapture = async () => {
    setBusy(true);
    try {
      const result = await requestAdminGraphQL<{ paymentCaptureMethodUpdate: ProviderMutationPayload }, { captureMethod: string }>(
        CAPTURE_MUTATION, { captureMethod: captureDraft }
      );
      const payload = result.paymentCaptureMethodUpdate;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      setCaptureOpen(false);
      showToast(t("settings.payments.captureSaved"));
      await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  const toggleProvider = async (code: string, nextActive: boolean) => {
    setBusy(true);
    try {
      const mutation = nextActive ? PROVIDER_ACTIVATE_MUTATION : PROVIDER_DEACTIVATE_MUTATION;
      const key = nextActive ? "shopPaymentProviderActivate" : "shopPaymentProviderDeactivate";
      const result = await requestAdminGraphQL<Record<string, ProviderMutationPayload>, { provider: string }>(
        mutation, { provider: code }
      );
      const payload = result[key];
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t(nextActive ? "settings.payments.activated" : "settings.payments.deactivated"));
      await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  // 啟用鈕只在「憑證在」時出現（後端 activate 的前置＝指紋非空；沒憑證先去 Manage）。
  const providerActionButton = (code: string) => {
    const row = rowFor(code);
    if (!row?.apiSecretFingerprint) return null;
    return row.status === "active" ? (
      <Button disabled={busy} onClick={() => void toggleProvider(code, false)} variant="secondary">
        {t("settings.payments.deactivate")}
      </Button>
    ) : (
      <Button disabled={busy} onClick={() => void toggleProvider(code, true)} variant="secondary">
        {t("settings.payments.activate")}
      </Button>
    );
  };

  const captureLabel = CAPTURE_OPTIONS.find((option) => option.value === data.paymentCaptureMethod);

  return (
    <Page title={t("settings.payments.title")}>
      {sandboxActive ? (
        <div className="cl-banner cl-banner--warning" role="status">
          <AlertTriangle aria-hidden="true" size={16} />
          <span>{t("settings.payments.testBanner")}</span>
        </div>
      ) : null}

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.primarySection")}</h3>
        <div className="cl-provider-row">
          <span className="cl-provider-row__icon"><CreditCard aria-hidden="true" size={20} /></span>
          <span className="cl-provider-row__text">
            <strong>Airwallex</strong>
            <small>{t("settings.payments.airwallex.desc")}</small>
            {rowFor("airwallex")?.enabledMethods.length ? (
              <span className="cl-method-chips">
                {rowFor("airwallex")!.enabledMethods.map((code) => (
                  <span className="cl-method-chip" key={code}>{code}</span>
                ))}
              </span>
            ) : null}
          </span>
          {providerBadge(rowFor("airwallex"))}
          {providerActionButton("airwallex")}
          <Link to="/admin/settings/payments/airwallex">
            <Button variant="primary">{t("settings.payments.manage")}</Button>
          </Link>
        </div>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.additionalSection")}</h3>
        <div className="cl-provider-row">
          <span className="cl-provider-row__icon"><Wallet aria-hidden="true" size={20} /></span>
          <span className="cl-provider-row__text">
            <strong>PayPal</strong>
            <small>{t("settings.payments.paypal.desc")}</small>
          </span>
          {providerBadge(rowFor("paypal"))}
          {providerActionButton("paypal")}
          <Link to="/admin/settings/payments/paypal">
            <Button variant="secondary">{t("settings.payments.manage")}</Button>
          </Link>
        </div>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.configSection")}</h3>
        <ul className="cl-config-list">
          <li className="cl-config-list__row">
            <button
              className="cl-config-list__button"
              onClick={() => {
                setCaptureDraft(data.paymentCaptureMethod);
                setCaptureOpen(true);
              }}
              type="button"
            >
              <span className="cl-provider-row__text">
                <strong>{t("settings.payments.captureMethod")}</strong>
                <small>{captureLabel ? t(captureLabel.labelKey) : data.paymentCaptureMethod}</small>
              </span>
              <ChevronRight aria-hidden="true" className="cl-config-list__chevron" size={16} />
            </button>
          </li>
          <li className="cl-config-list__row">
            <Link className="cl-config-list__button" to="/admin/settings/payments/manual-payment-methods">
              <span className="cl-provider-row__text">
                <strong>{t("settings.payments.manualMethods")}</strong>
                <small>{t("settings.payments.manualMethodsDesc")}</small>
              </span>
              <ChevronRight aria-hidden="true" className="cl-config-list__chevron" size={16} />
            </Link>
          </li>
          <li aria-disabled="true" className="cl-config-list__row cl-config-list__row--soon">
            <span className="cl-provider-row__text">
              <strong>{t("settings.payments.customizations")}</strong>
              <small>{t("settings.payments.customizationsDesc")}</small>
            </span>
            <Badge progress="full" tone="default">{t("settings.payments.comingSoon")}</Badge>
          </li>
        </ul>
      </Card>

      {captureOpen ? (
        <Modal
          dismissable={!busy}
          footer={
            <>
              <Button disabled={busy} onClick={() => setCaptureOpen(false)}>{t("common.cancel")}</Button>
              <Button disabled={busy} onClick={() => void saveCapture()} variant="primary">
                {busy ? t("settings.payments.saving") : t("common.save")}
              </Button>
            </>
          }
          onClose={() => setCaptureOpen(false)}
          open
          title={t("settings.payments.captureMethod")}
        >
          <p className="cl-card-note">{t("settings.payments.captureDesc")}</p>
          <div role="radiogroup">
            {CAPTURE_OPTIONS.map((option) => (
              <label className="cl-choice" key={option.value}>
                <input
                  checked={captureDraft === option.value}
                  name="capture-method"
                  onChange={() => setCaptureDraft(option.value)}
                  type="radio"
                  value={option.value}
                />
                <span className="cl-choice__text">
                  <strong>{t(option.labelKey)}</strong>
                  <small>{t(option.descKey)}</small>
                </span>
              </label>
            ))}
          </div>
        </Modal>
      ) : null}
    </Page>
  );
}
