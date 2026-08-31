import { CreditCard } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
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
 * 設定 › 付款（G6-3 前半切片：provider 憑證入口）。
 *
 * 🔴 **祕密欄 write-only（37 §6.3）**：後端永不回明文，只回 SHA-256 前 16 hex 指紋；
 * 本頁祕密輸入框恆為空、placeholder 顯示指紋，**留空＝保持不變**（省略參數＝不變，
 * 見 shopPaymentProviderSet 的協定）。本切片不提供「清空祕密」（G6-3 隨完整頁補）。
 *
 * 86 號 §1 的完整 1:1 佈局（Shopify Payments 卡位／Add provider／capture modal…）
 * 與逐方法 toggle 隨 G6-3 落；本頁先承載兩個直連 provider 的憑證與 test mode。
 */
const PROVIDERS_QUERY = `
  query shopPaymentProviderList {
    shopPaymentProviders {
      provider environment status clientId webhookId
      apiSecretFingerprint webhookSecretFingerprint
    }
  }
`;

const SET_MUTATION = `
  mutation shopPaymentProviderSet($provider: String!, $environment: String,
      $clientId: String, $apiSecret: String, $webhookSecret: String, $webhookId: String) {
    shopPaymentProviderSet(provider: $provider, environment: $environment,
        clientId: $clientId, apiSecret: $apiSecret, webhookSecret: $webhookSecret, webhookId: $webhookId) {
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
}

interface ProvidersData {
  shopPaymentProviders: ProviderRow[];
}

interface SetPayload {
  shopPaymentProvider: { provider: string } | null;
  userErrors: { field: string[] | null; message: string; code: string }[];
}

/** provider 靜態字典（顯示層；值域正典＝limits psp_packs，後端 PROVIDER_UNKNOWN 把關）。 */
const PROVIDER_CARDS = [
  {
    code: "airwallex",
    brand: "Airwallex",
    secretLabelKey: "settings.payments.airwallex.apiKey",
    hasWebhookSecret: true,
    hasWebhookId: false,
  },
  {
    code: "paypal",
    brand: "PayPal",
    secretLabelKey: "settings.payments.paypal.secret",
    hasWebhookSecret: false,
    hasWebhookId: true,
  },
] as const;

interface FormState {
  clientId: string;
  apiSecret: string;
  webhookSecret: string;
  webhookId: string;
  sandbox: boolean;
}

const EMPTY_FORM: FormState = { clientId: "", apiSecret: "", webhookSecret: "", webhookId: "", sandbox: true };

export function SettingsPaymentsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<ProvidersData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [forms, setForms] = useState<Record<string, FormState>>({});

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<ProvidersData, Record<string, never>>(PROVIDERS_QUERY, {}, signal);
      setData(result);
      setForms((previous) => {
        const next: Record<string, FormState> = {};
        for (const card of PROVIDER_CARDS) {
          const row = result.shopPaymentProviders.find((item) => item.provider === card.code);
          next[card.code] = {
            ...EMPTY_FORM,
            ...previous[card.code],
            clientId: row?.clientId ?? previous[card.code]?.clientId ?? "",
            webhookId: row?.webhookId ?? previous[card.code]?.webhookId ?? "",
            // 祕密欄恆空（write-only）；環境以後端現值為準。
            apiSecret: "",
            webhookSecret: "",
            sandbox: row ? row.environment === "sandbox" : true,
          };
        }
        return next;
      });
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

  const patchForm = (code: string, patch: Partial<FormState>) => {
    setForms((previous) => ({ ...previous, [code]: { ...(previous[code] ?? EMPTY_FORM), ...patch } }));
  };

  const save = useCallback(
    async (code: string) => {
      if (busy) return;
      const form = forms[code] ?? EMPTY_FORM;
      setBusy(code);
      try {
        const variables: Record<string, unknown> = {
          provider: code,
          environment: form.sandbox ? "sandbox" : "production",
          clientId: form.clientId,
          webhookId: form.webhookId,
        };
        // 🔴 write-only：留空＝省略參數＝保持既有祕密（不得送空字串——那是清空協定）。
        if (form.apiSecret) variables.apiSecret = form.apiSecret;
        if (form.webhookSecret) variables.webhookSecret = form.webhookSecret;
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
        setBusy(null);
      }
    },
    [busy, forms, load, showToast, t],
  );

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

  return (
    <Page title={t("settings.payments.title")}>
      <Card padded>
        <p className="cl-card-note">{t("settings.payments.hint")}</p>
      </Card>
      {PROVIDER_CARDS.map((card) => {
        const row = data.shopPaymentProviders.find((item) => item.provider === card.code);
        const form = forms[card.code] ?? EMPTY_FORM;
        const configured = Boolean(row?.apiSecretFingerprint);
        const secretHint = row?.apiSecretFingerprint
          ? t("settings.payments.secretStored").replace("{fingerprint}", row.apiSecretFingerprint)
          : t("settings.payments.secretUnset");
        const webhookSecretHint = row?.webhookSecretFingerprint
          ? t("settings.payments.secretStored").replace("{fingerprint}", row.webhookSecretFingerprint)
          : t("settings.payments.secretUnset");
        return (
          <Card key={card.code} padded>
            <div className="cl-provider-head">
              <h3>
                <CreditCard aria-hidden="true" size={16} /> {card.brand}
              </h3>
              <Badge progress="full" tone={configured ? "success" : "default"}>
                {configured ? t("settings.payments.configured") : t("settings.payments.unconfigured")}
              </Badge>
            </div>
            <SwitchRow
              checked={form.sandbox}
              hint={t("settings.payments.testModeHint")}
              label={t("settings.payments.testMode")}
              onChange={(next) => patchForm(card.code, { sandbox: next })}
            />
            <TextField
              autoComplete="off"
              label={t("settings.payments.clientId")}
              onChange={(event) => patchForm(card.code, { clientId: event.target.value })}
              value={form.clientId}
            />
            <TextField
              autoComplete="new-password"
              hint={secretHint}
              label={t(card.secretLabelKey)}
              onChange={(event) => patchForm(card.code, { apiSecret: event.target.value })}
              type="password"
              value={form.apiSecret}
            />
            {card.hasWebhookSecret ? (
              <TextField
                autoComplete="new-password"
                hint={webhookSecretHint}
                label={t("settings.payments.webhookSecret")}
                onChange={(event) => patchForm(card.code, { webhookSecret: event.target.value })}
                type="password"
                value={form.webhookSecret}
              />
            ) : null}
            {card.hasWebhookId ? (
              <TextField
                autoComplete="off"
                label={t("settings.payments.webhookId")}
                onChange={(event) => patchForm(card.code, { webhookId: event.target.value })}
                value={form.webhookId}
              />
            ) : null}
            <Button disabled={busy !== null} loading={busy === card.code} onClick={() => void save(card.code)} variant="primary">
              {t("settings.payments.save")}
            </Button>
          </Card>
        );
      })}
    </Page>
  );
}
