import { AlertTriangle, ChevronRight, CreditCard, Wallet } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";

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
  }
`;

export interface ProviderRow {
  provider: string;
  environment: string;
  status: string;
  apiSecretFingerprint: string | null;
  enabledMethods: string[];
}

interface ProvidersData {
  shopPaymentProviders: ProviderRow[];
}

export function SettingsPaymentsPage() {
  const t = useT();
  const [data, setData] = useState<ProvidersData | null>(null);
  const [error, setError] = useState<string | null>(null);

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

  const providerBadge = (row: ProviderRow | undefined) =>
    row?.apiSecretFingerprint ? (
      <Badge progress="full" tone="success">{t("settings.payments.configured")}</Badge>
    ) : (
      <Badge progress="full" tone="default">{t("settings.payments.unconfigured")}</Badge>
    );

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
          <Link to="/admin/settings/payments/paypal">
            <Button variant="secondary">{t("settings.payments.manage")}</Button>
          </Link>
        </div>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.configSection")}</h3>
        <ul className="cl-config-list">
          <li className="cl-config-list__row">
            <span className="cl-provider-row__text">
              <strong>{t("settings.payments.captureMethod")}</strong>
              <small>{t("settings.payments.captureCurrent")}</small>
            </span>
            <ChevronRight aria-hidden="true" className="cl-config-list__chevron" size={16} />
          </li>
          <li aria-disabled="true" className="cl-config-list__row cl-config-list__row--soon">
            <span className="cl-provider-row__text">
              <strong>{t("settings.payments.manualMethods")}</strong>
              <small>{t("settings.payments.manualMethodsDesc")}</small>
            </span>
            <Badge progress="full" tone="default">{t("settings.payments.comingSoon")}</Badge>
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
    </Page>
  );
}
