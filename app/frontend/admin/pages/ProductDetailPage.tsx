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
const STATUS_OPTIONS: { value: string; label: string; hint: string }[] = [
  { value: "ACTIVE", label: "啟用中", hint: "可販售也可被發現：進搜尋、系列與 sitemap" },
  { value: "DRAFT", label: "草稿", hint: "尚未備妥：顧客在任何管道都取用不到" },
  { value: "UNLISTED", label: "未列出", hint: "可購買但不被發現：僅能透過直接連結存取" },
];

/** 封存態只在目前狀態＝ARCHIVED 時出現在 listbox（顯示用；解除走選其他值）。 */
const ARCHIVED_OPTION = { value: "ARCHIVED", label: "已封存", hint: "已停售：選擇其他狀態即取消封存" };

/** SEO 計數器的 SERP 建議值（不是上限；上限＝伺服端 70／320，91 §11）。 */
const SEO_TITLE_MAX = 70;
const SEO_DESCRIPTION_SERP = 160;
const SEO_DESCRIPTION_MAX = 320;

/**
 * 狀態呈現（正典＝原型 P_STATUS，chilllove-admin-v2.html:3105；
 * 與 ProductsPage 同表——文案與 pip 不得漂移）。
 */
const STATUS_PRESENTATION: Record<string, { label: string; progress: BadgeProgress; tone: BadgeTone }> = {
  ACTIVE: { label: "啟用中", progress: "full", tone: "success" },
  ARCHIVED: { label: "已封存", progress: "full", tone: "default" },
  DRAFT: { label: "草稿", progress: "empty", tone: "info" },
  UNLISTED: { label: "未列出", progress: "empty", tone: "attention" },
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
        {current.label}
        <ChevronDown aria-hidden="true" size={14} />
      </button>
      {open ? (
        <ul aria-label="商品狀態" className="cl-statusbox__list" id={listId} role="listbox">
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
                {option.label}
                <span>{option.hint}</span>
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
        標籤
      </label>
      {tags.length > 0 ? (
        <div className="cl-chips">
          {tags.map((tag) => (
            <span className="cl-chip" key={tag}>
              {tag}
              <button
                aria-label={`移除標籤 ${tag}`}
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
        placeholder="以 Enter 或逗號加入"
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
        showToast(reason instanceof Error ? reason.message : "無法載入商品。");
        setLoadState("missing");
      });

    return () => controller.abort();
  }, [isNew, productGid, showToast]);

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
    if (!values.title.trim()) found.title = "標題不能為空白。";
    else if (values.title.length > 255) found.title = "標題長度超過上限（255）。";

    if (!values.price.trim()) found.price = "價格必填。";
    else if (!isValidMoneyInput(values.price)) {
      found.price = "請輸入有效金額（最多兩位小數，不含幣別符號）";
    }
    if (!isValidMoneyInput(values.compare)) {
      found.compare = "請輸入有效金額（最多兩位小數，不含幣別符號）";
    }
    if (!isValidMoneyInput(values.cost)) {
      found.cost = "請輸入有效金額（最多兩位小數，不含幣別符號）";
    }
    if (isNew && values.handle && !/^[a-z0-9-]+$/.test(values.handle)) {
      found.handle = "handle 只能包含小寫字母、數字與連字號。";
    }
    if (values.seoTitle.length > SEO_TITLE_MAX) {
      found.seoTitle = `SEO 標題超過 ${SEO_TITLE_MAX} 字元上限。`;
    }
    if (values.seoDescription.length > SEO_DESCRIPTION_MAX) {
      found.seoDescription = `Meta 描述超過 ${SEO_DESCRIPTION_MAX} 字元上限。`;
    }

    setErrors(found);
    const firstBad = (Object.keys(found) as FieldKey[])[0];
    if (firstBad) {
      showToast("有欄位未通過驗證");
      setShakeSignal((signal) => signal + 1);
      fieldRefs.current[firstBad]?.focus();
      return false;
    }
    return true;
  }, [isNew, showToast, values]);

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
      showToast(unmapped[0] ?? "有欄位未通過驗證");
      setShakeSignal((signal) => signal + 1);
      const firstBad = (Object.keys(mapped) as FieldKey[])[0];
      fieldRefs.current[firstBad ?? "title"]?.focus();
    },
    [showToast],
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
      showToast("已儲存變更");
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
        showToast(reason instanceof Error ? reason.message : "儲存失敗，請稍後再試。");
      }
    } finally {
      setSaving(false);
    }
  }, [applyServerErrors, isNew, lockVersion, navigate, productGid, saving, showToast, validate, values]);

  const discard = useCallback(() => {
    setValues(JSON.parse(snapshot.current) as FormValues);
    setErrors({});
    showToast("已捨棄變更，還原為上次儲存的內容");
  }, [showToast]);

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
    showToast("有未儲存的變更——再點一次即離開並捨棄");
    setShakeSignal((signal) => signal + 1);
    blocker.reset();
  }, [blocker, showToast]);

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
        <p className="cl-card-note">載入中…</p>
      </div>
    );
  }

  if (loadState === "missing") {
    return (
      <div className="cl-page cl-page--detail cl-product-detail">
        <Card padded>
          <h3>找不到商品</h3>
          <p className="cl-card-note">此商品不存在或已被刪除。</p>
          <Button onClick={() => navigate("/admin/products")}>返回商品列表</Button>
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
          aria-label="返回商品列表"
          className="cl-icon-button"
          onClick={() => navigate("/admin/products")}
          type="button"
        >
          <ArrowLeft aria-hidden="true" size={16} />
        </button>
        <h1>{isNew ? "新增商品" : values.title || "商品"}</h1>
        <Badge progress={statusBadge.progress} tone={statusBadge.tone}>
          {statusBadge.label}
        </Badge>
        {/* 內容語言 chip：建立一律在來源語言（67 §E.2）；編輯態的切換器屬多語言包 */}
        <span className="cl-locale-chip" title="內容語言">
          繁體中文
        </span>
        <div className="cl-detail-head__actions">
          {isNew ? null : (
            <div className="cl-actionsmenu">
              <Button
                aria-expanded={actionsOpen}
                aria-haspopup="menu"
                onClick={() => setActionsOpen((state) => !state)}
              >
                更多動作 <MoreHorizontal aria-hidden="true" size={14} />
              </Button>
              {actionsOpen ? (
                <div className="cl-actionsmenu__list" role="menu">
                  <button className="cl-actionsmenu__item" disabled role="menuitem" title="複製屬後續包" type="button">
                    複製商品
                  </button>
                  {values.status === "ARCHIVED" ? (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => applyStatusAction("DRAFT")}
                      role="menuitem"
                      type="button"
                    >
                      取消封存商品
                    </button>
                  ) : (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => applyStatusAction("ARCHIVED")}
                      role="menuitem"
                      type="button"
                    >
                      封存商品
                    </button>
                  )}
                  <button
                    className="cl-actionsmenu__item cl-actionsmenu__item--danger"
                    disabled
                    role="menuitem"
                    title="刪除屬後續包"
                    type="button"
                  >
                    刪除商品
                  </button>
                </div>
              ) : null}
            </div>
          )}
          <Button loading={saving} loadingLabel="儲存中…" onClick={() => void save()} variant="primary">
            儲存
          </Button>
        </div>
      </header>

      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          <Card padded>
            <h3>標題與說明</h3>
            <TextField
              error={errors.title}
              hint={isNew ? "儲存時自動生成 handle 並唯一化" : undefined}
              label="標題"
              maxLength={255}
              onChange={(event) => setValue("title", event.target.value)}
              placeholder="例：奶茶色寬版帽T"
              ref={bindField("title")}
              value={values.title}
            />
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="product-description">
                說明
              </label>
              <div className="cl-rte-toolbar" title="富文本工具列（媒體里程碑開放）">
                <button className="cl-rte-tool" disabled type="button">
                  <Sparkles aria-hidden="true" size={13} /> AI 生成
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
            <h3>多媒體</h3>
            <div className="cl-dropzone">
              <ImagePlus aria-hidden="true" size={20} />
              <div className="cl-dropzone__actions">
                <Button disabled size="small">
                  上傳新檔案
                </Button>
                <Button disabled size="small" variant="ghost">
                  選取現有檔案
                </Button>
              </div>
              <p>接受圖片、影片或 3D 模型（媒體里程碑開放）</p>
            </div>
          </Card>

          <Card padded>
            <h3>商品類別</h3>
            <TextField
              disabled
              hint="未選時適用稅則與中繼欄位顯示 --（分類里程碑開放）"
              label="類別"
              placeholder="搜尋標準分類…"
              value=""
            />
            <div className="cl-derow">
              <div className="cl-de">
                適用稅則 <b className="cl-de--unknown">--</b>
              </div>
              <div className="cl-de">
                中繼欄位 <b className="cl-de--unknown">--</b>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>定價</h3>
            <TextField
              error={errors.price}
              inputMode="decimal"
              label="價格（HK$）"
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
                  { key: "compare", label: "比較價格", value: values.compare || undefined },
                  { key: "unit", label: "單價" },
                  { key: "tax", label: "收取稅金", value: values.taxable ? "是" : "否" },
                  { key: "cost", label: "每品項成本", value: values.cost || undefined },
                ]}
              />
              {openPills.has("compare") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.compare}
                    hint="高於售價時前台顯示劃線價"
                    inputMode="decimal"
                    label="原價（劃線價）"
                    onChange={(event) => setValue("compare", event.target.value)}
                    placeholder="選填"
                    ref={bindField("compare")}
                    value={values.compare}
                  />
                </div>
              ) : null}
              {openPills.has("unit") ? (
                <div className="cl-pillpanel">
                  <div className="cl-field">
                    <label className="cl-field__label" htmlFor="unit-pricing">
                      單位定價
                    </label>
                    <select className="cl-field__input" disabled id="unit-pricing">
                      <option>不啟用</option>
                      <option>每 100 ml</option>
                      <option>每 100 g</option>
                      <option>每 1 kg</option>
                      <option>每 1 m</option>
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
                    收取稅金（課不課由 jurisdiction pack 決定）
                  </label>
                </div>
              ) : null}
              {openPills.has("cost") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.cost}
                    hint="不對顧客顯示"
                    inputMode="decimal"
                    label="每品項成本"
                    onChange={(event) => setValue("cost", event.target.value)}
                    placeholder="0.00"
                    ref={bindField("cost")}
                    value={values.cost}
                  />
                  <div className="cl-derow">
                    <div className="cl-de">
                      利潤{" "}
                      {profit.profit === null ? (
                        <b className="cl-de--unknown">--</b>
                      ) : (
                        <b className="cl-num">{centsToApiString(profit.profit)}</b>
                      )}
                    </div>
                    <div className="cl-de">
                      利潤率{" "}
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
            <h3>庫存</h3>
            <SwitchRow checked disabled hint="關閉時不寫 ledger（庫存里程碑開放）" label="已追蹤庫存" />
            {isNew ? (
              <div className="cl-grid2">
                <TextField disabled hint="庫存里程碑開放" label="數量" value="0" />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="inventory-location">
                    地點
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
                  { key: "sku", label: "SKU", value: values.sku || undefined },
                  { key: "barcode", label: "條碼", value: values.barcode || undefined },
                  { key: "continue", label: "無庫存時繼續銷售" },
                ]}
              />
              {openPills.has("sku") ? (
                <div className="cl-pillpanel">
                  <TextField
                    hint="軟唯一：重複時警告但不阻擋"
                    label="SKU（庫存單位）"
                    maxLength={64}
                    onChange={(event) => setValue("sku", event.target.value)}
                    value={values.sku}
                  />
                </div>
              ) : null}
              {openPills.has("barcode") ? (
                <div className="cl-pillpanel">
                  <TextField
                    label="條碼（ISBN、UPC、GTIN 等）"
                    onChange={(event) => setValue("barcode", event.target.value)}
                    value={values.barcode}
                  />
                </div>
              ) : null}
              {openPills.has("continue") ? (
                <div className="cl-pillpanel">
                  <label className="cl-checkrow">
                    <input disabled type="checkbox" />
                    售完後仍可繼續銷售（庫存里程碑開放）
                  </label>
                </div>
              ) : null}
            </div>
          </Card>

          <Card padded>
            <h3>運送</h3>
            <label className="cl-checkrow">
              <input defaultChecked disabled type="checkbox" />
              這是實體商品（運送里程碑開放）
            </label>
            <div className="cl-grid2">
              <TextField disabled label="商品重量（kg）" placeholder="0.00" value="" />
              <div className="cl-field">
                <label className="cl-field__label" htmlFor="shipping-package">
                  包材
                </label>
                <select className="cl-field__input" disabled id="shipping-package">
                  <option>商店預設・樣品盒</option>
                </select>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>
              子類
              <span className="cl-card__head-action">
                <Button disabled size="small" title="具名選項屬變體里程碑">
                  ＋ 新增子類
                </Button>
              </span>
            </h3>
            <p className="cl-card-note">新增尺寸、顏色等選項後，變體以選項值組合生成（≤2048）。</p>
          </Card>

          <Card padded>
            <h3>購買選項</h3>
            <div className="cl-detail-head__actions cl-purchase-options">
              {["訂閱", "預購", "先試後買"].map((label) => (
                <Button key={label} onClick={() => showToast(`${label}：功能準備中`)} size="small">
                  {label}
                </Button>
              ))}
            </div>
          </Card>

          <Card padded>
            <h3>
              搜尋引擎產品資訊
              <span className="cl-card__head-action">
                <button
                  aria-expanded={seoOpen}
                  aria-label="編輯搜尋引擎產品資訊"
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
              <p className="cl-card-note">尚無可預覽的內容——填寫標題後這裡會顯示搜尋結果預覽。</p>
            )}
            {seoOpen ? (
              <>
                <TextField
                  error={errors.seoTitle}
                  hint={`已使用 ${values.seoTitle.length} / ${SEO_TITLE_MAX} 個字元；留空時沿用商品標題`}
                  label="頁面標題"
                  maxLength={SEO_TITLE_MAX}
                  onChange={(event) => setValue("seoTitle", event.target.value)}
                  ref={bindField("seoTitle")}
                  value={values.seoTitle}
                />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="seo-description">
                    Meta 描述
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
                      已使用 {values.seoDescription.length} / {SEO_DESCRIPTION_SERP} 個字元；超過會被搜尋結果截斷（上限 {SEO_DESCRIPTION_MAX}）
                    </p>
                  )}
                </div>
                <TextField
                  disabled={!isNew}
                  error={errors.handle}
                  hint={
                    isNew
                      ? "儲存時由英文標題自動生成；手填衝突會被拒絕"
                      : "handle 變更需 301 轉址（URL 里程碑開放）"
                  }
                  label="網址 handle"
                  onChange={(event) => setValue("handle", event.target.value)}
                  placeholder="自動生成"
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
              <h3>狀態</h3>
              <div className="cl-field">
                <span className="cl-field__label" id="product-status-label">
                  商品狀態
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
                  可購買 <b className={dimensions.purchasable ? "" : "cl-de--unknown"}>{dimensions.purchasable ? "是" : "否"}</b>
                </div>
                <div className="cl-de">
                  可被發現 <b className={dimensions.discoverable ? "" : "cl-de--unknown"}>{dimensions.discoverable ? "是" : "否"}</b>
                </div>
              </div>
            </Card>
          )}
          <Card padded>
            <h3>發布</h3>
            <SwitchRow checked disabled hint="排程上線：立即（發布里程碑開放）" label="線上商店" />
            <SwitchRow checked disabled label="AI 代理" />
            <SwitchRow checked={false} disabled label="門市 POS" />
          </Card>
          {/* 組織分類卡（91 §12：類型 search-or-create、廠商 autocomplete、標籤 token、佈景範本）。 */}
          <Card padded>
            <h3>組織分類</h3>
            <TextField
              error={errors.productType}
              label="產品類型"
              list="product-type-suggestions"
              maxLength={255}
              onChange={(event) => setValue("productType", event.target.value)}
              placeholder="搜尋或新增產品類型"
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
              label="廠商"
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
                佈景主題範本
              </label>
              <select className="cl-field__input" disabled id="theme-template">
                <option>預設商品</option>
              </select>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
