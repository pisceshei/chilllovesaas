import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { AdminRoutes } from "../admin/App";

const rootElement = document.getElementById("admin-root");

if (!(rootElement instanceof HTMLElement)) {
  throw new Error("找不到 Admin SPA 掛載節點。");
}

const brandName = rootElement.dataset.brandName?.trim();

if (!brandName) {
  throw new Error("Admin SPA 缺少品牌設定。");
}

createRoot(rootElement).render(
  <BrowserRouter>
    <AdminRoutes brandName={brandName} />
  </BrowserRouter>,
);
