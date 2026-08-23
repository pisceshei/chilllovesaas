import { Globe, Plus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 設定 › 語言（ML-4；docs/specs/67 §A.2／§C.1）。
 *
 * 🔴 **新增語言不建表、不 migration**：語言集合是**資料**——
 * 這頁做的事就是往 `shop_locales` 插／改一列，商品與 Collection 編輯頁
 * 下次載入就多出（或少掉）那一格欄位（欄位由 `shopLocales` 查詢驅動）。
 * 譯文一律落同一張 `translations`（resource × locale × field 一列）。
 *
 * 停用＝狀態轉換不是刪除：譯文全部保留，重新啟用即復原（67 §C.1）。
 */
const LOCALES_QUERY = `
  query localeSettings {
    shopLocales(includeDisabled: true) {
      locale { tag endonym direction }
      isSource
      published
      enabled
      position
    }
    availableLocales { tag endonym direction }
  }
`;

const ENABLE_MUTATION = `
  mutation shopLocaleEnable($locale: String!) {
    shopLocaleEnable(locale: $locale) {
      shopLocale { locale { tag } }
      userErrors { field message code }
    }
  }
`;

const UPDATE_MUTATION = `
  mutation shopLocaleUpdate($locale: String!, $published: Boolean) {
    shopLocaleUpdate(locale: $locale, published: $published) {
      shopLocale { locale { tag } published }
      userErrors { field message code }
    }
  }
`;

const DISABLE_MUTATION = `
  mutation shopLocaleDisable($locale: String!) {
    shopLocaleDisable(locale: $locale) {
      retainedTranslations
      userErrors { field message code }
    }
  }
`;

interface LocaleRef {
  tag: string;
  endonym: string;
  direction: string;
}

interface ShopLocaleRow {
  locale: LocaleRef;
  isSource: boolean;
  published: boolean;
  enabled: boolean;
  position: number;
}

interface LocalesData {
  shopLocales: ShopLocaleRow[];
  availableLocales: LocaleRef[];
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

export function SettingsLanguagesPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<LocalesData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [adding, setAdding] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setData(await requestAdminGraphQL<LocalesData, Record<string, never>>(LOCALES_QUERY, {}, signal));
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("settings.languages.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  /** 三支 mutation 共用：跑完一律重載，讓畫面與 DB 同源（不做樂觀更新——語言是設定不是輸入框）。 */
  const run = useCallback(
    async (label: string, query: string, variables: Record<string, unknown>, successMessage: string) => {
      if (busy) return;
      setBusy(label);
      try {
        const result = await requestAdminGraphQL<Record<string, MutationErrors>, Record<string, unknown>>(query, variables);
        const payload = Object.values(result)[0];
        if (payload.userErrors.length > 0) {
          showToast(payload.userErrors[0].message);
          return;
        }
        showToast(successMessage);
        await load();
      } catch (reason: unknown) {
        showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("settings.languages.actionFailed"));
      } finally {
        setBusy(null);
      }
    },
    [busy, load, showToast, t],
  );

  if (error) {
    return (
      <Page title={t("settings.languages.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("settings.languages.title")}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  const enabledRows = data.shopLocales.filter((row) => row.enabled);
  const disabledRows = data.shopLocales.filter((row) => !row.enabled);

  return (
    <Page title={t("settings.languages.title")}>
      <Card padded>
        <h3>{t("settings.languages.enabled")}</h3>
        <p className="cl-card-note">{t("settings.languages.enabledHint")}</p>
        <ul className="cl-locale-list">
          {enabledRows.map((row) => (
            <li className="cl-locale-row" key={row.locale.tag}>
              <span className="cl-locale-row__name" lang={row.locale.tag}>
                {row.locale.endonym}
                <small>{row.locale.tag}{row.locale.direction === "rtl" ? " · RTL" : ""}</small>
              </span>
              {row.isSource ? (
                <Badge progress="full" tone="info">
                  {t("settings.languages.source")}
                </Badge>
              ) : (
                <Badge progress={row.published ? "full" : "empty"} tone={row.published ? "success" : "default"}>
                  {row.published ? t("settings.languages.published") : t("settings.languages.unpublished")}
                </Badge>
              )}
              <span className="cl-locale-row__actions">
                {row.isSource ? (
                  <span className="cl-card-note">{t("settings.languages.sourceHint")}</span>
                ) : (
                  <>
                    <Button
                      disabled={busy !== null}
                      onClick={() =>
                        void run(
                          `publish:${row.locale.tag}`,
                          UPDATE_MUTATION,
                          { locale: row.locale.tag, published: !row.published },
                          row.published ? t("settings.languages.unpublishedDone") : t("settings.languages.publishedDone"),
                        )
                      }
                      size="small"
                    >
                      {row.published ? t("settings.languages.unpublish") : t("settings.languages.publish")}
                    </Button>
                    <Button
                      disabled={busy !== null}
                      onClick={() =>
                        void run(
                          `disable:${row.locale.tag}`,
                          DISABLE_MUTATION,
                          { locale: row.locale.tag },
                          t("settings.languages.disabledDone"),
                        )
                      }
                      size="small"
                      variant="ghost"
                    >
                      <Trash2 aria-hidden="true" size={13} /> {t("settings.languages.disable")}
                    </Button>
                  </>
                )}
              </span>
            </li>
          ))}
        </ul>
      </Card>

      <Card padded>
        <h3>{t("settings.languages.add")}</h3>
        {/* 🔴 候選來自平台語言字典（platform_locales）——新增語言＝插一列 shop_locales，
            不建表、不 migration；商品與 Collection 編輯頁下次載入自動多一格。 */}
        <p className="cl-card-note">{t("settings.languages.addHint")}</p>
        <div className="cl-locale-add">
          <select
            aria-label={t("settings.languages.add")}
            className="cl-field__input"
            disabled={busy !== null || data.availableLocales.length === 0}
            onChange={(event) => setAdding(event.target.value)}
            value={adding}
          >
            <option value="">{t("settings.languages.choose")}</option>
            {data.availableLocales.map((locale) => (
              <option key={locale.tag} lang={locale.tag} value={locale.tag}>
                {locale.endonym}（{locale.tag}）
              </option>
            ))}
          </select>
          <Button
            disabled={busy !== null || !adding}
            onClick={() => {
              const tag = adding;
              setAdding("");
              void run(`enable:${tag}`, ENABLE_MUTATION, { locale: tag }, t("settings.languages.addedDone"));
            }}
            variant="primary"
          >
            <Plus aria-hidden="true" size={14} /> {t("settings.languages.addButton")}
          </Button>
        </div>
      </Card>

      {disabledRows.length > 0 ? (
        <Card padded>
          <h3>{t("settings.languages.disabled")}</h3>
          {/* 停用＝狀態轉換不是刪除：譯文全部保留，加回來即復原（67 §C.1）。 */}
          <p className="cl-card-note">{t("settings.languages.disabledHint")}</p>
          <ul className="cl-locale-list">
            {disabledRows.map((row) => (
              <li className="cl-locale-row" key={row.locale.tag}>
                <span className="cl-locale-row__name" lang={row.locale.tag}>
                  {row.locale.endonym}
                  <small>{row.locale.tag}</small>
                </span>
                <span className="cl-locale-row__actions">
                  <Button
                    disabled={busy !== null}
                    onClick={() =>
                      void run(
                        `enable:${row.locale.tag}`,
                        ENABLE_MUTATION,
                        { locale: row.locale.tag },
                        t("settings.languages.restoredDone"),
                      )
                    }
                    size="small"
                  >
                    <Globe aria-hidden="true" size={13} /> {t("settings.languages.restore")}
                  </Button>
                </span>
              </li>
            ))}
          </ul>
        </Card>
      ) : null}
    </Page>
  );
}
