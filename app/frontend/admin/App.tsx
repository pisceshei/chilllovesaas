import { Navigate, Route, Routes } from "react-router-dom";
import { AdminShell } from "./layout/AdminShell";
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
 * 定義 Admin SPA 的 React Router 路由。
 *
 * @param props - 後端注入的單一品牌值。
 * @returns 以 AdminShell 包住所有登入後頁面的 route tree。
 */
export function AdminRoutes({ brandName }: AdminRoutesProps) {
  return (
    <Routes>
      <Route element={<AdminShell brandName={brandName} />}>
        <Route element={<Navigate replace to="/admin/products" />} path="/admin" />
        <Route element={<PlaceholderPage title="首頁" />} path="/admin/home" />
        <Route element={<PlaceholderPage title="訂單" />} path="/admin/orders" />
        <Route element={<ProductsPage />} path="/admin/products" />
        <Route element={<PlaceholderPage title="新增商品" />} path="/admin/products/new" />
        <Route element={<PlaceholderPage title="商品詳情" />} path="/admin/products/:id" />
        <Route element={<PlaceholderPage title="顧客" />} path="/admin/customers" />
        <Route element={<PlaceholderPage title="折扣" />} path="/admin/discounts" />
        <Route element={<PlaceholderPage title="分析" />} path="/admin/analytics" />
        <Route element={<PlaceholderPage title="線上商店" />} path="/admin/store" />
        <Route element={<PlaceholderPage title="應用程式" />} path="/admin/apps" />
        <Route element={<PlaceholderPage title="AI 助理" />} path="/admin/assistant" />
        <Route element={<PlaceholderPage title="設定" />} path="/admin/settings" />
        <Route element={<Navigate replace to="/admin/products" />} path="*" />
      </Route>
    </Routes>
  );
}
