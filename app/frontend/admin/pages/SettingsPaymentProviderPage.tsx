import { ArrowLeft, CreditCard } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { SwitchRow } from "./ProductDetailPage";

/**
 * provider 詳情頁（G6-3；形態照本尊 Airwallex alternative-provider 頁——digest §F）：
 * 標題＋狀態 badge → About 卡 → 憑證卡 → **逐 method toggle 清單**（字典＝平台層
 * `pspMethodDictionary` query，白名單＝租戶列 enabled_methods）→ Test mode → Save。
 *
 * 🔴 祕密欄 write-only（37 §6.3）：留空＝省略參數＝保持不變；只回指紋。
 */
const DETAIL_QUERY = `
  query shopPaymentProviderDetail($provider: String!) {
    shopPaymentProviders {
      provider environment status clientId webhookId
      apiSecretFingerprint webhookSecretFingerprint enabledMethods
    }
    pspMethodDictionary(provider: $provider) { code label }
  }
`;

const SET_MUTATION = `
  mutation shopPaymentProviderSet($provider: String!, $environment: String,
      $clientId: String, $apiSecret: String, $webhookSecret: String, $webhookId: String,
      $enabledMethods: [String!]) {
    shopPaymentProviderSet(provider: $provider, environment: $environment,
        clientId: $clientId, apiSecret: $apiSecret, webhookSecret: $webhookSecret,
        webhookId: $webhookId, enabledMethods: $enabledMethods) {
      shopPaymentProvider { provider }
      userErrors { field message code }
    }
  }
`;

interface ProviderRow {
  provider: string;
  environment: string;
  status: string;
  clientId: string | null;
  webhookId: string | null;
  apiSecretFingerprint: string | null;
  webhookSecretFingerprint: string | null;
  enabledMethods: string[];
}

interface DetailData {
  shopPaymentProviders: ProviderRow[];
  pspMethodDictionary: { code: string; label: string }[];
}

interface SetPayload {
  shopPaymentProvider: { provider: string } | null;
  userErrors: { field: string[] | null; message: string; code: string }[];
}

const BRANDS: Record<string, { brand: string; aboutKey: string; secretLabelKey: string; hasWebhookSecret: boolean; hasWebhookId: boolean }> = {
  airwallex: {
    brand: "Airwallex",
    aboutKey: "settings.payments.airwallex.about",
    secretLabelKey: "settings.payments.airwallex.apiKey",
    hasWebhookSecret: true,
    hasWebhookId: false,
  },
  paypal: {
    brand: "PayPal",
    aboutKey: "settings.payments.paypal.about",
    secretLabelKey: "settings.payments.paypal.secret",
    hasWebhookSecret: false,
    hasWebhookId: true,
  },
};

export function SettingsPaymentProviderPage() {
  const t = useT();
  const { showToast } = useToast();
  const params = useParams();
  const code = String(params.provider ?? "");
  const meta = BRANDS[code];

  const [data, setData] = useState<DetailData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [clientId, setClientId] = useState("");
  const [apiSecret, setApiSecret] = useState("");
  const [webhookSecret, setWebhookSecret] = useState("");
  const [webhookId, setWebhookId] = useState("");
  const [sandbox, setSandbox] = useState(true);
  const [methods, setMethods] = useState<string[]>([]);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<DetailData, { provider: string }>(DETAIL_QUERY, { provider: code }, signal);
      setData(result);
      const row = result.shopPaymentProviders.find((item) => item.provider === code);
      setClientId(row?.clientId ?? "");
      setWebhookId(row?.webhookId ?? "");
      setSandbox(row ? row.environment === "sandbox" : true);
      setMethods(row?.enabledMethods ?? []);
      setApiSecret("");
      setWebhookSecret("");
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.payments.loadFailed"));
    }
  }, [code, t]);

  useEffect(() => {
    if (!meta) return; // 未知 provider：不打 API，直接渲染錯誤卡
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load, meta]);

  const save = useCallback(async () => {
    if (saving) return;
    setSaving(true);
    try {
      const variables: Record<string, unknown> = {
        provider: code,
        environment: sandbox ? "sandbox" : "production",
        clientId,
        webhookId,
        enabledMethods: methods,
      };
      // 🔴 write-only：留空＝省略參數＝保持既有祕密（不得送空字串——那是清空協定）。
      if (apiSecret) variables.apiSecret = apiSecret;
      if (webhookSecret) variables.webhookSecret = webhookSecret;
      const result = await requestAdminGraphQL<{ shopPaymentProviderSet: SetPayload }, Record<string, unknown>>(
        SET_MUTATION,
        variables,
      );
      const payload = result.shopPaymentProviderSet;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t("settings.payments.saved"));
      await load();
    } catch (reason: unknown) {
      showToast(
        reason instanceof AdminGraphQLError || reason instanceof Error
          ? reason.message
          : t("settings.payments.actionFailed"),
      );
    } finally {
      setSaving(false);
    }
  }, [apiSecret, clientId, code, load, methods, sandbox, saving, showToast, t, webhookId, webhookSecret]);

  if (!meta) {
    return (
      <Page title={t("settings.payments.title")}>
        <Card padded>
          <p className="cl-card-note">{t("settings.payments.unknownProvider")}</p>
          <Link to="/admin/settings/payments"><Button>{t("common.back")}</Button></Link>
        </Card>
      </Page>
    );
  }

  if (error) {
    return (
      <Page title={meta.brand}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={meta.brand}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  const row = data.shopPaymentProviders.find((item) => item.provider === code);
  const configured = Boolean(row?.apiSecretFingerprint);
  const secretHint = row?.apiSecretFingerprint
    ? t("settings.payments.secretStored").replace("{fingerprint}", row.apiSecretFingerprint)
    : t("settings.payments.secretUnset");
  const webhookSecretHint = row?.webhookSecretFingerprint
    ? t("settings.payments.secretStored").replace("{fingerprint}", row.webhookSecretFingerprint)
    : t("settings.payments.secretUnset");

  return (
    <Page
      actions={
        <Button loading={saving} loadingLabel={t("settings.payments.saving")} onClick={() => void save()} variant="primary">
          {t("settings.payments.save")}
        </Button>
      }
      title={meta.brand}
      width="detail"
    >
      <div className="cl-provider-back">
        <Link className="cl-provider-back__link" to="/admin/settings/payments">
          <ArrowLeft aria-hidden="true" size={14} /> {t("settings.payments.backToList")}
        </Link>
        <Badge progress="full" tone={configured ? "success" : "default"}>
          {configured ? t("settings.payments.configured") : t("settings.payments.unconfigured")}
        </Badge>
      </div>

      <Card padded>
        <h3 className="cl-section-title"><CreditCard aria-hidden="true" size={15} /> {t("settings.payments.aboutTitle")}</h3>
        <p className="cl-card-note">{t(meta.aboutKey)}</p>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.credentialsTitle")}</h3>
        <SwitchRow
          checked={sandbox}
          hint={t("settings.payments.testModeHint")}
          label={t("settings.payments.testMode")}
          onChange={setSandbox}
        />
        <TextField
          autoComplete="off"
          label={t("settings.payments.clientId")}
          onChange={(event) => setClientId(event.target.value)}
          value={clientId}
        />
        <TextField
          autoComplete="new-password"
          hint={secretHint}
          label={t(meta.secretLabelKey)}
          onChange={(event) => setApiSecret(event.target.value)}
          type="password"
          value={apiSecret}
        />
        {meta.hasWebhookSecret ? (
          <TextField
            autoComplete="new-password"
            hint={webhookSecretHint}
            label={t("settings.payments.webhookSecret")}
            onChange={(event) => setWebhookSecret(event.target.value)}
            type="password"
            value={webhookSecret}
          />
        ) : null}
        {meta.hasWebhookId ? (
          <TextField
            autoComplete="off"
            label={t("settings.payments.webhookId")}
            onChange={(event) => setWebhookId(event.target.value)}
            value={webhookId}
          />
        ) : null}
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.payments.methodsTitle")}</h3>
        <p className="cl-card-note">{t("settings.payments.methodsHint")}</p>
        {data.pspMethodDictionary.map((entry) => (
          <SwitchRow
            checked={methods.includes(entry.code)}
            key={entry.code}
            label={entry.label}
            onChange={(next) =>
              setMethods((previous) =>
                next ? [ ...previous, entry.code ] : previous.filter((item) => item !== entry.code))
            }
          />
        ))}
      </Card>
    </Page>
  );
}
