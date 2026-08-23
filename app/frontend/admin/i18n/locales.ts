/**
 * 平台 admin **介面語言**清單（docs/specs/67 §E.1：介面語言≠內容語言，兩個切換器不連動）。
 *
 * ⚠️ 前端鏡像：正典在 `config/limits.yml` 的 `i18n.admin.ui_locales`／`ui_locale_default`
 * （前端讀不到 YAML，改那兩鍵要同步改這裡；形態同 api/pagination.ts 的鏡像紀律）。
 * endonym＝語言自稱（不用國旗、不用語言碼——`en` 不屬於任何國家；67 §E.2-1 硬規則 2）。
 */
export const UI_LOCALES = [
  { tag: "en", endonym: "English" },
  { tag: "zh-Hant", endonym: "繁體中文" },
  { tag: "zh-Hans", endonym: "简体中文" },
  { tag: "ja", endonym: "日本語" },
  { tag: "fr", endonym: "Français" },
] as const;

export type UiLocale = (typeof UI_LOCALES)[number]["tag"];

export const DEFAULT_UI_LOCALE: UiLocale = "en";

/** 把任意輸入正規化成支援的介面語言；不支援時回預設（不得靜默留空）。 */
export function coerceUiLocale(raw: string | null | undefined): UiLocale {
  const found = UI_LOCALES.find((locale) => locale.tag === raw);
  return found ? found.tag : DEFAULT_UI_LOCALE;
}
