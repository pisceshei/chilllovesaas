import { useId, useState } from "react";
import type { ReactNode } from "react";
import { useT } from "../i18n/I18nContext";
import { TextField } from "./TextField";

/**
 * 內容語言的輸入元件（docs/specs/67 §E.2-1；ML-2）。
 *
 * 兩種佈局、**同一個資料契約**（都寫 translations 的 (locale, field) 列——
 * `mode_does_not_affect_schema`；分頁式若被實作成「一語言一份 JSON blob」，
 * 欄位級 digest／outdated／進度分子／翻譯 CSV 會一起壞，且要到匯出才發現）：
 *
 * - `stacked`：短單行欄位（標題）。N 個輸入框並列、各標語言 endonym。
 *   🔴 一次看完所有語言，才看得出「譯錯語言／貼錯欄位／漏一語」——這是
 *   §E.1 那個事故（把中文打進英文版標題）的視覺防線。
 * - `tabbed`：長內容／富文本／一組要一起看的欄位（說明、SEO 標題＋描述）。
 *   **單一編輯器實例＋語言 tab**（不是 N 個實例：N 個 RTE ＝ N 條工具列與載入成本）。
 *
 * 來源語言那一格恆在第一位且必填（裁定 C4：資料以英文為主）。
 */
export interface LocalizedValue {
  /** BCP-47 → 值；來源語言的值就是 base row 的值。 */
  [locale: string]: string;
}

export interface LocaleOption {
  tag: string;
  /** 語言自稱（不用國旗、不用語言碼；67 §E.2-1 硬規則 2）。 */
  endonym: string;
  /** 該語言此欄位的譯文是否已過期（來源文字變更）。 */
  outdated?: boolean;
}

export interface LocalizedFieldProps {
  label: string;
  /** 已啟用語言（含來源語言，來源語言必須排第一）。 */
  locales: readonly LocaleOption[];
  sourceLocale: string;
  values: LocalizedValue;
  onChange: (locale: string, value: string) => void;
  /** 單行輸入的額外屬性（maxLength／placeholder…）。 */
  maxLength?: number;
  placeholder?: string;
  error?: string;
  hint?: string;
  /** 來源語言欄位的 ref（驗證失敗 focus 用）。 */
  sourceRef?: (node: HTMLInputElement | null) => void;
  /** tabbed 模式下每個 tab 的內容（自行渲染 textarea／RTE）；省略時用單行輸入。 */
  renderTabbed?: (locale: string, value: string, onValueChange: (next: string) => void) => ReactNode;
  mode: "stacked" | "tabbed";
}

/** 過期徽章：橙點＋說明；**不影響前台渲染**（67 §C.5），只提示商家。 */
function OutdatedDot({ title }: { title: string }) {
  return <span aria-label={title} className="cl-locale-dot cl-locale-dot--outdated" title={title} />;
}

export function LocalizedField({
  label,
  locales,
  sourceLocale,
  values,
  onChange,
  maxLength,
  placeholder,
  error,
  hint,
  sourceRef,
  renderTabbed,
  mode,
}: LocalizedFieldProps) {
  const t = useT();
  const groupId = useId();
  const [activeTab, setActiveTab] = useState(sourceLocale);

  if (mode === "stacked") {
    return (
      <div className="cl-localized cl-localized--stacked" role="group">
        {locales.map((locale) => {
          const isSource = locale.tag === sourceLocale;
          return (
            <TextField
              error={isSource ? error : undefined}
              hint={isSource ? hint : undefined}
              key={locale.tag}
              label={`${label}（${locale.endonym}）`}
              lang={locale.tag}
              maxLength={maxLength}
              onChange={(event) => onChange(locale.tag, event.target.value)}
              placeholder={isSource ? placeholder : t("i18n.field.fallbackPlaceholder")}
              ref={isSource ? sourceRef : undefined}
              required={isSource || undefined}
              value={values[locale.tag] ?? ""}
            />
          );
        })}
      </div>
    );
  }

  const activeValue = values[activeTab] ?? "";
  return (
    <div className="cl-localized cl-localized--tabbed">
      <div className="cl-field__label">{label}</div>
      <div aria-label={t("i18n.field.localeTabs")} className="cl-locale-tabs" role="tablist">
        {locales.map((locale) => (
          <button
            aria-controls={`${groupId}-panel`}
            aria-selected={locale.tag === activeTab}
            className={`cl-locale-tab ${locale.tag === activeTab ? "cl-locale-tab--active" : ""}`}
            key={locale.tag}
            lang={locale.tag}
            onClick={() => setActiveTab(locale.tag)}
            role="tab"
            type="button"
          >
            {locale.endonym}
            {locale.outdated ? <OutdatedDot title={t("i18n.field.outdated")} /> : null}
            {locale.tag !== sourceLocale && (values[locale.tag] ?? "").trim() === "" ? (
              <span aria-label={t("i18n.field.empty")} className="cl-locale-dot" title={t("i18n.field.empty")} />
            ) : null}
          </button>
        ))}
      </div>
      <div className="cl-locale-panel" id={`${groupId}-panel`} role="tabpanel">
        {activeTab !== sourceLocale ? (
          // 非來源語言：上方顯示原文供對照（§E.2 的「上原文／下譯文」雙段形態）。
          <details className="cl-locale-source">
            <summary>{t("i18n.field.showSource")}</summary>
            <p lang={sourceLocale}>{values[sourceLocale] || t("i18n.field.sourceEmpty")}</p>
          </details>
        ) : null}
        {renderTabbed ? (
          renderTabbed(activeTab, activeValue, (next) => onChange(activeTab, next))
        ) : (
          <TextField
            error={activeTab === sourceLocale ? error : undefined}
            hint={activeTab === sourceLocale ? hint : undefined}
            label={`${label}（${locales.find((locale) => locale.tag === activeTab)?.endonym ?? activeTab}）`}
            labelHidden
            lang={activeTab}
            maxLength={maxLength}
            onChange={(event) => onChange(activeTab, event.target.value)}
            placeholder={activeTab === sourceLocale ? placeholder : t("i18n.field.fallbackPlaceholder")}
            value={activeValue}
          />
        )}
      </div>
    </div>
  );
}
