import { ArrowLeft, Check, ChevronDown, ImagePlus, MoreHorizontal, Pencil, Sparkles, X } from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import { useBlocker, useNavigate, useParams } from "react-router-dom";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import type { BadgeProgress, BadgeTone } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { TextField } from "../components/TextField";
import { useSaveBarRegister } from "../lib/SaveBarContext";
import { useToast } from "../lib/ToastContext";
import { uuidV4 } from "../lib/uuid";
import { centsToApiString, isValidMoneyInput, parseMoneyToCents, profitState } from "../lib/money";
import { useT } from "../i18n/I18nContext";

/**
 * 商品建立／詳情頁（59 §7：**同一個元件的兩種狀態，不是兩個頁面**——
 * 分家後同名函式靜默覆蓋整頁是本專案頭號事故 53 號 N-01）。
 *
 * isNew＝建立態（固定草稿、右欄只有發布卡）；否則編輯態（載入既有商品、
 * 右欄多狀態卡、儲存帶 id＋lockVersion 走 productSet 更新分支）。
 * 版面、卡片順序、pill 分組鍵對照原型 productPage()（chilllove-admin-v2.html）。
 *
 * 未接線欄位（disabled）＝後續里程碑的通道還沒到（庫存／運送／發布／SEO 文案），
 * **刻意 disabled 而不是收集後丟棄**——收了不送等於騙商家已儲存。
 * 清單與依賴見 docs/dev/m1-product-set-foundation.md §4／§6。
 */
export interface ProductDetailPageProps {
  /** 建立態；false＝編輯態（路由 /admin/products/:id）。 */
  isNew: boolean;
}

const PRODUCT_SET_MUTATION = `
  mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
    productSet(input: $input, idempotencyKey: $idempotencyKey) {
      product { id handle status title lockVersion }
      userErrors { field message code }
    }
  }
`;

const PRODUCT_QUERY = `
  query productForEdit($id: ID!) {
    product(id: $id) {
      id title descriptionHtml status handle lockVersion
      vendor productType tags
      seo { title description }
      variants { price compareAtPrice cost sku barcode taxable }
    }
  }
`;

/** 組織分類卡 autocomplete 的建議清單（91 §12；伺服端 distinct＋字母序）。 */
const SUGGESTIONS_QUERY = `
  query productOrganizationSuggestions {
    productVendors
    productTypes
  }
`;

interface SuggestionsData {
  productVendors: string[];
  productTypes: string[];
}

interface ProductSetData {
  productSet: {
    product: {
      id: string;
      handle: string;
      status: string;
      title: string;
      lockVersion: number;
    } | null;
    userErrors: { field: string[] | null; message: string; code: string }[];
  };
}

interface ProductQueryData {
  product: {
    id: string;
    title: string;
    descriptionHtml: string;
    status: string;
    handle: string;
    lockVersion: number;
    vendor: string | null;
    productType: string | null;
    tags: string[];
    seo: { title: string | null; description: string | null };
    variants: {
      price: string;
      compareAtPrice: string | null;
      cost: string | null;
      sku: string | null;
      barcode: string | null;
      taxable: boolean;
    }[];
  } | null;
}

/** 表單值（原型 PD_NEW 的對應子集；金額欄以原始輸入字串保存，送出才轉）。 */
interface FormValues {
  title: string;
  description: string;
  price: string;
  compare: string;
  cost: string;
  taxable: boolean;
  sku: string;
  barcode: string;
  handle: string;
  status: string;
  vendor: string;
  productType: string;
  tags: string[];
  seoTitle: string;
  seoDescription: string;
}

/** 建立態預設值（原型 PD_NEW：金額 null＝空字串不是 0；taxable 預設 true）。 */
const INITIAL_VALUES: FormValues = {
  title: "",
  description: "",
  price: "",
  compare: "",
  cost: "",
  taxable: true,
  sku: "",
  barcode: "",
  handle: "",
  status: "DRAFT",
  vendor: "",
  productType: "",
  tags: [],
  seoTitle: "",
  seoDescription: "",
};

type FieldKey =
  | "title" | "price" | "compare" | "cost" | "handle"
  | "vendor" | "productType" | "seoTitle" | "seoDescription";

/** 伺服器 userErrors path（productSet 剝 `input` 首段後）→ 表單欄位。 */
const SERVER_PATHS: Record<string, FieldKey> = {
  title: "title",
  handle: "handle",
  vendor: "vendor",
  productType: "productType",
  "seo.title": "seoTitle",
  "seo.description": "seoDescription",
  "variants.0.price": "price",
  "variants.0.compareAtPrice": "compare",
  "variants.0.cost": "cost",
};

/**
 * 狀態 listbox 選項（91 §2：本尊每項帶描述副行；**封存不在 listbox**，
 * 只能走「更多動作→封存商品」）。副行文案為我方措辭（鐵律 9 不抄本尊文案），
 * 語義取自 13 §F1.2 真值表。
 */
const STATUS_OPTIONS: { value: string; labelKey: string; hintKey: string }[] = [
  { value: "ACTIVE", labelKey: "status.active", hintKey: "status.hint.active" },
  { value: "DRAFT", labelKey: "status.draft", hintKey: "status.hint.draft" },
  { value: "UNLISTED", labelKey: "status.unlisted", hintKey: "status.hint.unlisted" },
];

/** 封存態只在目前狀態＝ARCHIVED 時出現在 listbox（顯示用；解除走選其他值）。 */
const ARCHIVED_OPTION = { value: "ARCHIVED", labelKey: "status.archived", hintKey: "status.hint.archived" };

/** SEO 計數器的 SERP 建議值（不是上限；上限＝伺服端 70／320，91 §11）。 */
const SEO_TITLE_MAX = 70;
const SEO_DESCRIPTION_SERP = 160;
const SEO_DESCRIPTION_MAX = 320;

/**
 * 狀態呈現（正典＝原型 P_STATUS，chilllove-admin-v2.html:3105；
 * 與 ProductsPage 同表——文案與 pip 不得漂移）。
 */
const STATUS_PRESENTATION: Record<string, { labelKey: string; progress: BadgeProgress; tone: BadgeTone }> = {
  ACTIVE: { labelKey: "status.active", progress: "full", tone: "success" },
  ARCHIVED: { labelKey: "status.archived", progress: "full", tone: "default" },
  DRAFT: { labelKey: "status.draft", progress: "empty", tone: "info" },
  UNLISTED: { labelKey: "status.unlisted", progress: "empty", tone: "attention" },
};

/** 兩維真值表（13 §F1.2：discoverable ⊆ purchasable 恆成立）。 */
const STATUS_DIMENSIONS: Record<string, { purchasable: boolean; discoverable: boolean }> = {
  ACTIVE: { purchasable: true, discoverable: true },
  UNLISTED: { purchasable: true, discoverable: false },
  DRAFT: { purchasable: false, discoverable: false },
  ARCHIVED: { purchasable: false, discoverable: false },
};

/** 純文字說明 → 段落 HTML（伺服器端再做白名單 sanitize，雙保險的前半）。 */
export function descriptionToHtml(text: string): string {
  const paragraphs = text
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.trim())
    .filter(Boolean);
  return paragraphs
    .map((paragraph) => `<p>${escapeHtml(paragraph).replaceAll("\n", "<br>")}</p>`)
    .join("");
}

/** 已儲存的段落 HTML → textarea 純文字（descriptionToHtml 的反向，編輯態載入用）。 */
export function htmlToDescription(html: string): string {
  return html
    .replaceAll(/<br\s*\/?>/gi, "\n")
    .replaceAll(/<\/p>\s*<p>/gi, "\n\n")
    .replaceAll(/<\/?p>/gi, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&")
    .trim();
}

function escapeHtml(raw: string): string {
  return raw
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

/** 開關列（原型 .swrow；v1 多為未接線 ⇒ disabled）。 */
function SwitchRow({
  label,
  hint,
  checked,
  disabled,
  onChange,
}: {
  label: string;
  hint?: string;
  checked: boolean;
  disabled?: boolean;
  onChange?: (next: boolean) => void;
}) {
  return (
    <div className="cl-swrow">
      <div className="cl-swrow__text">
        {label}
        {hint ? <span>{hint}</span> : null}
      </div>
      <button
        aria-checked={checked}
        aria-label={label}
        className={`cl-switch ${checked ? "cl-switch--on" : ""}`}
        disabled={disabled}
        onClick={onChange ? () => onChange(!checked) : undefined}
        role="switch"
        type="button"
      >
        <span aria-hidden="true" className="cl-switch__knob" />
      </button>
    </div>
  );
}

/** pill 收合組（原型 .pills/.pillpanel：透明無框、展開 sunken 底、▾ 旋轉）。 */
function PillGroup({
  pills,
  open,
  onToggle,
}: {
  pills: { key: string; label: string; value?: string }[];
  open: ReadonlySet<string>;
  onToggle: (key: string) => void;
}) {
  return (
    <div className="cl-pills">
      {pills.map((pill) => (
        <button
          aria-expanded={open.has(pill.key)}
          className="cl-pill"
          key={pill.key}
          onClick={() => onToggle(pill.key)}
          type="button"
        >
          {pill.label}
          {pill.value ? <span className="cl-pill__value">{pill.value}</span> : null}
          <span aria-hidden="true" className="cl-pill__chevron">
            ▾
          </span>
        </button>
      ))}
    </div>
  );
}

/**
 * 狀態選單（91 §2 形態：按鈕＋listbox popover，每項主文＋描述副行）。
 * 原生 select 的 option 放不下副行 ⇒ 自訂 listbox；鍵盤：Escape 關閉、點選即選取。
 */
function StatusListbox({
  value,
  onChange,
  labelId,
}: {
  value: string;
  onChange: (next: string) => void;
  labelId?: string;
}) {
  const t = useT();
  const [open, setOpen] = useState(false);
  const listId = useId();
  const options = value === "ARCHIVED" ? [ ...STATUS_OPTIONS, ARCHIVED_OPTION ] : STATUS_OPTIONS;
  const current = options.find((option) => option.value === value) ?? STATUS_OPTIONS[1];

  return (
    <div className="cl-statusbox">
      <button
        aria-controls={listId}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-labelledby={labelId}
        className="cl-field__input cl-statusbox__button"
        onClick={() => setOpen((state) => !state)}
        onKeyDown={(event) => {
          if (event.key === "Escape") setOpen(false);
        }}
        type="button"
      >
        {t(current.labelKey)}
        <ChevronDown aria-hidden="true" size={14} />
      </button>
      {open ? (
        <ul aria-label={t("product.status.label")} className="cl-statusbox__list" id={listId} role="listbox">
          {options.map((option) => (
            <li
              aria-selected={option.value === value}
              className={`cl-statusbox__option ${option.value === value ? "cl-statusbox__option--active" : ""}`}
              key={option.value}
              onClick={() => {
                onChange(option.value);
                setOpen(false);
              }}
              role="option"
            >
              <span className="cl-statusbox__check">
                {option.value === value ? <Check aria-hidden="true" size={14} /> : null}
              </span>
              <span className="cl-statusbox__text">
                {t(option.labelKey)}
                <span>{t(option.hintKey)}</span>
              </span>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

/**
 * 標籤欄（91 §12：token 多值）。Enter／逗號提交；chip × 移除。
 * 草稿輸入獨立於表單值 ⇒ 只敲了一半的標籤不會弄髒 SaveBar。
 */
function TagsField({
  tags,
  onChange,
  suggestions,
}: {
  tags: string[];
  onChange: (next: string[]) => void;
  suggestions: string[];
}) {
  const t = useT();
  const [draft, setDraft] = useState("");
  const inputId = useId();
  const listId = useId();

  const commit = () => {
    const value = draft.trim().replace(/,+$/, "").trim();
    setDraft("");
    if (!value || tags.includes(value)) return;
    onChange([ ...tags, value ]);
  };

  return (
    <div className="cl-field">
      <label className="cl-field__label" htmlFor={inputId}>
        {t("product.org.tags")}
      </label>
      {tags.length > 0 ? (
        <div className="cl-chips">
          {tags.map((tag) => (
            <span className="cl-chip" key={tag}>
              {tag}
              <button
                aria-label={t("product.org.tags.remove", { tag })}
                className="cl-chip__remove"
                onClick={() => onChange(tags.filter((existing) => existing !== tag))}
                type="button"
              >
                <X aria-hidden="true" size={11} />
              </button>
            </span>
          ))}
        </div>
      ) : null}
      <input
        className="cl-field__input"
        id={inputId}
        list={listId}
        onChange={(event) => {
          if (event.target.value.endsWith(",")) {
            setDraft(event.target.value);
            // 逗號輸入即提交（IME 安全：組字期間不會產生裸逗號）
            const value = event.target.value.slice(0, -1).trim();
            setDraft("");
            if (value && !tags.includes(value)) onChange([ ...tags, value ]);
            return;
          }
          setDraft(event.target.value);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            commit();
          }
        }}
        placeholder={t("product.org.tags.placeholder")}
        value={draft}
      />
      <datalist id={listId}>
        {suggestions.map((suggestion) => (
          <option key={suggestion} value={suggestion} />
        ))}
      </datalist>
    </div>
  );
}

/**
 * 呈現商品建立／編輯頁。
 *
 * @param props - isNew 分流。
 * @returns 對齊原型卡片樹的商品表單。
 */
export function ProductDetailPage({ isNew }: ProductDetailPageProps) {
  const navigate = useNavigate();
  const params = useParams();
  const t = useT();
  const { showToast } = useToast();
  const registerSaveBar = useSaveBarRegister();

  const productGid = isNew ? null : decodeURIComponent(params.id ?? "");

  const [values, setValues] = useState<FormValues>(INITIAL_VALUES);
  const [errors, setErrors] = useState<Partial<Record<FieldKey, string>>>({});
  const [saving, setSaving] = useState(false);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "missing">(
    isNew ? "ready" : "loading",
  );
  const [lockVersion, setLockVersion] = useState(0);
  const [openPills, setOpenPills] = useState<ReadonlySet<string>>(new Set());
  const [shakeSignal, setShakeSignal] = useState(0);
  const [seoOpen, setSeoOpen] = useState(false);
  const [actionsOpen, setActionsOpen] = useState(false);
  const [suggestions, setSuggestions] = useState<SuggestionsData>({ productVendors: [], productTypes: [] });
  // 更多動作→封存／取消封存：改狀態後立即儲存（本尊為即時動作，不停在 SaveBar）。
  const pendingAutoSave = useRef(false);

  // 冪等鍵：建立態專用（更新態是宣告式覆寫、天然冪等，防線是 lockVersion——D-PS5）。
  const idempotencyKey = useRef<string>(uuidV4());
  const fieldRefs = useRef<Partial<Record<FieldKey, HTMLInputElement | null>>>({});

  const snapshot = useRef(JSON.stringify(INITIAL_VALUES));
  const dirty = useMemo(() => JSON.stringify(values) !== snapshot.current, [values]);

  // 編輯態：載入既有商品填表（隱含變體恆一筆，B1-2）。
  useEffect(() => {
    if (isNew || !productGid) return;
    const controller = new AbortController();
    setLoadState("loading");

    requestAdminGraphQL<ProductQueryData, { id: string }>(
      PRODUCT_QUERY,
      { id: productGid },
      controller.signal,
    )
      .then((data) => {
        const product = data.product;
        if (!product) {
          setLoadState("missing");
          return;
        }
        const variant = product.variants[0];
        const loaded: FormValues = {
          title: product.title,
          description: htmlToDescription(product.descriptionHtml),
          price: variant?.price ?? "",
          compare: variant?.compareAtPrice ?? "",
          cost: variant?.cost ?? "",
          taxable: variant?.taxable ?? true,
          sku: variant?.sku ?? "",
          barcode: variant?.barcode ?? "",
          handle: product.handle,
          status: product.status,
          vendor: product.vendor ?? "",
          productType: product.productType ?? "",
          tags: product.tags ?? [],
          seoTitle: product.seo?.title ?? "",
          seoDescription: product.seo?.description ?? "",
        };
        snapshot.current = JSON.stringify(loaded);
        setValues(loaded);
        setLockVersion(product.lockVersion);
        setLoadState("ready");
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        showToast(reason instanceof Error ? reason.message : t("product.loadFailed"));
        setLoadState("missing");
      });

    return () => controller.abort();
  }, [isNew, productGid, showToast, t]);

  const setValue = useCallback(<Key extends keyof FormValues>(key: Key, value: FormValues[Key]) => {
    setValues((current) => ({ ...current, [key]: value }));
  }, []);

  // 組織分類卡的 autocomplete 建議（91 §12）。失敗靜默：建議清單是增強不是資料，
  // 空清單只是少了 datalist，欄位照常可打字。
  useEffect(() => {
    const controller = new AbortController();
    requestAdminGraphQL<SuggestionsData, Record<string, never>>(SUGGESTIONS_QUERY, {}, controller.signal)
      .then((data) => setSuggestions(data))
      .catch(() => {});
    return () => controller.abort();
  }, []);

  const togglePill = useCallback((key: string) => {
    setOpenPills((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  // 原型 formValidate：req/max/money/handle 規則；失敗 → toast＋shake＋focus 首個壞欄位。
  const validate = useCallback((): boolean => {
    const found: Partial<Record<FieldKey, string>> = {};
    if (!values.title.trim()) found.title = t("product.validation.titleBlank");
    else if (values.title.length > 255) found.title = t("product.validation.titleTooLong", { max: 255 });

    if (!values.price.trim()) found.price = t("product.validation.priceRequired");
    else if (!isValidMoneyInput(values.price)) {
      found.price = t("product.validation.moneyInvalid");
    }
    if (!isValidMoneyInput(values.compare)) {
      found.compare = t("product.validation.moneyInvalid");
    }
    if (!isValidMoneyInput(values.cost)) {
      found.cost = t("product.validation.moneyInvalid");
    }
    if (isNew && values.handle && !/^[a-z0-9-]+$/.test(values.handle)) {
      found.handle = t("product.validation.handleInvalid");
    }
    if (values.seoTitle.length > SEO_TITLE_MAX) {
      found.seoTitle = t("product.validation.seoTitleTooLong", { max: SEO_TITLE_MAX });
    }
    if (values.seoDescription.length > SEO_DESCRIPTION_MAX) {
      found.seoDescription = t("product.validation.seoDescriptionTooLong", { max: SEO_DESCRIPTION_MAX });
    }

    setErrors(found);
    const firstBad = (Object.keys(found) as FieldKey[])[0];
    if (firstBad) {
      showToast(t("product.validation.failed"));
      setShakeSignal((signal) => signal + 1);
      fieldRefs.current[firstBad]?.focus();
      return false;
    }
    return true;
  }, [isNew, showToast, t, values]);

  const applyServerErrors = useCallback(
    (userErrors: ProductSetData["productSet"]["userErrors"]) => {
      const mapped: Partial<Record<FieldKey, string>> = {};
      const unmapped: string[] = [];
      for (const userError of userErrors) {
        const key = userError.field ? SERVER_PATHS[userError.field.join(".")] : undefined;
        if (key) mapped[key] = userError.message;
        else unmapped.push(userError.message);
      }
      setErrors(mapped);
      showToast(unmapped[0] ?? t("product.validation.failed"));
      setShakeSignal((signal) => signal + 1);
      const firstBad = (Object.keys(mapped) as FieldKey[])[0];
      fieldRefs.current[firstBad ?? "title"]?.focus();
    },
    [showToast, t],
  );

  const save = useCallback(async () => {
    if (saving) return;
    if (!validate()) return;
    setSaving(true);
    try {
      // 🔴 B.4 規則 1：送**完整樹**（不是 dirty fields）。
      // 建立態顯式 DRAFT；編輯態帶 id＋lockVersion＋狀態卡的值。
      // handle：建立可手填；編輯不送（v1 handle 不可變，缺席＝保持現值）。
      const input: Record<string, unknown> = {
        title: values.title.trim(),
        descriptionHtml: descriptionToHtml(values.description),
        status: values.status,
        // 組織分類＋SEO 恆送（宣告式：空字串／空陣列＝清除，伺服端契約同語義）。
        vendor: values.vendor.trim(),
        productType: values.productType.trim(),
        tags: values.tags,
        seo: {
          title: values.seoTitle.trim(),
          description: values.seoDescription.trim(),
        },
        variants: [
          {
            price: centsToApiString(parseMoneyToCents(values.price) ?? null),
            ...(values.compare.trim()
              ? { compareAtPrice: centsToApiString(parseMoneyToCents(values.compare) ?? null) }
              : {}),
            ...(values.cost.trim()
              ? { cost: centsToApiString(parseMoneyToCents(values.cost) ?? null) }
              : {}),
            ...(values.sku.trim() ? { sku: values.sku.trim() } : {}),
            ...(values.barcode.trim() ? { barcode: values.barcode.trim() } : {}),
            taxable: values.taxable,
          },
        ],
      };
      if (isNew) {
        if (values.handle) input.handle = values.handle;
      } else {
        input.id = productGid;
        input.lockVersion = lockVersion;
      }

      const data = await requestAdminGraphQL<ProductSetData, Record<string, unknown>>(
        PRODUCT_SET_MUTATION,
        isNew ? { input, idempotencyKey: idempotencyKey.current } : { input },
      );

      const { product, userErrors } = data.productSet;
      if (userErrors.length > 0 || !product) {
        applyServerErrors(userErrors);
        return;
      }

      snapshot.current = JSON.stringify(values);
      showToast(t("product.saved"));
      if (isNew) {
        navigate("/admin/products");
      } else {
        // 編輯態留在頁上：吸收新 lockVersion，快照歸零 dirty。
        setLockVersion(product.lockVersion);
        setValues((current) => ({ ...current }));
      }
    } catch (reason: unknown) {
      // 鐵律 4 三層的另外兩層：top-level（THROTTLED／ACCESS_DENIED／
      // IDEMPOTENCY_KEY_REQUIRED）與非 200——都要有人話訊息，不得靜默空畫面。
      if (reason instanceof AdminGraphQLError) {
        showToast(reason.message);
      } else {
        showToast(reason instanceof Error ? reason.message : t("product.saveFailed"));
      }
    } finally {
      setSaving(false);
    }
  }, [applyServerErrors, isNew, lockVersion, navigate, productGid, saving, showToast, t, validate, values]);

  const discard = useCallback(() => {
    setValues(JSON.parse(snapshot.current) as FormValues);
    setErrors({});
    showToast(t("product.discarded"));
  }, [showToast, t]);

  // 封存／取消封存：狀態寫入 state 後由本 effect 立即觸發儲存（91 §1 本尊為即時動作）。
  useEffect(() => {
    if (!pendingAutoSave.current) return;
    pendingAutoSave.current = false;
    void save();
  }, [save, values.status]);

  const applyStatusAction = useCallback(
    (status: string) => {
      pendingAutoSave.current = true;
      setActionsOpen(false);
      setValue("status", status);
    },
    [setValue],
  );

  // SaveBar 註冊（topbar 渲染；離頁清除）。
  useEffect(() => {
    registerSaveBar({ dirty, saving, onSave: () => void save(), onDiscard: discard, shakeSignal });
    return () => registerSaveBar(null);
  }, [dirty, discard, registerSaveBar, save, saving, shakeSignal]);

  // guardNav（原型 §4453：dirty 首次攔截 shake＋toast，4 秒內再點同意離開）。
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

  const priceCents = parseMoneyToCents(values.price);
  const costCents = parseMoneyToCents(values.cost);
  const profit = profitState(
    typeof priceCents === "number" ? priceCents : null,
    typeof costCents === "number" ? costCents : null,
  );

  const bindField = (key: FieldKey) => (node: HTMLInputElement | null) => {
    fieldRefs.current[key] = node;
  };

  if (loadState === "loading") {
    return (
      <div className="cl-page cl-page--detail cl-product-detail">
        <p className="cl-card-note">{t("product.loading")}</p>
      </div>
    );
  }

  if (loadState === "missing") {
    return (
      <div className="cl-page cl-page--detail cl-product-detail">
        <Card padded>
          <h3>{t("product.notFound.title")}</h3>
          <p className="cl-card-note">{t("product.notFound.body")}</p>
          <Button onClick={() => navigate("/admin/products")}>{t("product.notFound.back")}</Button>
        </Card>
      </div>
    );
  }

  const statusBadge = STATUS_PRESENTATION[values.status] ?? STATUS_PRESENTATION.DRAFT;
  const dimensions = STATUS_DIMENSIONS[values.status] ?? STATUS_DIMENSIONS.DRAFT;

  // SERP 預覽（91 §11）：覆寫值優先，留空 fallback 商品標題／說明摘要。
  const serpHost = window.location.host;
  const serpTitle = values.seoTitle.trim() || values.title.trim();
  const serpDescription = (values.seoDescription.trim() || values.description.trim().replaceAll("\n", " "))
    .slice(0, SEO_DESCRIPTION_SERP);

  return (
    <div className="cl-page cl-page--detail cl-product-detail">
      <header className="cl-detail-head">
        <button
          aria-label={t("product.backToList")}
          className="cl-icon-button"
          onClick={() => navigate("/admin/products")}
          type="button"
        >
          <ArrowLeft aria-hidden="true" size={16} />
        </button>
        <h1>{isNew ? t("product.new") : values.title || t("product.untitled")}</h1>
        <Badge progress={statusBadge.progress} tone={statusBadge.tone}>
          {t(statusBadge.labelKey)}
        </Badge>
        {/* 內容語言 chip：建立一律在來源語言（67 §E.2）；編輯態的切換器屬多語言包 */}
        <span className="cl-locale-chip" title={t("product.contentLocale")}>
          English
        </span>
        <div className="cl-detail-head__actions">
          {isNew ? null : (
            <div className="cl-actionsmenu">
              <Button
                aria-expanded={actionsOpen}
                aria-haspopup="menu"
                onClick={() => setActionsOpen((state) => !state)}
              >
                {t("product.moreActions")} <MoreHorizontal aria-hidden="true" size={14} />
              </Button>
              {actionsOpen ? (
                <div className="cl-actionsmenu__list" role="menu">
                  <button className="cl-actionsmenu__item" disabled role="menuitem" title={t("product.duplicate.pending")} type="button">
                    {t("product.duplicate")}
                  </button>
                  {values.status === "ARCHIVED" ? (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => applyStatusAction("DRAFT")}
                      role="menuitem"
                      type="button"
                    >
                      {t("product.unarchive")}
                    </button>
                  ) : (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => applyStatusAction("ARCHIVED")}
                      role="menuitem"
                      type="button"
                    >
                      {t("product.archive")}
                    </button>
                  )}
                  <button
                    className="cl-actionsmenu__item cl-actionsmenu__item--danger"
                    disabled
                    role="menuitem"
                    title={t("product.delete.pending")}
                    type="button"
                  >
                    {t("product.delete")}
                  </button>
                </div>
              ) : null}
            </div>
          )}
          <Button loading={saving} loadingLabel={t("common.saving")} onClick={() => void save()} variant="primary">
            {t("common.save")}
          </Button>
        </div>
      </header>

      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          <Card padded>
            <h3>{t("product.card.titleDescription")}</h3>
            <TextField
              error={errors.title}
              hint={isNew ? t("product.field.title.hint") : undefined}
              label={t("product.field.title")}
              maxLength={255}
              onChange={(event) => setValue("title", event.target.value)}
              placeholder={t("product.field.title.placeholder")}
              ref={bindField("title")}
              value={values.title}
            />
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="product-description">
                {t("product.field.description")}
              </label>
              <div className="cl-rte-toolbar" title={t("product.rte.hint")}>
                <button className="cl-rte-tool" disabled type="button">
                  <Sparkles aria-hidden="true" size={13} /> {t("product.rte.ai")}
                </button>
              </div>
              <textarea
                className="cl-field__input cl-field__textarea"
                id="product-description"
                onChange={(event) => setValue("description", event.target.value)}
                rows={4}
                value={values.description}
              />
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.media")}</h3>
            <div className="cl-dropzone">
              <ImagePlus aria-hidden="true" size={20} />
              <div className="cl-dropzone__actions">
                <Button disabled size="small">
                  {t("product.media.upload")}
                </Button>
                <Button disabled size="small" variant="ghost">
                  {t("product.media.selectExisting")}
                </Button>
              </div>
              <p>{t("product.media.accept")}</p>
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.category")}</h3>
            <TextField
              disabled
              hint={t("product.category.hint")}
              label={t("product.category.label")}
              placeholder={t("product.category.placeholder")}
              value=""
            />
            <div className="cl-derow">
              <div className="cl-de">
                {t("product.category.taxRule")} <b className="cl-de--unknown">--</b>
              </div>
              <div className="cl-de">
                {t("product.category.metafields")} <b className="cl-de--unknown">--</b>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.pricing")}</h3>
            <TextField
              error={errors.price}
              inputMode="decimal"
              label={t("product.price.label")}
              onChange={(event) => setValue("price", event.target.value)}
              placeholder="0.00"
              ref={bindField("price")}
              value={values.price}
            />
            <div className="cl-pillset">
              <PillGroup
                onToggle={togglePill}
                open={openPills}
                pills={[
                  { key: "compare", label: t("product.pill.compare"), value: values.compare || undefined },
                  { key: "unit", label: t("product.pill.unit") },
                  { key: "tax", label: t("product.pill.tax"), value: values.taxable ? t("common.yes") : t("common.no") },
                  { key: "cost", label: t("product.pill.cost"), value: values.cost || undefined },
                ]}
              />
              {openPills.has("compare") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.compare}
                    hint={t("product.compare.hint")}
                    inputMode="decimal"
                    label={t("product.compare.label")}
                    onChange={(event) => setValue("compare", event.target.value)}
                    placeholder={t("product.compare.placeholder")}
                    ref={bindField("compare")}
                    value={values.compare}
                  />
                </div>
              ) : null}
              {openPills.has("unit") ? (
                <div className="cl-pillpanel">
                  <div className="cl-field">
                    <label className="cl-field__label" htmlFor="unit-pricing">
                      {t("product.unit.label")}
                    </label>
                    <select className="cl-field__input" disabled id="unit-pricing">
                      <option>{t("product.unit.off")}</option>
                      <option>{t("product.unit.per100ml")}</option>
                      <option>{t("product.unit.per100g")}</option>
                      <option>{t("product.unit.per1kg")}</option>
                      <option>{t("product.unit.per1m")}</option>
                    </select>
                  </div>
                </div>
              ) : null}
              {openPills.has("tax") ? (
                <div className="cl-pillpanel">
                  <label className="cl-checkrow">
                    <input
                      checked={values.taxable}
                      onChange={(event) => setValue("taxable", event.target.checked)}
                      type="checkbox"
                    />
                    {t("product.tax.checkbox")}
                  </label>
                </div>
              ) : null}
              {openPills.has("cost") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.cost}
                    hint={t("product.cost.hint")}
                    inputMode="decimal"
                    label={t("product.cost.label")}
                    onChange={(event) => setValue("cost", event.target.value)}
                    placeholder="0.00"
                    ref={bindField("cost")}
                    value={values.cost}
                  />
                  <div className="cl-derow">
                    <div className="cl-de">
                      {t("product.profit")}{" "}
                      {profit.profit === null ? (
                        <b className="cl-de--unknown">--</b>
                      ) : (
                        <b className="cl-num">{centsToApiString(profit.profit)}</b>
                      )}
                    </div>
                    <div className="cl-de">
                      {t("product.margin")}{" "}
                      {profit.margin === null ? (
                        <b className="cl-de--unknown">--</b>
                      ) : (
                        <b className="cl-num">{profit.margin}%</b>
                      )}
                    </div>
                  </div>
                </div>
              ) : null}
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.inventory")}</h3>
            <SwitchRow checked disabled hint={t("product.inventory.tracked.hint")} label={t("product.inventory.tracked")} />
            {isNew ? (
              <div className="cl-grid2">
                <TextField disabled hint={t("product.inventory.quantity.hint")} label={t("product.inventory.quantity")} value="0" />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="inventory-location">
                    {t("product.inventory.location")}
                  </label>
                  <select className="cl-field__input" disabled id="inventory-location">
                    <option>Shop location</option>
                  </select>
                </div>
              </div>
            ) : null}
            <div className="cl-pillset">
              <PillGroup
                onToggle={togglePill}
                open={openPills}
                pills={[
                  { key: "sku", label: t("product.pill.sku"), value: values.sku || undefined },
                  { key: "barcode", label: t("product.pill.barcode"), value: values.barcode || undefined },
                  { key: "continue", label: t("product.pill.continue") },
                ]}
              />
              {openPills.has("sku") ? (
                <div className="cl-pillpanel">
                  <TextField
                    hint={t("product.sku.hint")}
                    label={t("product.sku.label")}
                    maxLength={64}
                    onChange={(event) => setValue("sku", event.target.value)}
                    value={values.sku}
                  />
                </div>
              ) : null}
              {openPills.has("barcode") ? (
                <div className="cl-pillpanel">
                  <TextField
                    label={t("product.barcode.label")}
                    onChange={(event) => setValue("barcode", event.target.value)}
                    value={values.barcode}
                  />
                </div>
              ) : null}
              {openPills.has("continue") ? (
                <div className="cl-pillpanel">
                  <label className="cl-checkrow">
                    <input disabled type="checkbox" />
                    {t("product.continue.checkbox")}
                  </label>
                </div>
              ) : null}
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.shipping")}</h3>
            <label className="cl-checkrow">
              <input defaultChecked disabled type="checkbox" />
              {t("product.shipping.physical")}
            </label>
            <div className="cl-grid2">
              <TextField disabled label={t("product.shipping.weight")} placeholder="0.00" value="" />
              <div className="cl-field">
                <label className="cl-field__label" htmlFor="shipping-package">
                  {t("product.shipping.package")}
                </label>
                <select className="cl-field__input" disabled id="shipping-package">
                  <option>{t("product.shipping.packageDefault")}</option>
                </select>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>
              {t("product.card.variants")}
              <span className="cl-card__head-action">
                <Button disabled size="small" title={t("product.variants.add.pending")}>
                  {t("product.variants.add")}
                </Button>
              </span>
            </h3>
            <p className="cl-card-note">{t("product.variants.note")}</p>
          </Card>

          <Card padded>
            <h3>{t("product.card.purchaseOptions")}</h3>
            <div className="cl-detail-head__actions cl-purchase-options">
              {[
                t("product.purchase.subscription"),
                t("product.purchase.preorder"),
                t("product.purchase.tryBeforeBuy"),
              ].map((label) => (
                <Button key={label} onClick={() => showToast(t("common.comingSoon", { label }))} size="small">
                  {label}
                </Button>
              ))}
            </div>
          </Card>

          <Card padded>
            <h3>
              {t("product.card.seo")}
              <span className="cl-card__head-action">
                <button
                  aria-expanded={seoOpen}
                  aria-label={t("product.seo.edit")}
                  className="cl-icon-button"
                  onClick={() => setSeoOpen((state) => !state)}
                  type="button"
                >
                  <Pencil aria-hidden="true" size={14} />
                </button>
              </span>
            </h3>
            {/* SERP 預覽（91 §11 收合態）：站名 → 麵包屑 URL → 標題連結 → 描述 → 價格列。 */}
            {serpTitle ? (
              <div className="cl-serp">
                <div className="cl-serp__site">CHILL LOVE</div>
                <div className="cl-serp__url">
                  {serpHost} › products › {values.handle || "…"}
                </div>
                <div className="cl-serp__title">{serpTitle}</div>
                {serpDescription ? <div className="cl-serp__desc">{serpDescription}</div> : null}
                {values.price.trim() ? (
                  <div className="cl-serp__price">HK${values.price.trim()} HKD</div>
                ) : null}
              </div>
            ) : (
              <p className="cl-card-note">{t("product.seo.empty")}</p>
            )}
            {seoOpen ? (
              <>
                <TextField
                  error={errors.seoTitle}
                  hint={t("product.seo.pageTitle.hint", { used: values.seoTitle.length, max: SEO_TITLE_MAX })}
                  label={t("product.seo.pageTitle")}
                  maxLength={SEO_TITLE_MAX}
                  onChange={(event) => setValue("seoTitle", event.target.value)}
                  ref={bindField("seoTitle")}
                  value={values.seoTitle}
                />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="seo-description">
                    {t("product.seo.meta")}
                  </label>
                  <textarea
                    aria-invalid={errors.seoDescription ? true : undefined}
                    className="cl-field__input cl-field__textarea"
                    id="seo-description"
                    maxLength={SEO_DESCRIPTION_MAX}
                    onChange={(event) => setValue("seoDescription", event.target.value)}
                    rows={3}
                    value={values.seoDescription}
                  />
                  {/* 160 是 SERP 建議值不是上限（91 §11：本尊 203/160 照樣可存；硬上限 320）。 */}
                  {errors.seoDescription ? (
                    <p className="cl-field__error">{errors.seoDescription}</p>
                  ) : (
                    <p className="cl-field__hint">
                      {t("product.seo.meta.hint", {
                        used: values.seoDescription.length,
                        serp: SEO_DESCRIPTION_SERP,
                        max: SEO_DESCRIPTION_MAX,
                      })}
                    </p>
                  )}
                </div>
                <TextField
                  disabled={!isNew}
                  error={errors.handle}
                  hint={isNew ? t("product.seo.handle.hintNew") : t("product.seo.handle.hintEdit")}
                  label={t("product.seo.handle")}
                  onChange={(event) => setValue("handle", event.target.value)}
                  placeholder={t("product.seo.handle.placeholder")}
                  ref={bindField("handle")}
                  value={values.handle}
                />
              </>
            ) : null}
          </Card>
        </div>

        <div className="cl-od-grid__aside">
          {isNew ? null : (
            <Card padded>
              <h3>{t("product.card.status")}</h3>
              <div className="cl-field">
                <span className="cl-field__label" id="product-status-label">
                  {t("product.status.label")}
                </span>
                {/* 91 §2：listbox 每項帶描述副行；封存不在清單（走更多動作）。 */}
                <StatusListbox
                  labelId="product-status-label"
                  onChange={(next) => setValue("status", next)}
                  value={values.status}
                />
              </div>
              {/* 兩維讀值（13 §F1.2）：是/否文字本身承載語意，顏色只加速掃視 */}
              <div className="cl-derow">
                <div className="cl-de">
                  {t("product.status.purchasable")} <b className={dimensions.purchasable ? "" : "cl-de--unknown"}>{dimensions.purchasable ? t("common.yes") : t("common.no")}</b>
                </div>
                <div className="cl-de">
                  {t("product.status.discoverable")} <b className={dimensions.discoverable ? "" : "cl-de--unknown"}>{dimensions.discoverable ? t("common.yes") : t("common.no")}</b>
                </div>
              </div>
            </Card>
          )}
          <Card padded>
            <h3>{t("product.card.publishing")}</h3>
            <SwitchRow checked disabled hint={t("product.publishing.onlineStore.hint")} label={t("product.publishing.onlineStore")} />
            <SwitchRow checked disabled label={t("product.publishing.agent")} />
            <SwitchRow checked={false} disabled label={t("product.publishing.pos")} />
          </Card>
          {/* 組織分類卡（91 §12：類型 search-or-create、廠商 autocomplete、標籤 token、佈景範本）。 */}
          <Card padded>
            <h3>{t("product.card.organization")}</h3>
            <TextField
              error={errors.productType}
              label={t("product.org.type")}
              list="product-type-suggestions"
              maxLength={255}
              onChange={(event) => setValue("productType", event.target.value)}
              placeholder={t("product.org.type.placeholder")}
              ref={bindField("productType")}
              value={values.productType}
            />
            <datalist id="product-type-suggestions">
              {suggestions.productTypes.map((type) => (
                <option key={type} value={type} />
              ))}
            </datalist>
            <TextField
              error={errors.vendor}
              label={t("product.org.vendor")}
              list="product-vendor-suggestions"
              maxLength={255}
              onChange={(event) => setValue("vendor", event.target.value)}
              ref={bindField("vendor")}
              value={values.vendor}
            />
            <datalist id="product-vendor-suggestions">
              {suggestions.productVendors.map((vendor) => (
                <option key={vendor} value={vendor} />
              ))}
            </datalist>
            <TagsField
              onChange={(tags) => setValue("tags", tags)}
              suggestions={[]}
              tags={values.tags}
            />
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="theme-template">
                {t("product.org.template")}
              </label>
              <select className="cl-field__input" disabled id="theme-template">
                <option>{t("product.org.template.default")}</option>
              </select>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
