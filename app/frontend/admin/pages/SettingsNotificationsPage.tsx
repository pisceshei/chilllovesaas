import { Bell } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link } from "react-router-dom";
import { ChevronRight } from "lucide-react";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 設定 › 通知（G6 步 6；docs/research/89 §1 對位）：
 * ①Sender email 欄（helper 逐字譯；空字串儲存＝清空回平台預設）
 * ②Customer notifications 模板清單（v1 三支；點入編輯頁）。
 * ⚪ Staff notifications／Fulfillment request／Webhooks 入口隨後續步驟。
 */
const NOTIFICATIONS_QUERY = `
  query notificationSettings {
    notificationSenderEmail
    notificationTemplates { key subject isDefault }
    webhookTopics
    webhookSubscriptions(first: 50) {
      nodes { id topic callbackUrl status failureCount }
    }
  }
`;

const WEBHOOK_CREATE_MUTATION = `
  mutation webhookSubscriptionCreate($topic: String!, $callbackUrl: String!) {
    webhookSubscriptionCreate(topic: $topic, callbackUrl: $callbackUrl) {
      secret
      webhookSubscription { id topic callbackUrl status failureCount }
      userErrors { field message code }
    }
  }
`;

const WEBHOOK_DELETE_MUTATION = `
  mutation webhookSubscriptionDelete($id: ID!) {
    webhookSubscriptionDelete(id: $id) {
      deletedId
      userErrors { field message code }
    }
  }
`;

const SENDER_MUTATION = `
  mutation notificationSenderEmailUpdate($senderEmail: String!) {
    notificationSenderEmailUpdate(senderEmail: $senderEmail) {
      senderEmail
      userErrors { field message code }
    }
  }
`;

interface TemplateRow {
  key: string;
  subject: string;
  isDefault: boolean;
}

interface WebhookRow {
  id: string;
  topic: string;
  callbackUrl: string;
  status: string;
  failureCount: number;
}

interface SettingsData {
  notificationSenderEmail: string | null;
  notificationTemplates: TemplateRow[];
  webhookTopics?: string[];
  webhookSubscriptions?: { nodes: WebhookRow[] };
}

export function SettingsNotificationsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<SettingsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [senderDraft, setSenderDraft] = useState("");
  const [busy, setBusy] = useState(false);
  // 20b：webhooks 卡（44:447——webhook 歸通知 IA）
  const [webhookTopic, setWebhookTopic] = useState("");
  const [webhookUrl, setWebhookUrl] = useState("");
  const [oneTimeSecret, setOneTimeSecret] = useState<string | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<SettingsData, Record<string, never>>(NOTIFICATIONS_QUERY, {}, signal);
      setData(result);
      setSenderDraft(result.notificationSenderEmail ?? "");
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.notifications.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const saveSender = async () => {
    setBusy(true);
    try {
      const result = await requestAdminGraphQL<{ notificationSenderEmailUpdate: {
        senderEmail: string | null;
        userErrors: { field: string[] | null; message: string; code: string }[];
      } }, { senderEmail: string }>(SENDER_MUTATION, { senderEmail: senderDraft });
      const payload = result.notificationSenderEmailUpdate;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t("settings.notifications.senderSaved"));
      await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
    }
  };

  const createWebhook = async () => {
    if (!webhookTopic || !webhookUrl) return;
    setBusy(true);
    try {
      const result = await requestAdminGraphQL<{ webhookSubscriptionCreate: {
        secret: string | null;
        webhookSubscription: WebhookRow | null;
        userErrors: { message: string; code: string }[];
      } }, { topic: string; callbackUrl: string }>(WEBHOOK_CREATE_MUTATION,
        { topic: webhookTopic, callbackUrl: webhookUrl });
      const payload = result.webhookSubscriptionCreate;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      // 🔴 secret 一次性可見（讀面無此欄）——顯示直到使用者關閉
      setOneTimeSecret(payload.secret);
      setWebhookUrl("");
      showToast(t("settings.webhooks.created"));
      void load();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("settings.webhooks.failed"));
    } finally {
      setBusy(false);
    }
  };

  const deleteWebhook = async (id: string) => {
    setBusy(true);
    try {
      const result = await requestAdminGraphQL<{ webhookSubscriptionDelete: {
        deletedId: string | null;
        userErrors: { message: string }[];
      } }, { id: string }>(WEBHOOK_DELETE_MUTATION, { id });
      if (result.webhookSubscriptionDelete.userErrors.length > 0) {
        showToast(result.webhookSubscriptionDelete.userErrors[0].message);
        return;
      }
      showToast(t("settings.webhooks.deleted"));
      void load();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("settings.webhooks.failed"));
    } finally {
      setBusy(false);
    }
  };

  const kindTitle = (kind: string) =>
    kind === "order_confirmation"
      ? t("settings.notifications.kind.orderConfirmation")
      : kind === "shipping_confirmation"
        ? t("settings.notifications.kind.shippingConfirmation")
        : kind === "customer_otp"
          ? t("settings.notifications.kind.customerOtp")
          : t("settings.notifications.kind.abandonedCheckout");

  const kindDesc = (kind: string) =>
    kind === "order_confirmation"
      ? t("settings.notifications.kindDesc.orderConfirmation")
      : kind === "shipping_confirmation"
        ? t("settings.notifications.kindDesc.shippingConfirmation")
        : kind === "customer_otp"
          ? t("settings.notifications.kindDesc.customerOtp")
          : t("settings.notifications.kindDesc.abandonedCheckout");

  if (error) {
    return (
      <Page title={t("settings.notifications.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("settings.notifications.title")}>
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      </Page>
    );
  }

  return (
    <Page title={t("settings.notifications.title")}>
      <Card padded>
        <h3 className="cl-section-title">{t("settings.notifications.senderTitle")}</h3>
        <p className="cl-card-note">{t("settings.notifications.senderHint")}</p>
        <div className="cl-sender-row">
          <TextField
            label={t("settings.notifications.senderTitle")}
            labelHidden
            onChange={(event) => setSenderDraft(event.target.value)}
            placeholder="no-reply@example.com"
            type="email"
            value={senderDraft}
          />
          <Button disabled={busy} onClick={() => void saveSender()} variant="primary">
            {busy ? t("settings.payments.saving") : t("common.save")}
          </Button>
        </div>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.notifications.customerSection")}</h3>
        <ul className="cl-config-list">
          {data.notificationTemplates.map((row) => (
            <li className="cl-config-list__row" key={row.key}>
              <Link className="cl-config-list__button" to={`/admin/settings/notifications/${row.key}`}>
                <Bell aria-hidden="true" size={16} />
                <span className="cl-provider-row__text">
                  <strong>{kindTitle(row.key)}</strong>
                  <small>{kindDesc(row.key)}</small>
                </span>
                {row.isDefault ? null : (
                  <Badge progress="full" tone="attention">{t("settings.notifications.customized")}</Badge>
                )}
                <ChevronRight aria-hidden="true" className="cl-config-list__chevron" size={16} />
              </Link>
            </li>
          ))}
        </ul>
      </Card>

      <Card padded>
        <h3 className="cl-section-title">{t("settings.webhooks.title")}</h3>
        <p className="cl-card-note">{t("settings.webhooks.hint")}</p>
        {oneTimeSecret ? (
          <p className="cl-webhook-secret">
            {t("settings.webhooks.secretOnce")}<code>{oneTimeSecret}</code>
            <Button onClick={() => setOneTimeSecret(null)} size="small" variant="ghost">
              {t("settings.webhooks.secretDismiss")}
            </Button>
          </p>
        ) : null}
        <ul className="cl-config-list" data-testid="webhook-list">
          {(data.webhookSubscriptions?.nodes ?? []).map((row) => (
            <li className="cl-config-list__row" key={row.id}>
              <span className="cl-provider-row__text">
                <strong>{row.topic}</strong>
                <small>{row.callbackUrl}</small>
              </span>
              <Badge tone={row.status === "active" ? "success" : "critical"}>
                {row.status}{row.failureCount > 0 ? ` (${row.failureCount})` : ""}
              </Badge>
              <Button disabled={busy} onClick={() => void deleteWebhook(row.id)} size="small" variant="ghost">
                {t("common.delete")}
              </Button>
            </li>
          ))}
        </ul>
        <div className="cl-sender-row">
          <label className="cl-field__label" htmlFor="webhook-topic">{t("settings.webhooks.topic")}</label>
          <select
            className="cl-field__input"
            id="webhook-topic"
            onChange={(event) => setWebhookTopic(event.target.value)}
            value={webhookTopic}
          >
            <option value="">{t("settings.webhooks.topicPlaceholder")}</option>
            {(data.webhookTopics ?? []).map((topic) => (
              <option key={topic} value={topic}>{topic}</option>
            ))}
          </select>
          <TextField
            label={t("settings.webhooks.url")}
            labelHidden
            onChange={(event) => setWebhookUrl(event.target.value)}
            placeholder="https://example.com/webhooks"
            value={webhookUrl}
          />
          <Button disabled={busy || !webhookTopic || !webhookUrl} onClick={() => void createWebhook()}>
            {t("settings.webhooks.add")}
          </Button>
        </div>
      </Card>
    </Page>
  );
}
