import { Download, Upload } from "lucide-react";
import { useRef, useState } from "react";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 翻譯 CSV 匯出／匯入（ML-5b；docs/specs/67 §E.6）。
 *
 * 🔴 兩步匯入（`i18n.import.preview_required`）：先預覽四個數字，商家看過才 apply。
 * 「覆寫」雖然是明示動作，但爆炸半徑仍是整份檔案——**明示只解決『是不是故意的』，
 * 沒有解決『知不知道有多大』**，所以預覽把 新增／覆寫／清空／不動 分開計數。
 *
 * 🔴 檔案通道走 HTTP（下載 Content-Disposition／上傳 multipart），不走 GraphQL——
 * 資料讀寫仍只走 GraphQL（D5），這兩支是檔案通道不是資料 API。
 */
interface LocaleRef {
  tag: string;
  endonym: string;
}

interface PreviewResult {
  created: number;
  updated: number;
  cleared: number;
  skipped: number;
  digestMismatch: number;
  applied: boolean;
  errors: { line: number; message: string; code: string }[];
}

function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
}

export function TranslationCsvCard({ locales }: { locales: readonly LocaleRef[] }) {
  const t = useT();
  const { showToast } = useToast();
  const fileRef = useRef<HTMLInputElement>(null);
  const [exportLocale, setExportLocale] = useState("");
  const [overwrite, setOverwrite] = useState(false);
  const [preview, setPreview] = useState<PreviewResult | null>(null);
  const [busy, setBusy] = useState(false);

  const send = async (path: string) => {
    const file = fileRef.current?.files?.[0];
    if (!file) {
      showToast(t("settings.languages.noFile"));
      return null;
    }
    const body = new FormData();
    body.append("file", file);
    body.append("overwrite_existing", String(overwrite));
    const response = await fetch(path, {
      method: "POST",
      body,
      headers: { "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
    });
    return (await response.json()) as PreviewResult;
  };

  const run = async (path: string, done?: () => void) => {
    if (busy) return;
    setBusy(true);
    try {
      const result = await send(path);
      if (!result) return;
      setPreview(result);
      if (result.errors.length > 0) {
        showToast(t("settings.languages.importErrors", { count: result.errors.length }));
      }
      done?.();
    } finally {
      setBusy(false);
    }
  };

  return (
    <Card padded>
      <h3>{t("settings.languages.csv")}</h3>
      <p className="cl-card-note">{t("settings.languages.csvHint")}</p>

      <div className="cl-csv-row">
        <select
          aria-label={t("settings.languages.exportCsv")}
          className="cl-field__input"
          onChange={(event) => setExportLocale(event.target.value)}
          value={exportLocale}
        >
          <option value="">{t("settings.languages.exportAll")}</option>
          {locales.map((locale) => (
            <option key={locale.tag} lang={locale.tag} value={locale.tag}>
              {locale.endonym}
            </option>
          ))}
        </select>
        <Button
          onClick={() => {
            const query = exportLocale ? `?locales=${encodeURIComponent(exportLocale)}` : "";
            window.location.assign(`/admin/translations/export${query}`);
          }}
        >
          <Download aria-hidden="true" size={14} /> {t("settings.languages.exportCsv")}
        </Button>
      </div>

      <div className="cl-csv-row">
        <input
          aria-label={t("settings.languages.chooseFile")}
          accept=".csv,text/csv"
          className="cl-field__input"
          onChange={() => setPreview(null)}
          ref={fileRef}
          type="file"
        />
        <Button disabled={busy} onClick={() => void run("/admin/translations/preview")}>
          <Upload aria-hidden="true" size={14} /> {t("settings.languages.preview")}
        </Button>
      </div>

      <label className="cl-checkrow">
        <input checked={overwrite} onChange={(event) => setOverwrite(event.target.checked)} type="checkbox" />
        {t("settings.languages.overwrite")}
      </label>
      <p className="cl-field__hint">{t("settings.languages.overwriteHint")}</p>

      {preview ? (
        <div className="cl-csv-preview" role="status">
          <p>
            {t("settings.languages.previewResult", {
              created: preview.created,
              updated: preview.updated,
              cleared: preview.cleared,
              skipped: preview.skipped,
            })}
          </p>
          {preview.digestMismatch > 0 ? (
            <p className="cl-field__hint">{t("settings.languages.digestMismatch", { count: preview.digestMismatch })}</p>
          ) : null}
          {preview.errors.length > 0 ? (
            <ul className="cl-csv-errors">
              {preview.errors.slice(0, 10).map((error) => (
                <li key={`${error.line}-${error.code}`}>
                  {error.line > 0 ? `#${error.line} · ` : ""}
                  {error.message}
                </li>
              ))}
            </ul>
          ) : null}
          {!preview.applied ? (
            <Button
              disabled={busy}
              onClick={() =>
                void run("/admin/translations/import", () => showToast(t("settings.languages.importDone")))
              }
              variant="primary"
            >
              {t("settings.languages.applyImport")}
            </Button>
          ) : null}
        </div>
      ) : null}
    </Card>
  );
}
