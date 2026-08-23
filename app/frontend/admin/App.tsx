import type { ReactElement } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { AdminShell } from "./layout/AdminShell";
import { APPS, NAVIGATION, SALES_CHANNELS } from "./layout/navigation";
import { SaveBarProvider } from "./lib/SaveBarContext";
import { ToastProvider } from "./lib/ToastContext";
import { ProductDetailPage } from "./pages/ProductDetailPage";
import { ProductsPage } from "./pages/ProductsPage";
import { Card } from "./components/Card";
import { Page } from "./components/Page";

/** Admin SPA route tree 可用屬性。 */
export interface AdminRoutesProps {
  /** Rails 注入的品牌名稱；route tree 只接受這個來源。 */
  brandName: string;
}

interface PlaceholderPageProps {
  title: string;
}

function PlaceholderPage({ title }: PlaceholderPageProps) {
  return (
    <Page title={title}>
      <Card className="cl-placeholder" padded>
        <h2>功能準備中</h2>
        <p>這個區域會在後續里程碑依規格逐步開放。</p>
      </Card>
    </Page>
  );
}

/**
 * 已有真實頁面的路由；其餘一律由導覽資料表產生 placeholder。
 *
 * 🔴 placeholder 路由**由 navigation.ts 派生**而不是逐條手寫：
 * 導覽樹加一項就自動有頁面，手寫清單則會出現「側欄點得到、路由 404」的縫。
 */
const IMPLEMENTED: ReadonlyMap<string, () => ReactElement> = new Map([
  [ "/admin/products", () => <ProductsPage /> ],
]);

/**
 * 定義 Admin SPA 的 React Router 路由。
 *
 * @param props - 後端注入的單一品牌值。
 * @returns 以 AdminShell 包住所有登入後頁面的 route tree。
 */
export function AdminRoutes({ brandName }: AdminRoutesProps) {
  const navigationPaths = [ ...NAVIGATION, ...SALES_CHANNELS, ...APPS ].flatMap((entry) => [
    { label: entry.label, path: entry.path },
    ...entry.kids.map(([ path, label ]) => ({ label, path })),
  ]);

  return (
    <ToastProvider>
      <SaveBarProvider>
        <Routes>
          <Route element={<AdminShell brandName={brandName} />}>
        <Route element={<Navigate replace to="/admin/products" />} path="/admin" />
        {navigationPaths.map(({ label, path }) => {
          const implemented = IMPLEMENTED.get(path);
          return (
            <Route
              element={implemented ? implemented() : <PlaceholderPage title={label} />}
              key={path}
              path={path}
            />
          );
        })}
        <Route element={<ProductDetailPage isNew />} path="/admin/products/new" />
        <Route element={<ProductDetailPage isNew={false} />} path="/admin/products/:id" />
        <Route element={<PlaceholderPage title="AI 助理" />} path="/admin/assistant" />
        <Route element={<PlaceholderPage title="設定" />} path="/admin/settings" />
        <Route element={<Navigate replace to="/admin/products" />} path="*" />
          </Route>
        </Routes>
      </SaveBarProvider>
    </ToastProvider>
  );
}
