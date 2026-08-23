import type { ReactElement } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import { AdminShell } from "./layout/AdminShell";
import { APPS, NAVIGATION, SALES_CHANNELS } from "./layout/navigation";
import { I18nProvider, useT } from "./i18n/I18nContext";
import { SaveBarProvider } from "./lib/SaveBarContext";
import { ToastProvider } from "./lib/ToastContext";
import { ProductDetailPage } from "./pages/ProductDetailPage";
import { ProductsPage } from "./pages/ProductsPage";
import { SettingsLanguagesPage } from "./pages/SettingsLanguagesPage";
import { SettingsPage } from "./pages/SettingsPage";
import { Card } from "./components/Card";
import { Page } from "./components/Page";

/** Admin SPA route tree 可用屬性。 */
export interface AdminRoutesProps {
  /** Rails 注入的品牌名稱；route tree 只接受這個來源。 */
  brandName: string;
  /**
   * 介面語言初值（Rails 從 `staff_members.locale` 注入 `data-ui-locale`）。
   * 67 §E.1：介面語言＝員工屬性，與內容語言不連動。未注入時 Provider 回平台預設。
   */
  uiLocale?: string;
}

interface PlaceholderPageProps {
  titleKey: string;
}

function PlaceholderPage({ titleKey }: PlaceholderPageProps) {
  const t = useT();
  return (
    <Page title={t(titleKey)}>
      <Card className="cl-placeholder" padded>
        <h2>{t("placeholder.title")}</h2>
        <p>{t("placeholder.body")}</p>
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
 * @param props - 後端注入的單一品牌值與介面語言初值。
 * @returns 以 AdminShell 包住所有登入後頁面的 route tree。
 */
export function AdminRoutes({ brandName, uiLocale }: AdminRoutesProps) {
  const navigationPaths = [ ...NAVIGATION, ...SALES_CHANNELS, ...APPS ].flatMap((entry) => [
    { labelKey: entry.labelKey, path: entry.path },
    ...entry.kids.map(([ path, labelKey ]) => ({ labelKey, path })),
  ]);

  return (
    <I18nProvider initialLocale={uiLocale}>
      <ToastProvider>
        <SaveBarProvider>
          <Routes>
            <Route element={<AdminShell brandName={brandName} />}>
              <Route element={<Navigate replace to="/admin/products" />} path="/admin" />
              {navigationPaths.map(({ labelKey, path }) => {
                const implemented = IMPLEMENTED.get(path);
                return (
                  <Route
                    element={implemented ? implemented() : <PlaceholderPage titleKey={labelKey} />}
                    key={path}
                    path={path}
                  />
                );
              })}
              <Route element={<ProductDetailPage isNew />} path="/admin/products/new" />
              <Route element={<ProductDetailPage isNew={false} />} path="/admin/products/:id" />
              <Route element={<PlaceholderPage titleKey="nav.assistant" />} path="/admin/assistant" />
              <Route element={<SettingsPage />} path="/admin/settings" />
              <Route element={<SettingsLanguagesPage />} path="/admin/settings/languages" />
              <Route element={<Navigate replace to="/admin/products" />} path="*" />
            </Route>
          </Routes>
        </SaveBarProvider>
      </ToastProvider>
    </I18nProvider>
  );
}
