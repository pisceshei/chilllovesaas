import { ArrowLeft } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { Link, useParams } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { Page } from "../components/Page";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 通知模板編輯頁（G6 步 6；89 §1 edit 頁對位）：表單恰兩欄——Email subject＋
 * Email body (HTML)（Liquid）；Revert to default（未自訂時 disabled——89 §1 實測形）。
 * Liquid 語法錯誤由後端儲存時擋（INVALID → 訊息顯示於表單頂）。
 */
const TEMPLATE_QUERY = `
  query notificationTemplateFor {
    notificationTemplates { key subject bodyLiquid isDefault }
  }
`;

const UPDATE_MUTATION = `
  mutation notificationTemplateUpdate($key: String!, $subject: String, $bodyLiquid: String, $revertToDefault: Boolean) {
    notificationTemplateUpdate(key: $key, subject: $subject, bodyLiquid: $bodyLiquid, revertToDefault: $revertToDefault) {
      notificationTemplate { key subject bodyLiquid isDefault }
      userErrors { field message code }
    }
  }
`;

interface TemplateView {
  key: string;
  subject: string;
  bodyLiquid: string;
  isDefault: boolean;
}

interface UpdatePayload {
  notificationTemplate: TemplateView | null;
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function SettingsNotificationTemplatePage() {
  const t = useT();
  const { kind = "" } = useParams();
  const { showToast } = useToast();
  const [view, setView] = useState<TemplateView | null>(null);
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [formError, setFormError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [reverting, setReverting] = useState(false);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const data = await requestAdminGraphQL<{ notificationTemplates: TemplateView[] }, Record<string, never>>(
        TEMPLATE_QUERY, {}, signal
      );
      const row = data.notificationTemplates.find((candidate) => candidate.key === kind) ?? null;
      if (row === null) {
        setError(t("settings.notifications.unknownTemplate"));
        return;
      }
      setView(row);
      setSubject(row.subject);
      setBody(row.bodyLiquid);
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.notifications.loadFailed"));
    }
  }, [kind, t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const kindTitle =
    kind === "order_confirmation"
      ? t("settings.notifications.kind.orderConfirmation")
      : kind === "shipping_confirmation"
        ? t("settings.notifications.kind.shippingConfirmation")
        : kind === "customer_otp"
          ? t("settings.notifications.kind.customerOtp")
          : t("settings.notifications.kind.abandonedCheckout");

  const mutate = async (variables: Record<string, unknown>, successMessage: string) => {
    setBusy(true);
    setFormError(null);
    try {
      const data = await requestAdminGraphQL<{ notificationTemplateUpdate: UpdatePayload }, Record<string, unknown>>(
        UPDATE_MUTATION, { key: kind, ...variables }
      );
      const payload = data.notificationTemplateUpdate;
      if (payload.userErrors.length > 0) {
        setFormError(payload.userErrors[0].message);
        return;
      }
      const next = payload.notificationTemplate;
      if (next) {
        setView(next);
        setSubject(next.subject);
        setBody(next.bodyLiquid);
      }
      showToast(successMessage);
    } catch (reason: unknown) {
      setFormError(reason instanceof Error ? reason.message : t("settings.payments.actionFailed"));
    } finally {
      setBusy(false);
      setReverting(false);
    }
  };

  if (error) {
    return (
      <Page title={kindTitle}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!view) {
    return (
      <Page title={kindTitle}>
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      </Page>
    );
  }

  return (
    <Page title={kindTitle}>
      <p className="cl-page-backlink">
        <Link className="cl-backlink" to="/admin/settings/notifications">
          <ArrowLeft aria-hidden="true" size={14} />
          {t("settings.notifications.title")}
        </Link>
      </p>

      <Card padded>
        <p className="cl-card-note">{t("settings.notifications.liquidHint")}</p>
        {formError ? <p className="cl-field__error" role="alert">{formError}</p> : null}
        <TextField
          label={t("settings.notifications.subjectLabel")}
          onChange={(event) => setSubject(event.target.value)}
          value={subject}
        />
        <div className="cl-field">
          <label className="cl-field__label" htmlFor="notification-body">
            {t("settings.notifications.bodyLabel")}
          </label>
          <textarea
            className="cl-field__input cl-field__textarea cl-code-textarea"
            id="notification-body"
            onChange={(event) => setBody(event.target.value)}
            rows={18}
            spellCheck={false}
            value={body}
          />
        </div>
        <div className="cl-section-title-row">
          <Button
            disabled={busy || view.isDefault}
            onClick={() => setReverting(true)}
          >
            {t("settings.notifications.revert")}
          </Button>
          <Button disabled={busy} onClick={() => void mutate({ subject, bodyLiquid: body }, t("settings.notifications.saved"))} variant="primary">
            {busy ? t("settings.payments.saving") : t("common.save")}
          </Button>
        </div>
      </Card>

      <ConfirmDialog
        busy={busy}
        confirmLabel={t("settings.notifications.revert")}
        message={t("settings.notifications.revertMessage")}
        onCancel={() => setReverting(false)}
        onConfirm={() => void mutate({ revertToDefault: true }, t("settings.notifications.reverted"))}
        open={reverting}
        title={t("settings.notifications.revertTitle")}
      />
    </Page>
  );
}
