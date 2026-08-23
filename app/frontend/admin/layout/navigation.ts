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
export type NavigationKid = readonly [path: string, label: string];

/** 主導覽單元（對齊原型 `NAV` 常數，docs/design/chilllove-admin-v2.html:2225）。 */
export interface NavigationEntry {
  label: string;
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
  { label: "首頁", path: "/admin/home", icon: House, kids: [] },
  {
    label: "訂單",
    path: "/admin/orders",
    icon: ShoppingBag,
    kids: [
      [ "/admin/orders/drafts", "草稿" ],
      [ "/admin/orders/shipping-labels", "運送標籤" ],
      [ "/admin/orders/abandoned", "未完成結帳" ],
    ],
  },
  {
    label: "產品",
    path: "/admin/products",
    icon: Package,
    kids: [
      [ "/admin/collections", "商品系列" ],
      [ "/admin/inventory", "庫存" ],
      [ "/admin/purchase-orders", "採購單" ],
      [ "/admin/transfers", "轉移" ],
      [ "/admin/gift-cards", "禮品卡" ],
    ],
  },
  {
    label: "顧客",
    path: "/admin/customers",
    icon: Users,
    kids: [
      [ "/admin/customers/segments", "分群" ],
      [ "/admin/companies", "公司" ],
    ],
  },
  {
    label: "成長",
    path: "/admin/growth",
    icon: TrendingUp,
    kids: [
      [ "/admin/growth/attribution", "歸因" ],
      [ "/admin/growth/campaigns", "行銷活動" ],
    ],
  },
  { label: "折扣", path: "/admin/discounts", icon: Percent, kids: [] },
  {
    label: "內容",
    path: "/admin/content/metaobjects",
    icon: Newspaper,
    kids: [
      [ "/admin/content/files", "檔案" ],
      [ "/admin/content/menus", "選單" ],
      [ "/admin/content/blog", "部落格貼文" ],
    ],
  },
  {
    label: "市場",
    path: "/admin/markets",
    icon: Globe,
    kids: [
      [ "/admin/catalogs", "目錄" ],
      [ "/admin/rollouts", "推出" ],
    ],
  },
  { label: "財務", path: "/admin/finance", icon: Landmark, kids: [] },
  {
    label: "分析",
    path: "/admin/analytics",
    icon: ChartLine,
    kids: [
      [ "/admin/reports", "報告" ],
      [ "/admin/live", "實況瀏覽" ],
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
    label: "線上商店",
    path: "/admin/store",
    icon: Store,
    kids: [
      [ "/admin/pages", "頁面" ],
      [ "/admin/store/preferences", "偏好設定" ],
    ],
  },
  { label: "代理式", path: "/admin/channels/agentic", icon: Bot, kids: [] },
  { label: "門市 POS", path: "/admin/channels/pos", icon: Tablet, kids: [] },
];

/** 應用程式群組。 */
export const APPS: readonly NavigationEntry[] = [
  { label: "應用程式", path: "/admin/apps", icon: LayoutGrid, kids: [] },
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
