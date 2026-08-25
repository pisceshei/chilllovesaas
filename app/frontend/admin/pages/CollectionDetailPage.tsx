import { ArrowLeft } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useBlocker, useNavigate, useParams } from "react-router-dom";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { LocalizedField } from "../components/LocalizedField";
import type { LocaleOption } from "../components/LocalizedField";
import { TextField } from "../components/TextField";
import { useT } from "../i18n/I18nContext";
import { useSaveBarRegister } from "../lib/SaveBarContext";
import { useToast } from "../lib/ToastContext";

/**
 * 商品系列建立／編輯（ML-3）。
 *
 * 🔴 **與商品頁共用三件事**（刻意，不另寫一份）：`LocalizedField` 兩種佈局、
 * SaveBar dirty 機制、譯文的 (locale, field) 列形態。共用的理由不是省碼，
 * 是**語義一致**——商家在兩個頁面看到的多語言行為必須一模一樣。
 */
const COLLECTION_QUERY = `
  query collectionForEdit($id: ID!) {
    collection(id: $id) {
      id title handle descriptionHtml collectionType sortOrder lockVersion
      seo { title description }
      translations { locale field value outdated }
    }
  }
`;

const SHOP_LOCALES_QUERY = `
  query shopLocales {
    shopLocales { locale { tag endonym } isSource position }
  }
`;

const COLLECTION_SET = `
  mutation collectionSet($input: CollectionSetInput!) {
    collectionSet(input: $input) {
      collection { id handle lockVersion title }
      userErrors { field message code }
    }
  }
`;

type TranslatableField = "title" | "body_html" | "meta_title" | "meta_description";
type TranslationMap = Record<string, Partial<Record<TranslatableField, string>>>;

interface FormValues {
  title: string;
  description: string;
  handle: string;
  collectionType: string;
  sortOrder: string;
  seoTitle: string;
  seoDescription: string;
  translations: TranslationMap;
}

const INITIAL: FormValues = {
  title: "",
  description: "",
  handle: "",
  collectionType: "manual",
  sortOrder: "manual",
  seoTitle: "",
  seoDescription: "",
  translations: {},
};

const SORT_ORDERS = [
  "manual", "best_selling", "title_asc", "title_desc", "price_asc", "price_desc", "created_desc", "created_asc",
] as const;

function toTranslationMap(rows: { locale: string; field: string; value: string }[]): TranslationMap {
  const map: TranslationMap = {};
  for (const row of rows) {
    map[row.locale] = { ...(map[row.locale] ?? {}), [row.field as TranslatableField]: row.value };
  }
  return map;
}

function translationEntries(map: TranslationMap, sourceLocale: string) {
  const fields: TranslatableField[] = [ "title", "body_html", "meta_title", "meta_description" ];
  const entries: { locale: string; field: TranslatableField; value: string }[] = [];
  for (const [ locale, byField ] of Object.entries(map)) {
    if (locale === sourceLocale) continue;
    for (const field of fields) {
      const value = byField[field];
      if (value === undefined) continue;
      entries.push({ locale, field, value });
    }
  }
  return entries;
}

export function CollectionDetailPage({ isNew }: { isNew: boolean }) {
  const t = useT();
  const navigate = useNavigate();
  const params = useParams();
  const { showToast } = useToast();
  const registerSaveBar = useSaveBarRegister();

  const gid = isNew ? null : decodeURIComponent(params.id ?? "");
  const [values, setValues] = useState<FormValues>(INITIAL);
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "missing">(isNew ? "ready" : "loading");
  const [lockVersion, setLockVersion] = useState(0);
  const [shakeSignal, setShakeSignal] = useState(0);
  const [contentLocales, setContentLocales] = useState<{ tag: string; endonym: string; isSource: boolean }[]>([]);
  const [outdatedFields, setOutdatedFields] = useState<Record<string, Set<TranslatableField>>>({});
  const titleRef = useRef<HTMLInputElement | null>(null);

  const snapshot = useRef(JSON.stringify(INITIAL));
  const dirty = useMemo(() => JSON.stringify(values) !== snapshot.current, [values]);

  useEffect(() => {
    const controller = new AbortController();
    requestAdminGraphQL<{ shopLocales: { locale: { tag: string; endonym: string }; isSource: boolean; position: number }[] }, Record<string, never>>(
      SHOP_LOCALES_QUERY, {}, controller.signal,
    )
      .then((data) => {
        const rows = [ ...data.shopLocales ].sort((left, right) => {
          if (left.isSource !== right.isSource) return left.isSource ? -1 : 1;
          return left.position - right.position;
        });
        setContentLocales(rows.map((row) => ({ tag: row.locale.tag, endonym: row.locale.endonym, isSource: row.isSource })));
      })
      .catch(() => setContentLocales([]));
    return () => controller.abort();
  }, []);

  useEffect(() => {
    if (isNew || !gid) return;
    const controller = new AbortController();
    setLoadState("loading");
    requestAdminGraphQL<{ collection: null | {
      id: string; title: string; handle: string; descriptionHtml: string; collectionType: string;
      sortOrder: string; lockVersion: number; seo: { title: string | null; description: string | null };
      translations: { locale: string; field: string; value: string; outdated: boolean }[];
    } }, { id: string }>(COLLECTION_QUERY, { id: gid }, controller.signal)
      .then((data) => {
        const collection = data.collection;
        if (!collection) {
          setLoadState("missing");
          return;
        }
        const loaded: FormValues = {
          title: collection.title,
          description: collection.descriptionHtml,
          handle: collection.handle,
          collectionType: collection.collectionType,
          sortOrder: collection.sortOrder,
          seoTitle: collection.seo?.title ?? "",
          seoDescription: collection.seo?.description ?? "",
          translations: toTranslationMap(collection.translations),
        };
        snapshot.current = JSON.stringify(loaded);
        setValues(loaded);
        setLockVersion(collection.lockVersion);
        setOutdatedFields(
          collection.translations.reduce<Record<string, Set<TranslatableField>>>((accumulator, row) => {
            if (!row.outdated) return accumulator;
            const set = accumulator[row.locale] ?? new Set<TranslatableField>();
            set.add(row.field as TranslatableField);
            return { ...accumulator, [row.locale]: set };
          }, {}),
        );
        setLoadState("ready");
      })
      .catch(() => setLoadState("missing"));
    return () => controller.abort();
  }, [gid, isNew]);

  const sourceLocale = contentLocales.find((locale) => locale.isSource)?.tag ?? "en";
  const baseField: Record<TranslatableField, keyof FormValues> = {
    title: "title",
    body_html: "description",
    meta_title: "seoTitle",
    meta_description: "seoDescription",
  };

  const localizedValues = (field: TranslatableField): Record<string, string> => {
    const map: Record<string, string> = {};
    for (const locale of contentLocales) {
      map[locale.tag] = locale.isSource
        ? String(values[baseField[field]] ?? "")
        : values.translations[locale.tag]?.[field] ?? "";
    }
    return map;
  };

  const setLocalized = (field: TranslatableField, locale: string, next: string) => {
    if (locale === sourceLocale) {
      setValues((current) => ({ ...current, [baseField[field]]: next }));
      return;
    }
    setValues((current) => ({
      ...current,
      translations: { ...current.translations, [locale]: { ...(current.translations[locale] ?? {}), [field]: next } },
    }));
  };

  const localeOptionsFor = (field: TranslatableField): LocaleOption[] =>
    contentLocales.map((locale) => ({
      tag: locale.tag,
      endonym: locale.endonym,
      outdated: outdatedFields[locale.tag]?.has(field) ?? false,
    }));

  const save = useCallback(async () => {
    if (saving) return;
    if (!values.title.trim()) {
      setErrors({ title: t("collections.validation.titleBlank") });
      showToast(t("product.validation.failed"));
      setShakeSignal((signal) => signal + 1);
      titleRef.current?.focus();
      return;
    }
    setErrors({});
    setSaving(true);
    try {
      const input: Record<string, unknown> = {
        title: values.title.trim(),
        descriptionHtml: values.description,
        collectionType: values.collectionType,
        sortOrder: values.sortOrder,
        seo: { title: values.seoTitle.trim(), description: values.seoDescription.trim() },
        translations: translationEntries(values.translations, sourceLocale),
      };
      // 第 6 包：系列 handle 兩態都送（同值＝伺服端 no-op；改值＝同 txn 落 301）。
      // 🔴 服務端在本包已解鎖，前端不同步的話 hintEdit 會在一個鎖死的欄位上
      //    描述「改 handle 會建立 301」——文案與可操作性互相矛盾（審查 P6-4）。
      if (values.handle) input.handle = values.handle.trim();
      if (!isNew) {
        input.id = gid;
        input.lockVersion = lockVersion;
      }

      const data = await requestAdminGraphQL<{
        collectionSet: { collection: { id: string; lockVersion: number } | null; userErrors: { field: string[] | null; message: string; code: string }[] };
      }, Record<string, unknown>>(COLLECTION_SET, { input });

      const { collection, userErrors } = data.collectionSet;
      if (userErrors.length > 0 || !collection) {
        showToast(userErrors[0]?.message ?? t("product.validation.failed"));
        setShakeSignal((signal) => signal + 1);
        return;
      }
      snapshot.current = JSON.stringify(values);
      showToast(t("product.saved"));
      if (isNew) {
        navigate("/admin/collections");
      } else {
        setLockVersion(collection.lockVersion);
        setValues((current) => ({ ...current }));
      }
    } catch (reason: unknown) {
      showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("product.saveFailed"));
    } finally {
      setSaving(false);
    }
  }, [gid, isNew, lockVersion, navigate, saving, showToast, sourceLocale, t, values]);

  const discard = useCallback(() => {
    setValues(JSON.parse(snapshot.current) as FormValues);
    setErrors({});
    showToast(t("product.discarded"));
  }, [showToast, t]);

  useEffect(() => {
    registerSaveBar({ dirty, saving, onSave: () => void save(), onDiscard: discard, shakeSignal });
    return () => registerSaveBar(null);
  }, [dirty, discard, registerSaveBar, save, saving, shakeSignal]);

  const blocker = useBlocker(dirty && !saving);
  const lastBlockAt = useRef(0);
  useEffect(() => {
    if (blocker.state !== "blocked") return;
    const now = Date.now();
    if (now - lastBlockAt.current < 4000) {
      blocker.proceed();
      return;
    }
    lastBlockAt.current = now;
    showToast(t("product.leaveWarning"));
    setShakeSignal((signal) => signal + 1);
    blocker.reset();
  }, [blocker, showToast, t]);

  if (loadState === "loading") {
    return (
      <div className="cl-page cl-page--detail">
        <p className="cl-card-note">{t("product.loading")}</p>
      </div>
    );
  }

  if (loadState === "missing") {
    return (
      <div className="cl-page cl-page--detail">
        <Card padded>
          <h3>{t("collections.notFound.title")}</h3>
          <Button onClick={() => navigate("/admin/collections")}>{t("collections.back")}</Button>
        </Card>
      </div>
    );
  }

  return (
    <div className="cl-page cl-page--detail cl-product-detail">
      <header className="cl-detail-head">
        <button
          aria-label={t("collections.back")}
          className="cl-icon-button"
          onClick={() => navigate("/admin/collections")}
          type="button"
        >
          <ArrowLeft aria-hidden="true" size={16} />
        </button>
        <h1>{isNew ? t("collections.add") : values.title || t("collections.title")}</h1>
        <span className="cl-locale-chip" title={t("product.contentLocale")}>
          {contentLocales.find((locale) => locale.isSource)?.endonym ?? sourceLocale}
        </span>
        <div className="cl-detail-head__actions">
          <Button loading={saving} loadingLabel={t("common.saving")} onClick={() => void save()} variant="primary">
            {t("common.save")}
          </Button>
        </div>
      </header>

      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          <Card padded>
            <h3>{t("product.card.titleDescription")}</h3>
            <LocalizedField
              error={errors.title}
              label={t("collections.field.title")}
              locales={localeOptionsFor("title")}
              maxLength={255}
              mode="stacked"
              onChange={(locale, next) => setLocalized("title", locale, next)}
              placeholder={t("collections.field.title.placeholder")}
              sourceLocale={sourceLocale}
              sourceRef={(node) => { titleRef.current = node; }}
              values={localizedValues("title")}
            />
            <LocalizedField
              label={t("product.field.description")}
              locales={localeOptionsFor("body_html")}
              mode="tabbed"
              onChange={(locale, next) => setLocalized("body_html", locale, next)}
              renderTabbed={(locale, value, onValueChange) => (
                <textarea
                  aria-label={`${t("product.field.description")}（${locale}）`}
                  className="cl-field__input cl-field__textarea"
                  lang={locale}
                  onChange={(event) => onValueChange(event.target.value)}
                  rows={4}
                  value={value}
                />
              )}
              sourceLocale={sourceLocale}
              values={localizedValues("body_html")}
            />
          </Card>

          <Card padded>
            <h3>{t("product.card.seo")}</h3>
            <LocalizedField
              label={t("product.seo.pageTitle")}
              locales={localeOptionsFor("meta_title")}
              maxLength={70}
              mode="tabbed"
              onChange={(locale, next) => setLocalized("meta_title", locale, next)}
              sourceLocale={sourceLocale}
              values={localizedValues("meta_title")}
            />
            <LocalizedField
              label={t("product.seo.meta")}
              locales={localeOptionsFor("meta_description")}
              mode="tabbed"
              onChange={(locale, next) => setLocalized("meta_description", locale, next)}
              renderTabbed={(locale, value, onValueChange) => (
                <textarea
                  aria-label={`${t("product.seo.meta")}（${locale}）`}
                  className="cl-field__input cl-field__textarea"
                  lang={locale}
                  maxLength={320}
                  onChange={(event) => onValueChange(event.target.value)}
                  rows={3}
                  value={value}
                />
              )}
              sourceLocale={sourceLocale}
              values={localizedValues("meta_description")}
            />
            <TextField
              hint={isNew ? t("product.seo.handle.hintNew") : t("product.seo.handle.hintEdit")}
              label={t("product.seo.handle")}
              onChange={(event) => setValues((current) => ({ ...current, handle: event.target.value }))}
              placeholder={t("product.seo.handle.placeholder")}
              value={values.handle}
            />
          </Card>
        </div>

        <div className="cl-od-grid__aside">
          <Card padded>
            <h3>{t("collections.card.type")}</h3>
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="collection-type">
                {t("collections.col.type")}
              </label>
              <select
                className="cl-field__input"
                id="collection-type"
                onChange={(event) => setValues((current) => ({ ...current, collectionType: event.target.value }))}
                value={values.collectionType}
              >
                <option value="manual">{t("collections.type.manual")}</option>
                <option value="smart">{t("collections.type.smart")}</option>
              </select>
              {/* 🔴 智慧系列的條件編輯屬規則引擎包；現在只存型別，不假裝能編條件。 */}
              <p className="cl-field__hint">
                {values.collectionType === "smart" ? t("collections.type.smartHint") : t("collections.type.manualHint")}
              </p>
            </div>
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="collection-sort">
                {t("collections.sortOrder")}
              </label>
              <select
                className="cl-field__input"
                id="collection-sort"
                onChange={(event) => setValues((current) => ({ ...current, sortOrder: event.target.value }))}
                value={values.sortOrder}
              >
                {SORT_ORDERS.map((order) => (
                  <option key={order} value={order}>
                    {t(`collections.sort.${order}`)}
                  </option>
                ))}
              </select>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
