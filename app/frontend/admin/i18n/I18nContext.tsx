import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { ReactNode } from "react";
import { formatMessage } from "./format";
import type { MessageValues } from "./format";
import { DEFAULT_UI_LOCALE, coerceUiLocale } from "./locales";
import type { UiLocale } from "./locales";
import en from "./messages/en.json";
import fr from "./messages/fr.json";
import ja from "./messages/ja.json";
import zhHans from "./messages/zh-Hans.json";
import zhHant from "./messages/zh-Hant.json";

/**
 * 平台 UI 字串 bundle（67 §E.1：隨版本部署、跨租戶共用，**不進租戶 translations 表**）。
 * 🔴 `en` 是 key 的正典；其餘四檔 key 集合必須與 en 完全相同（`i18n/messages.test.ts` 擋）。
 * 五檔靜態 import（合計數十 KB）；之後需要再改 code-split，不在本包。
 */
const MESSAGES: Record<UiLocale, Record<string, string>> = {
  en,
  fr,
  ja,
  "zh-Hans": zhHans,
  "zh-Hant": zhHant,
};

export type Translate = (key: string, values?: MessageValues) => string;

interface I18nContextValue {
  locale: UiLocale;
  t: Translate;
  setLocale: (next: UiLocale) => void;
}

const I18nContext = createContext<I18nContextValue | null>(null);

/**
 * 介面語言 Provider。`initialLocale` 來自 Rails 注入（`staff_members.locale`），
 * 切換由 `useSetUiLocale` 觸發（AdminShell 的切換器先打 `staffLocaleUpdate` 再呼叫）。
 */
export function I18nProvider({ initialLocale, children }: { initialLocale?: string; children: ReactNode }) {
  const [locale, setLocaleState] = useState<UiLocale>(() => coerceUiLocale(initialLocale));

  // `<html lang>` 跟介面語言（無障礙／拼字檢查／字型 fallback 都看它）。
  useEffect(() => {
    document.documentElement.lang = locale;
  }, [locale]);

  const t = useCallback<Translate>(
    (key, values) => {
      const message = MESSAGES[locale][key] ?? MESSAGES[DEFAULT_UI_LOCALE][key];
      if (message === undefined) {
        // 缺鍵不得靜默空白（原則 2）：回 key 本身，畫面上看得到、測試抓得到。
        return key;
      }
      return formatMessage(message, values, locale);
    },
    [locale],
  );

  const setLocale = useCallback((next: UiLocale) => setLocaleState(coerceUiLocale(next)), []);
  const value = useMemo(() => ({ locale, t, setLocale }), [locale, t, setLocale]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

function useI18n(): I18nContextValue {
  const context = useContext(I18nContext);
  if (!context) throw new Error("useT must be used inside <I18nProvider>.");
  return context;
}

/** 取翻譯函式。 */
export function useT(): Translate {
  return useI18n().t;
}

/** 目前介面語言（BCP-47）。 */
export function useUiLocale(): UiLocale {
  return useI18n().locale;
}

/** 切換介面語言（只改前端狀態；持久化由呼叫端先完成）。 */
export function useSetUiLocale(): (next: UiLocale) => void {
  return useI18n().setLocale;
}

/** 給非 React 程式碼／測試用的純函式（不含 Provider 狀態）。 */
export function translateWith(locale: UiLocale): Translate {
  return (key, values) => {
    const message = MESSAGES[locale][key] ?? MESSAGES[DEFAULT_UI_LOCALE][key];
    return message === undefined ? key : formatMessage(message, values, locale);
  };
}

/** 測試用：所有 bundle（key 同構檢查）。 */
export const ALL_MESSAGES = MESSAGES;
