import { ArrowLeft, ChevronsUpDown, Share2 } from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
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
import { Popover } from "../components/Popover";
import {
  ChannelScheduleButton, EMPTY_DELTA, GroupToggle, SwitchRow,
  channelIsOn, channelSwitchId, publishEntry, salesChannelsOf, sameDelta,
  scheduleChannel, serverScheduleOf, toggleChannel,
} from "./ProductDetailPage";
import type { PublicationDelta, PublicationOption, PublicationRow } from "./ProductDetailPage";

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
      resourcePublicationsV2(onlyPublished: false) {
        isPublished
        publishDate
        publication { id title supportsFuturePublishing }
      }
    }
  }
`;

const SHOP_LOCALES_QUERY = `
  query shopLocales {
    shopLocales { locale { tag endonym } isSource position }
  }
`;

/**
 * S6c（D71）：系列的銷售管道 popover 資料。
 * `publications`＝本店全部管道（popover 要列出「未發布」的管道，`resourcePublicationsV2`
 * 只回有列者——與商品 modal 同一個理由，見 ProductDetailPage 同名註釋）。
 */
const CHANNELS_QUERY = `
  query collectionChannels {
    publications { id title handle supportsFuturePublishing }
    shop { ianaTimezone }
  }
`;

/**
 * 發布寫入（S6c）。與 ProductDetailPage 的 PUBLISHING_MUTATION 同構——
 * 🔴 本尊實測（2026-08-28 抓包，docs/research/82 §17）：系列 popover 的儲存
 * 走 AddCollectionPublications／DeleteCollectionPublications 兩個 persisted op，
 * response 的 data key 是 `publishablePublish`／`publishableUnpublish`
 * ⇒ 底層就是我方 S5 的同名 mutation，直接用。
 */
const COLLECTION_PUBLISHING_MUTATION = `
  mutation collectionPublishing(
    $id: ID!
    $publicationsToPublish: [PublicationInput!]!
    $publicationsToUnpublish: [PublicationInput!]!
    $shouldPublish: Boolean!
    $shouldUnpublish: Boolean!
  ) {
    publishablePublish(id: $id, input: $publicationsToPublish) @include(if: $shouldPublish) {
      userErrors { field message code }
    }
    publishableUnpublish(id: $id, input: $publicationsToUnpublish) @include(if: $shouldUnpublish) {
      userErrors { field message code }
    }
  }
`;

/** 儲存後的發布狀態重讀（不做樂觀翻轉——理由同 ProductDetailPage 的 PUBLICATIONS_QUERY）。 */
const COLLECTION_PUBLICATIONS_QUERY = `
  query collectionPublications($id: ID!) {
    collection(id: $id) {
      resourcePublicationsV2(onlyPublished: false) {
        isPublished
        publishDate
        publication { id title supportsFuturePublishing }
      }
    }
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
  // ── S6c（D71）：銷售管道 popover ──────────────────────────────────────
  const [publications, setPublications] = useState<PublicationOption[]>([]);
  const [pubRows, setPubRows] = useState<PublicationRow[]>([]);
  const [pubDelta, setPubDelta] = useState<PublicationDelta>(EMPTY_DELTA);
  const [shopTimezone, setShopTimezone] = useState("Asia/Hong_Kong");
  const titleRef = useRef<HTMLInputElement | null>(null);

  const snapshot = useRef(JSON.stringify(INITIAL));
  const valuesDirty = useMemo(() => JSON.stringify(values) !== snapshot.current, [values]);
  // 🔴 本尊實測（82 §17）：popover 的 toggle 是**表單級 dirty**——不打即時 mutation，
  //   頂部出現 Unsaved changes 保存列，Save 才送、Discard 還原。delta 因此進 dirty。
  const dirty = useMemo(() => valuesDirty || !sameDelta(pubDelta, EMPTY_DELTA), [valuesDirty, pubDelta]);

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
      resourcePublicationsV2: PublicationRow[];
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
        setPubRows(collection.resourcePublicationsV2 ?? []);
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

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const data = await requestAdminGraphQL<{
          publications: (PublicationOption & { handle: string | null })[];
          shop: { ianaTimezone: string };
        }, Record<string, never>>(CHANNELS_QUERY, {});
        if (cancelled) return;
        setPublications(salesChannelsOf(data.publications));
        setShopTimezone(data.shop.ianaTimezone);
      } catch {
        // 管道清單拿不到 ⇒ popover 顯示空清單；不擋頁面其他功能
      }
    })();
    return () => { cancelled = true; };
  }, []);

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
        sortOrder: values.sortOrder,
        seo: { title: values.seoTitle.trim(), description: values.seoDescription.trim() },
        translations: translationEntries(values.translations, sourceLocale),
      };
      // 第 6 包：系列 handle 兩態都送（同值＝伺服端 no-op；改值＝同 txn 落 301）。
      // 🔴 服務端在本包已解鎖，前端不同步的話 hintEdit 會在一個鎖死的欄位上
      //    描述「改 handle 會建立 301」——文案與可操作性互相矛盾（審查 P6-4）。
      if (values.handle) input.handle = values.handle.trim();
      // 🔴 型別**只在建立時**送：伺服端自 2026-08-26 起把它做成建立後不可變
      //    （本尊官方語義，save_collection.rb 的 immutable 守衛）。更新照送的話，
      //    被拒的值會留在表單狀態裡，**之後每一次存檔**（改標題、改 SEO⋯⋯）都被
      //    同一個 INVALID 擋下——商家看到「改標題卻說型別不可變」且永遠存不進去。
      //    宣告式契約下「缺席＝保持現值」，不送才是正解。
      if (isNew) input.collectionType = values.collectionType;
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

      // ── S6c：套發布 delta（collectionSet 成功後才送；同 S6b 的順序理由）──
      if (!sameDelta(pubDelta, EMPTY_DELTA) && !isNew) {
        const toPublish = pubDelta.publish.map((entry) => ({
          publicationId: entry.publicationId,
          ...(entry.at !== null ? { publishDate: new Date(entry.at).toISOString() } : {}),
        }));
        const toUnpublish = pubDelta.unpublish.map((publicationId) => ({ publicationId }));
        const applied = await requestAdminGraphQL<{
          publishablePublish?: { userErrors: { field: string[] | null; message: string; code: string }[] };
          publishableUnpublish?: { userErrors: { field: string[] | null; message: string; code: string }[] };
        }, Record<string, unknown>>(COLLECTION_PUBLISHING_MUTATION, {
          id: gid,
          publicationsToPublish: toPublish,
          publicationsToUnpublish: toUnpublish,
          shouldPublish: toPublish.length > 0,
          shouldUnpublish: toUnpublish.length > 0,
        });
        const pubErrors = [
          ...(applied.publishablePublish?.userErrors ?? []),
          ...(applied.publishableUnpublish?.userErrors ?? []),
        ];
        // 🔴 不做樂觀翻轉，一律重讀（unpublish 是硬刪列、publish 可能被拒，
        //    兩支不同 transaction——與 ProductDetailPage 同一組理由）。
        setPubDelta(EMPTY_DELTA);
        try {
          const fresh = await requestAdminGraphQL<{
            collection: { resourcePublicationsV2: PublicationRow[] } | null;
          }, { id: string }>(COLLECTION_PUBLICATIONS_QUERY, { id: gid ?? "" });
          setPubRows(fresh.collection?.resourcePublicationsV2 ?? []);
        } catch {
          // 重讀失敗：維持舊列，下一次載入會補正
        }
        if (pubErrors.length > 0) {
          showToast(pubErrors[0].message);
          return;
        }
      }

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
  }, [gid, isNew, lockVersion, navigate, pubDelta, saving, showToast, sourceLocale, t, values]);

  const discard = useCallback(() => {
    setValues(JSON.parse(snapshot.current) as FormValues);
    setPubDelta(EMPTY_DELTA); // S6c：本尊實測 Discard 一併還原 popover 的 toggle（82 §17）
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
            {/* S6c（D71）：本尊把管道觸發鈕放在標題卡右下（82 §17 實測）。
                isNew 隱藏：新系列尚無 GID 可發布；本尊新建表單的形態未取得（登記 V）。 */}
            {!isNew ? (
              <CollectionChannelsControl
                delta={pubDelta}
                onDelta={(updater) => setPubDelta(updater)}
                publications={publications}
                rows={pubRows}
                shopTimezone={shopTimezone}
                t={t}
              />
            ) : null}
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
              {/* 🔴 建立後不可變（本尊官方語義；伺服端硬拒）⇒ 既有系列上這個下拉必須
                  停用。留著顯示（而非隱藏）是為了讓商家看得到目前型別；停用理由寫在
                  hint 裡。**不得**讓它可翻——可翻的控件配上必定失敗的伺服端＝
                  「改標題卻跳型別錯誤」的死路（2026-08-26 delta 審查 F4）。 */}
              <select
                className="cl-field__input"
                disabled={!isNew}
                id="collection-type"
                onChange={(event) => setValues((current) => ({ ...current, collectionType: event.target.value }))}
                value={values.collectionType}
              >
                <option value="manual">{t("collections.type.manual")}</option>
                <option value="smart">{t("collections.type.smart")}</option>
              </select>
              {/* 🔴 智慧系列的條件編輯屬規則引擎包；現在只存型別，不假裝能編條件。 */}
              <p className="cl-field__hint">
                {isNew
                  ? values.collectionType === "smart" ? t("collections.type.smartHint") : t("collections.type.manualHint")
                  : t("collections.type.immutableHint")}
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


/**
 * S6c（D71）：系列的銷售管道 popover（本尊「輕量 popover」形態，82 §9.3／§17 實測）。
 *
 * ①這是什麼：標題卡右下的 `N 個管道 ˅` 觸發鈕 ＋ 它開出的輕量 popover。
 * ②具體功能：popover 標頭＝「銷售管道」＋三態總開關（mixed→全開→全關，82 §17 實測循環）；
 *   每列＝管道名＋switch；`supportsFuturePublishing` 的管道另有排程入口。
 *   🔴 值域＝本店全部銷售管道（`publications` query，handle 非 null 者）——**無 Agentic、
 *   無 Catalogs 組**，本尊官方語義「Collection only supports publications to APP catalog
 *   types」（82 §9.3）。
 * ③怎樣做出來：toggle 只改 `pubDelta`（表單級 dirty，82 §17 實測：本尊不打即時 mutation，
 *   Save 才送 publishablePublish／publishableUnpublish、Discard 還原）；重用商品 modal 的
 *   SwitchRow／GroupToggle／ChannelScheduleButton（單一發布語義來源）。
 * ④跨功能影響：SaveBar 的 dirty；儲存流程多一段 delta 套用＋重讀；
 *   前台可見性（S9 的兩道閘之一）。
 * ⚠️ 與本尊的兩個已知偏離（皆已登記 82 §17）：
 *   排程入口一律顯示（本尊 hover 才現身；觸控無對應手勢——與商品 modal 同一裁定）；
 *   排程面板是錨定子彈層（本尊在 popover 內原地換頁——我方重用 SchedulePopover 原語，
 *   形態隨商品 modal 的先例）。
 */
function CollectionChannelsControl({
  publications,
  rows,
  delta,
  shopTimezone,
  onDelta,
  t,
}: {
  publications: PublicationOption[];
  rows: PublicationRow[];
  delta: PublicationDelta;
  shopTimezone: string;
  onDelta: (updater: (current: PublicationDelta) => PublicationDelta) => void;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const scopeId = useId();
  // 🔴 開啟當下取一次「現在」，不逐 render 取——排程下限不在填表期間往前跑
  //   （SchedulePopover 的既有契約，S6b-2a）。
  const [nowAt, setNowAt] = useState(() => Date.now());

  const onCount = publications.filter((pub) => channelIsOn(rows, delta, pub.id)).length;
  const groupState: boolean | "mixed" =
    publications.length > 0 && onCount === publications.length ? true : onCount === 0 ? false : "mixed";

  const triggerText = onCount === 1
    ? t("collection.channels.trigger.one")
    : t("collection.channels.trigger.many", { count: onCount });

  return (
    <div className="cl-chpop-slot">
      <button
        aria-expanded={open}
        aria-haspopup="dialog"
        aria-label={t("collection.channels.triggerAria", { count: onCount })}
        className="cl-chpop-trigger"
        onClick={() => { setNowAt(Date.now()); setOpen((current) => !current); }}
        ref={anchorRef}
        title={t("collection.channels.tooltip")}
        type="button"
      >
        <Share2 aria-hidden="true" size={16} />
        <span>{triggerText}</span>
        <ChevronsUpDown aria-hidden="true" size={14} />
      </button>
      <Popover
        anchorRef={anchorRef}
        dismissOnOutsideClick
        label={t("collection.channels.title")}
        onClose={() => setOpen(false)}
        open={open}
      >
        <div className="cl-chpop">
          <div className="cl-chpop__head">
            <span className="cl-chpop__head-label">{t("collection.channels.title")}</span>
            <GroupToggle
              checked={groupState}
              controls={publications.map((pub) => channelSwitchId(scopeId, pub.id)).join(" ")}
              label={`${t("collection.channels.title")} — ${groupState === true
                ? t("product.publishing.modal.unpublishAll")
                : t("product.publishing.modal.publishAll")}`}
              onChange={(next) =>
                onDelta((current) =>
                  publications.reduce((acc, pub) => toggleChannel(rows, acc, pub.id, next), current))}
            />
          </div>
          <ul className="cl-chpop__list">
            {publications.map((pub) => (
              <li className="cl-chpop__row" key={pub.id}>
                <SwitchRow
                  checked={channelIsOn(rows, delta, pub.id)}
                  id={channelSwitchId(scopeId, pub.id)}
                  label={pub.title}
                  onChange={(next) => onDelta((current) => toggleChannel(rows, current, pub.id, next))}
                />
                {pub.supportsFuturePublishing ? (
                  <ChannelScheduleButton
                    hasSavedSchedule={serverScheduleOf(rows, pub.id) !== null}
                    now={nowAt}
                    onSchedule={(at) => onDelta((current) => scheduleChannel(current, pub.id, at))}
                    publicationId={pub.id}
                    scheduledAt={publishEntry(delta, pub.id)?.at ?? serverScheduleOf(rows, pub.id)}
                    shopTimezone={shopTimezone}
                    t={t}
                  />
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      </Popover>
    </div>
  );
}
