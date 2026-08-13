import {
  BarChart3,
  Bell,
  Boxes,
  Heart,
  Home,
  Menu,
  Package,
  Search,
  Settings,
  ShoppingBag,
  Sparkles,
  Store,
  Tag,
  Users,
  X,
} from "lucide-react";
import { useState } from "react";
import type { LucideIcon } from "lucide-react";
import { NavLink, Outlet } from "react-router-dom";

interface NavigationItem {
  label: string;
  path: string;
  icon: LucideIcon;
}

const primaryNavigation: readonly NavigationItem[] = [
  { label: "首頁", path: "/admin/home", icon: Home },
  { label: "訂單", path: "/admin/orders", icon: ShoppingBag },
  { label: "商品", path: "/admin/products", icon: Package },
  { label: "顧客", path: "/admin/customers", icon: Users },
  { label: "折扣", path: "/admin/discounts", icon: Tag },
  { label: "分析", path: "/admin/analytics", icon: BarChart3 },
];

/**
 * AdminShell 可用屬性，佈局對應 `docs/design/23-interaction-css-spec.md` §2 App frame。
 */
export interface AdminShellProps {
  /** Rails 從單一 `#admin-root[data-brand-name]` 注入的平台品牌。 */
  brandName: string;
}

/**
 * 呈現登入後的 52px topbar、220px sidebar 與可捲動內容區。
 *
 * @param props - 後端注入的單一品牌值。
 * @returns 可響應窄螢幕且具 accessible navigation 的 admin shell。
 */
export function AdminShell({ brandName }: AdminShellProps) {
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const avatarText = Array.from(brandName.trim())[0]?.toLocaleUpperCase() ?? "";

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

        <button aria-label="開啟全域搜尋" className="cl-search-trigger" type="button">
          <Search aria-hidden="true" size={14} />
          <span>搜尋</span>
          <kbd>CTRL K</kbd>
        </button>

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
            onClick={() => setSidebarOpen(false)}
            type="button"
          />
        ) : null}
        <aside className={`cl-sidebar ${sidebarOpen ? "cl-sidebar--open" : ""}`}>
          <nav aria-label="主要導覽" className="cl-sidebar__navigation">
            {primaryNavigation.map(({ icon: Icon, label, path }) => (
              <NavLink
                className={({ isActive }) => `cl-nav-item ${isActive ? "cl-nav-item--active" : ""}`}
                key={path}
                onClick={() => setSidebarOpen(false)}
                to={path}
              >
                <Icon aria-hidden="true" size={16} />
                <span>{label}</span>
              </NavLink>
            ))}
          </nav>

          <div className="cl-sidebar__group">
            <p>銷售管道</p>
            <NavLink className="cl-nav-item" onClick={() => setSidebarOpen(false)} to="/admin/store">
              <Store aria-hidden="true" size={16} />
              <span>線上商店</span>
            </NavLink>
          </div>

          <div className="cl-sidebar__group">
            <p>應用程式</p>
            <NavLink className="cl-nav-item" onClick={() => setSidebarOpen(false)} to="/admin/apps">
              <Boxes aria-hidden="true" size={16} />
              <span>新增應用程式</span>
            </NavLink>
          </div>

          <nav aria-label="工具與設定" className="cl-sidebar__footer">
            <NavLink className="cl-nav-item" onClick={() => setSidebarOpen(false)} to="/admin/assistant">
              <Sparkles aria-hidden="true" size={16} />
              <span>AI 助理對話</span>
            </NavLink>
            <NavLink className="cl-nav-item" onClick={() => setSidebarOpen(false)} to="/admin/settings">
              <Settings aria-hidden="true" size={16} />
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
