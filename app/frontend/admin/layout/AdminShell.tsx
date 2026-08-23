import { Bell, Heart, Menu, Search, Settings, Sparkles, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { useSaveBarState } from "../lib/SaveBarContext";
import { APPS, NAVIGATION, SALES_CHANNELS, entryContains } from "./navigation";
import type { NavigationEntry } from "./navigation";

/**
 * SaveBar（44 §22.5：dirty 時**取代**搜尋列的槽位，不疊加；深色浮層底）。
 *
 * shakeSignal 遞增時重播 cl-shake（原型 47 #88：先移除 class 並強制 reflow）。
 */
function TopbarSaveBar() {
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
    <div aria-label="未儲存的變更" className="cl-savebar" ref={barRef} role="region">
      <span className="cl-savebar__text">未儲存的變更</span>
      <button
        className="cl-savebar__button cl-savebar__button--secondary"
        disabled={state.saving}
        onClick={state.onDiscard}
        type="button"
      >
        捨棄
      </button>
      <button
        className="cl-savebar__button cl-savebar__button--primary"
        disabled={state.saving}
        onClick={state.onSave}
        type="button"
      >
        {state.saving ? "儲存中…" : "儲存"}
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
        <span>{entry.label}</span>
      </NavLink>
      {entry.kids.length > 0 ? (
        <div className={`cl-nav-subs ${active ? "cl-nav-subs--open" : ""}`}>
          {entry.kids.map(([ path, label ]) => (
            <NavLink
              className={({ isActive }) =>
                `cl-nav-sub ${active ? "cl-nav-sub--show" : ""} ${isActive ? "cl-nav-sub--active" : ""}`
              }
              key={path}
              onClick={onNavigate}
              to={path}
            >
              {label}
            </NavLink>
          ))}
        </div>
      ) : null}
    </>
  );
}

/** 搜尋鈕與 SaveBar 共用同一個 topbar 槽位（dirty 時取代，不疊加）。 */
function SearchOrSaveBar() {
  const state = useSaveBarState();
  if (state?.dirty) return <TopbarSaveBar />;
  return (
    <button aria-label="開啟全域搜尋" className="cl-search-trigger" type="button">
      <Search aria-hidden="true" size={14} />
      <span>搜尋</span>
      <kbd>CTRL K</kbd>
    </button>
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
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const avatarText = Array.from(brandName.trim())[0]?.toLocaleUpperCase() ?? "";
  const closeSidebar = () => setSidebarOpen(false);

  return (
    <div className="cl-admin-shell">
      <header className="cl-topbar">
        <button
          aria-expanded={sidebarOpen}
          aria-label={sidebarOpen ? "關閉導覽" : "開啟導覽"}
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
          <span className="cl-brand__version">秋季 ’26</span>
        </div>

        <SearchOrSaveBar />

        <div className="cl-topbar__actions">
          <button aria-label="AI 助理" className="cl-icon-button" type="button">
            <Sparkles aria-hidden="true" size={17} />
          </button>
          <button aria-label="通知" className="cl-icon-button" type="button">
            <Bell aria-hidden="true" size={17} />
          </button>
          <button aria-label={`目前商店：${brandName}`} className="cl-store-chip" type="button">
            <span aria-hidden="true" className="cl-store-chip__avatar">
              {avatarText}
            </span>
            <span>{brandName}</span>
          </button>
        </div>
      </header>

      <div className="cl-app-frame">
        {sidebarOpen ? (
          <button
            aria-label="關閉導覽"
            className="cl-sidebar-backdrop"
            onClick={closeSidebar}
            type="button"
          />
        ) : null}
        <aside className={`cl-sidebar ${sidebarOpen ? "cl-sidebar--open" : ""}`}>
          <nav aria-label="主要導覽" className="cl-sidebar__navigation">
            {NAVIGATION.map((entry) => (
              <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
            ))}
          </nav>

          <p className="cl-nav-group">銷售管道</p>
          {SALES_CHANNELS.map((entry) => (
            <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
          ))}

          <p className="cl-nav-group">應用程式</p>
          {APPS.map((entry) => (
            <SidebarEntry entry={entry} key={entry.path} onNavigate={closeSidebar} />
          ))}

          <div className="cl-sidebar__spacer" />
          <nav aria-label="工具與設定" className="cl-nav-foot">
            <NavLink className="cl-nav-item" onClick={closeSidebar} to="/admin/assistant">
              <Sparkles aria-hidden="true" size={15} />
              <span>AI 助理對話</span>
            </NavLink>
            <NavLink className="cl-nav-item" onClick={closeSidebar} to="/admin/settings">
              <Settings aria-hidden="true" size={15} />
              <span>設定</span>
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
