import {
  Bot,
  ChartLine,
  Globe,
  Landmark,
  LayoutGrid,
  House,
  Newspaper,
  Package,
  Percent,
  ShoppingBag,
  Store,
  Tablet,
  TrendingUp,
  Users,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

/**
 * 導航子項：`[路由, 標籤]`。
 *
 * 路由歸屬由**本表**決定，不由 URL 前綴推導——原型 `GROUP_OF` 的語義：
 * `/admin/collections` 屬「產品」群組、`/admin/catalogs` 屬「市場」群組，
 * 兩者的 URL 都看不出歸屬。
 */
export type NavigationKid = readonly [path: string, labelKey: string]; // labelKey＝i18n bundle 的 key（nav.*）

/** 主導覽單元（對齊原型 `NAV` 常數，docs/design/chilllove-admin-v2.html:2225）。 */
export interface NavigationEntry {
  /** i18n key（`nav.*`），渲染時 t(labelKey)；導覽文案不得硬編（ML-1）。 */
  labelKey: string;
  path: string;
  icon: LucideIcon;
  kids: readonly NavigationKid[];
}

/**
 * 主導覽樹。
 *
 * 🔴 正典＝原型 `NAV` 常數（`docs/design/chilllove-admin-v2.html:2225`），
 * 逐項對照、順序一致，不自創（鐵律 12.3）。各項出處：
 *
 * - 訂單子項三項（草稿／運送標籤／未完成結帳）＝原型 orders.kids。
 *   ⚠️ 原型的 `count:5` 徽章**刻意不搬**：那是原型的 demo 數字；實作端的
 *   badge 數字必須來自 rollup 同源查詢（鐵律 7），沒有資料源之前寧可沒有徽章。
 * - 產品子項五項＝71-R8-STRUCT1（採購單／轉移是獨立頁不是庫存 tab）。
 * - 內容根＝元物件（71-R9：本尊根路由 /content/metaobjects）；
 *   網址重新導向在選單頁的頁首鈕，不在本表。
 * - 市場子項＝目錄／推出（71-R10：推出是頂層路徑 /rollouts，沿用同構命名）。
 * - 財務無子項（71-R4-STRUCT1：子項是狀態函數，未啟收款＝無；動態化留待
 *   導航資料驅動時實作，71-R4-V4）。
 */
export const NAVIGATION: readonly NavigationEntry[] = [
  { labelKey: "nav.home", path: "/admin/home", icon: House, kids: [] },
  {
    labelKey: "nav.orders",
    path: "/admin/orders",
    icon: ShoppingBag,
    kids: [
      [ "/admin/orders/drafts", "nav.orders.drafts" ],
      [ "/admin/orders/shipping-labels", "nav.orders.shippingLabels" ],
      [ "/admin/orders/abandoned", "nav.orders.abandoned" ],
    ],
  },
  {
    labelKey: "nav.products",
    path: "/admin/products",
    icon: Package,
    kids: [
      [ "/admin/collections", "nav.products.collections" ],
      [ "/admin/inventory", "nav.products.inventory" ],
      [ "/admin/purchase-orders", "nav.products.purchaseOrders" ],
      [ "/admin/transfers", "nav.products.transfers" ],
      [ "/admin/gift-cards", "nav.products.giftCards" ],
    ],
  },
  {
    labelKey: "nav.customers",
    path: "/admin/customers",
    icon: Users,
    kids: [
      [ "/admin/customers/segments", "nav.customers.segments" ],
      [ "/admin/companies", "nav.customers.companies" ],
    ],
  },
  {
    labelKey: "nav.growth",
    path: "/admin/growth",
    icon: TrendingUp,
    kids: [
      [ "/admin/growth/attribution", "nav.growth.attribution" ],
      [ "/admin/growth/campaigns", "nav.growth.campaigns" ],
    ],
  },
  { labelKey: "nav.discounts", path: "/admin/discounts", icon: Percent, kids: [] },
  {
    labelKey: "nav.content",
    path: "/admin/content/metaobjects",
    icon: Newspaper,
    kids: [
      [ "/admin/content/files", "nav.content.files" ],
      [ "/admin/content/menus", "nav.content.menus" ],
      [ "/admin/content/blog", "nav.content.blog" ],
    ],
  },
  {
    labelKey: "nav.markets",
    path: "/admin/markets",
    icon: Globe,
    kids: [
      [ "/admin/catalogs", "nav.markets.catalogs" ],
      [ "/admin/rollouts", "nav.markets.rollouts" ],
    ],
  },
  { labelKey: "nav.finance", path: "/admin/finance", icon: Landmark, kids: [] },
  {
    labelKey: "nav.analytics",
    path: "/admin/analytics",
    icon: ChartLine,
    kids: [
      [ "/admin/reports", "nav.analytics.reports" ],
      [ "/admin/live", "nav.analytics.live" ],
    ],
  },
];

/**
 * 銷售管道群組（原型 renderSidebar 的固定段，docs/design/chilllove-admin-v2.html:2278）。
 *
 * - 線上商店子項只有頁面／偏好設定兩項（71-R9-STRUCT1）。
 * - 代理式／門市 POS＝71-R0-STUB1 結案：本尊銷售管道全是 app（/apps/{handle}），
 *   只有線上商店是第一方特例；我方以 channels 路由承載，資料模型日後掛在 App 之下。
 */
export const SALES_CHANNELS: readonly NavigationEntry[] = [
  {
    labelKey: "nav.onlineStore",
    path: "/admin/store",
    icon: Store,
    kids: [
      [ "/admin/pages", "nav.onlineStore.pages" ],
      [ "/admin/store/preferences", "nav.onlineStore.preferences" ],
    ],
  },
  { labelKey: "nav.agentic", path: "/admin/channels/agentic", icon: Bot, kids: [] },
  { labelKey: "nav.pos", path: "/admin/channels/pos", icon: Tablet, kids: [] },
];

/** 應用程式群組。 */
export const APPS: readonly NavigationEntry[] = [
  { labelKey: "nav.apps", path: "/admin/apps", icon: LayoutGrid, kids: [] },
];

/**
 * 判斷 pathname 是否屬於某導覽單元（自身或任一子項）。
 *
 * 用前綴比對讓詳情頁（如 `/admin/products/123`）仍點亮所屬單元；
 * 邊界加 `/` 避免 `/admin/orders` 誤點亮 `/admin/orders-x`。
 */
export function entryContains(entry: NavigationEntry, pathname: string): boolean {
  const paths = [ entry.path, ...entry.kids.map(([ path ]) => path) ];
  return paths.some((path) => pathname === path || pathname.startsWith(`${path}/`));
}
