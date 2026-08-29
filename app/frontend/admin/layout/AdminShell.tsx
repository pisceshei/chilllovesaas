import { Bell, Heart, Languages, Menu, Search, Settings, Sparkles, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { translateWith, useSetUiLocale, useT, useUiLocale } from "../i18n/I18nContext";
import { UI_LOCALES } from "../i18n/locales";
import type { UiLocale } from "../i18n/locales";
import { useSaveBarState } from "../lib/SaveBarContext";
import { useToast } from "../lib/ToastContext";
import { APPS, NAVIGATION, SALES_CHANNELS, entryContains } from "./navigation";
import type { NavigationEntry } from "./navigation";

/**
 * SaveBar（44 §22.5：dirty 時**取代**搜尋列的槽位，不疊加；深色浮層底）。
 *
 * shakeSignal 遞增時重播 cl-shake（原型 47 #88：先移除 class 並強制 reflow）。
 */
function TopbarSaveBar() {
  const t = useT();
  const state = useSaveBarState();
  const barRef = useRef<HTMLDivElement | null>(null);
  const lastShake = useRef(0);

  useEffect(() => {
    if (!state || state.shakeSignal === lastShake.current) return;
    lastShake.current = state.shakeSignal;
    const bar = barRef.current;
    if (!bar) return;
    bar.classList.remove("cl-shake");
    void bar.offsetWidth;
    bar.classList.add("cl-shake");
  }, [state]);

  if (!state?.dirty) return null;

  return (
    <div aria-label={t("shell.savebar.unsaved")} className="cl-savebar" ref={barRef} role="region">
      <span className="cl-savebar__text">{t("shell.savebar.unsaved")}</span>
      <button
        className="cl-savebar__button cl-savebar__button--secondary"
        disabled={state.saving}
        onClick={state.onDiscard}
        type="button"
      >
        {t("shell.savebar.discard")}
      </button>
      <button
        className="cl-savebar__button cl-savebar__button--primary"
        disabled={state.saving}
        onClick={state.onSave}
        type="button"
      >
        {state.saving ? t("shell.savebar.saving") : t("shell.savebar.save")}
      </button>
    </div>
  );
}

/**
 * AdminShell 可用屬性，佈局對應原型 topbar／sidebar（值一律走 tokens，鐵律 8）。
 */
export interface AdminShellProps {
  /** Rails 從單一 `#admin-root[data-brand-name]` 注入的平台品牌。 */
  brandName: string;
}

interface SidebarEntryProps {
  entry: NavigationEntry;
  onNavigate: () => void;
}

/**
 * 呈現一個導覽單元＋其子項手風琴。
 *
 * 展開語義照原型 `renderSidebar`：**目前頁面屬於這個群組**時展開
 * （`nav-subs.open`＋子項 `show`），不是點擊切換——切到別的群組會自動收合。
 * 群組歸屬由 navigation.ts 的資料表決定，不由 URL 前綴推導。
 */
function SidebarEntry({ entry, onNavigate }: SidebarEntryProps) {
  const t = useT();
  const location = useLocation();
  const active = entryContains(entry, location.pathname);
  const Icon = entry.icon;

  return (
    <>
      <NavLink
        className={`cl-nav-item ${active && location.pathname === entry.path ? "cl-nav-item--active" : ""}`}
        onClick={onNavigate}
        to={entry.path}
      >
        <Icon aria-hidden="true" size={15} />
        <span>{t(entry.labelKey)}</span>
      </NavLink>
      {entry.kids.length > 0 ? (
        <div className={`cl-nav-subs ${active ? "cl-nav-subs--open" : ""}`}>
          {entry.kids.map(([ path, labelKey ]) => (
            <NavLink
              className={({ isActive }) =>
                `cl-nav-sub ${active ? "cl-nav-sub--show" : ""} ${isActive ? "cl-nav-sub--active" : ""}`
              }
              key={path}
              onClick={onNavigate}
              to={path}
            >
              {t(labelKey)}
            </NavLink>
          ))}
        </div>
      ) : null}
    </>
  );
}

/** 搜尋鈕與 SaveBar 共用同一個 topbar 槽位（dirty 時取代，不疊加）。 */
function SearchOrSaveBar() {
  const t = useT();
  const state = useSaveBarState();
  if (state?.dirty) return <TopbarSaveBar />;
  return (
    <button aria-label={t("shell.search.open")} className="cl-search-trigger" type="button">
      <Search aria-hidden="true" size={14} />
      <span>{t("shell.search.label")}</span>
      <kbd>CTRL K</kbd>
    </button>
  );
}

const STAFF_LOCALE_MUTATION = `
  mutation staffLocaleUpdate($locale: String!) {
    staffLocaleUpdate(locale: $locale) {
      locale
      userErrors { field message code }
    }
  }
`;

interface StaffLocaleData {
  staffLocaleUpdate: { locale: string | null; userErrors: { message: string }[] };
}

/**
 * 介面語言切換器（67 §E.1：員工屬性，與內容語言**不連動**）。
 * 先持久化（staffLocaleUpdate）再切前端狀態；失敗時不切，避免「畫面換了、重整又跳回」。
 */
function UiLocaleSwitcher() {
  const t = useT();
  const locale = useUiLocale();
  const setLocale = useSetUiLocale();
  const { showToast } = useToast();
  const [busy, setBusy] = useState(false);

  const change = async (next: UiLocale) => {
    if (next === locale || busy) return;
    setBusy(true);
    try {
      const data = await requestAdminGraphQL<StaffLocaleData, { locale: string }>(STAFF_LOCALE_MUTATION, { locale: next });
      if (data.staffLocaleUpdate.userErrors.length > 0) {
        showToast(data.staffLocaleUpdate.userErrors[0].message);
        return;
      }
      setLocale(next);
      // 成功訊息用**新**語言：閉包裡的 t 仍是切換前的語言。
      showToast(translateWith(next)("shell.uiLocale.updated"));
    } catch {
      showToast(t("shell.uiLocale.failed"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <label className="cl-locale-switch" title={t("shell.uiLocale")}>
      <Languages aria-hidden="true" size={16} />
      <span className="cl-sr-only">{t("shell.uiLocale")}</span>
      <select
        className="cl-locale-switch__select"
        disabled={busy}
        onChange={(event) => void change(event.target.value as UiLocale)}
        value={locale}
      >
        {UI_LOCALES.map((option) => (
          <option key={option.tag} lang={option.tag} value={option.tag}>
            {option.endonym}
          </option>
        ))}
      </select>
    </label>
  );
}

/**
 * 呈現登入後的 topbar、sidebar 與可捲動內容區。
 *
 * 導覽樹＝原型 `NAV`＋銷售管道＋應用程式＋工具（navigation.ts 逐項對照）。
 *
 * @param props - 後端注入的單一品牌值。
 * @returns 可響應窄螢幕且具 accessible navigation 的 admin shell。
 */
export function AdminShell({ brandName }: AdminShellProps) {
  const t = useT();
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const avatarText = Array.from(brandName.trim())[0]?.toLocaleUpperCase() ?? "";
  const closeSidebar = () => setSidebarOpen(false);

  return (
    <div className="cl-admin-shell">
      {/* cl-scope-dark：本尊把頂欄包在一個主題容器裡，容器改 token、頂欄只寫 var(--bg)。
          見 admin.css 的 .cl-scope-dark 與原型 :root 的暗色域區塊。 */}
      <header className="cl-topbar cl-scope-dark">
        {/* 三欄 grid 的三個槽（D67）。中槽同時是搜尋列與存檔列的槽位——
            dirty 時 SaveBar 取代搜尋列而不是疊加，兩者共用同一個槽 ⇒ 換手時中線不動。
            本尊對應物是 `_LeftContent_` / `_SlotsContainer_` / `_RightContent_`。 */}
        <div className="cl-topbar__zone">
        <button
          aria-expanded={sidebarOpen}
          aria-label={sidebarOpen ? t("shell.nav.close") : t("shell.nav.open")}
          className="cl-icon-button cl-topbar__menu"
          onClick={() => setSidebarOpen((open) => !open)}
          type="button"
        >
          {sidebarOpen ? <X aria-hidden="true" size={18} /> : <Menu aria-hidden="true" size={18} />}
        </button>

        <div className="cl-brand" title={brandName}>
          <span aria-hidden="true" className="cl-brand__mark">
            <Heart fill="currentColor" size={13} />
          </span>
          <span className="cl-brand__name">{brandName}</span>
          <span className="cl-brand__version">{t("shell.version")}</span>
        </div>

        </div>

        <div className="cl-topbar__zone">
          <SearchOrSaveBar />
        </div>

        <div className="cl-topbar__zone cl-topbar__zone--right">
        <div className="cl-topbar__actions">
          <UiLocaleSwitcher />
          <button aria-label={t("shell.assistant")} className="cl-icon-button" type="button">
            <Sparkles aria-hidden="true" size={17} />
          </button>
          <button aria-label={t("shell.notifications")} className="cl-icon-button" type="button">
            <Bell aria-hidden="true" size={17} />
          </button>
          <button aria-label={t("shell.currentStore", { name: brandName })} className="cl-store-chip" type="button">
            <span aria-hidden="true" className="cl-store-chip__avatar">
              {avatarText}
            </span>
            <span>{brandName}</span>
          </button>
        </div>
        </div>
      </header>

      <div className="cl-app-frame">
        {sidebarOpen ? (
          <button
            aria-label={t("shell.nav.close")}
            className="cl-sidebar-backdrop"
            onClick={closeSidebar}
            type="button"
          />
        ) : null}
        <aside className={`cl-sidebar ${sidebarOpen ? "cl-sidebar--open" : ""}`}>
          <nav aria-label={t("shell.nav.main")} className="cl-sidebar__navigation">
            {NAVIGATION.map((entry) => (
              <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
            ))}
          </nav>

          <p className="cl-nav-group">{t("nav.group.salesChannels")}</p>
          {SALES_CHANNELS.map((entry) => (
            <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
          ))}

          <p className="cl-nav-group">{t("nav.group.apps")}</p>
          {APPS.map((entry) => (
            <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
          ))}

          <div className="cl-sidebar__spacer" />
          <nav aria-label={t("shell.nav.tools")} className="cl-nav-foot">
            <NavLink className="cl-nav-item" onClick={closeSidebar} to="/admin/assistant">
              <Sparkles aria-hidden="true" size={15} />
              <span>{t("nav.assistantChat")}</span>
            </NavLink>
            <NavLink className="cl-nav-item" onClick={closeSidebar} to="/admin/settings">
              <Settings aria-hidden="true" size={15} />
              <span>{t("nav.settings")}</span>
            </NavLink>
          </nav>
        </aside>

        <main className="cl-main" id="main-content">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
