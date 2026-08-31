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

interface SettingsData {
  notificationSenderEmail: string | null;
  notificationTemplates: TemplateRow[];
}

export function SettingsNotificationsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<SettingsData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [senderDraft, setSenderDraft] = useState("");
  const [busy, setBusy] = useState(false);

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

  const kindTitle = (kind: string) =>
    kind === "order_confirmation"
      ? t("settings.notifications.kind.orderConfirmation")
      : kind === "shipping_confirmation"
        ? t("settings.notifications.kind.shippingConfirmation")
        : t("settings.notifications.kind.abandonedCheckout");

  const kindDesc = (kind: string) =>
    kind === "order_confirmation"
      ? t("settings.notifications.kindDesc.orderConfirmation")
      : kind === "shipping_confirmation"
        ? t("settings.notifications.kindDesc.shippingConfirmation")
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
    </Page>
  );
}
