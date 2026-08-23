import { createRoot } from "react-dom/client";
import { RouterProvider, createBrowserRouter } from "react-router-dom";
import { AdminRoutes } from "../admin/App";

const rootElement = document.getElementById("admin-root");

if (!(rootElement instanceof HTMLElement)) {
  throw new Error("找不到 Admin SPA 掛載節點。");
}

const brandName = rootElement.dataset.brandName?.trim();

if (!brandName) {
  throw new Error("Admin SPA 缺少品牌設定。");
}

// 介面語言初值（staff_members.locale，Rails 經 data-ui-locale 注入；67 §E.1）。
const uiLocale = rootElement.dataset.uiLocale?.trim();

// data router（createBrowserRouter）而非 <BrowserRouter>：SaveBar 的離頁攔截
// 用 useBlocker，它只在 data router 下生效——declarative router 會直接拋錯。
// 單一 splat route 包住既有 <Routes> 樹，內層路由行為不變。
const router = createBrowserRouter([
  { path: "*", element: <AdminRoutes brandName={brandName} uiLocale={uiLocale} /> },
]);

createRoot(rootElement).render(<RouterProvider router={router} />);
