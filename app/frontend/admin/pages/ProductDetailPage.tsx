import { ArrowLeft, CalendarClock, Check, ChevronDown, ImagePlus, MoreHorizontal, Pencil, Settings, Sparkles, X } from "lucide-react";
import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import type { RefObject } from "react";
import { Link, useBlocker, useNavigate, useParams } from "react-router-dom";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import type { BadgeProgress, BadgeTone } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { InventoryCard } from "../components/InventoryCard";
import { MediaCard } from "../components/MediaCard";
import { Modal } from "../components/Modal";
import { SchedulePopover } from "../components/SchedulePopover";
import type { MediaCardItem } from "../components/MediaCard";
import { LocalizedField } from "../components/LocalizedField";
import type { LocaleOption } from "../components/LocalizedField";
import { TextField } from "../components/TextField";
import { useSaveBarRegister } from "../lib/SaveBarContext";
import { useToast } from "../lib/ToastContext";
import { uuidV4 } from "../lib/uuid";
import { centsToApiString, isValidMoneyInput, parseMoneyToCents, profitState } from "../lib/money";
import { useT } from "../i18n/I18nContext";
import { graveKey, MAX_PRODUCT_OPTIONS, rebuildRows, buildVariantsPayload } from "../lib/variantMatrix";
import type { OptionDraft, RowSeed, VariantRowData } from "../lib/variantMatrix";

/**
 * 商品建立／詳情頁（59 §7：**同一個元件的兩種狀態，不是兩個頁面**——
 * 分家後同名函式靜默覆蓋整頁是本專案頭號事故 53 號 N-01）。
 *
 * isNew＝建立態（固定草稿、右欄只有發布卡）；否則編輯態（載入既有商品、
 * 右欄多狀態卡、儲存帶 id＋lockVersion 走 productSet 更新分支）。
 * 版面、卡片順序、pill 分組鍵對照原型 productPage()（chilllove-admin-v2.html）。
 *
 * 未接線欄位（disabled）＝後續里程碑的通道還沒到（庫存／運送／發布／SEO 文案），
 * **刻意 disabled 而不是收集後丟棄**——收了不送等於騙商家已儲存。
 * 清單與依賴見 docs/dev/m1-product-set-foundation.md §4／§6。
 */
export interface ProductDetailPageProps {
  /** 建立態；false＝編輯態（路由 /admin/products/:id）。 */
  isNew: boolean;
}

const PRODUCT_SET_MUTATION = `
  mutation productSet($input: ProductSetInput!, $idempotencyKey: String) {
    productSet(input: $input, idempotencyKey: $idempotencyKey) {
      product {
        id handle status title lockVersion
        variants(first: 250) { nodes { id selectedOptions { name value } } }
      }
      userErrors { field message code }
    }
  }
`;

const PRODUCT_QUERY = `
  query productForEdit($id: ID!) {
    product(id: $id) {
      id title descriptionHtml status handle lockVersion
      vendor productType tags
      seo { title description }
      translations { locale field value outdated }
      # 🔴 **必須 onlyPublished: false**：預設 true 只回「已到點」的，
      #   已排程未到點的管道會整列消失 ⇒ 發布卡少顯示一個管道，而這在
      #   「沒有任何排程」的環境下 100% 測綠（S6 盤點的風險 #7）。
      # S6a-2：可見性兩維的**伺服器唯一答案**（三層 AND 的前兩層）。
      #   省略 publicationId＝線上商店（v1 唯一前台管道）。
      purchasable
      discoverable
      resourcePublicationsV2(onlyPublished: false) {
        isPublished
        publishDate
        publication { id title supportsFuturePublishing }
      }
      media { id position alt status image { thumbUrl url }
              externalVideo { host externalId embedUrl originUrl } }
      options { name position values { value position } }
      variants(first: 250) {
        nodes {
          id title position price compareAtPrice cost sku barcode taxable
          weightGrams requiresShipping
          selectedOptions { name value }
        }
        pageInfo { hasNextPage }
      }
    }
    # 🔴 **本店全部管道**（modal 要顯示「未發布」的管道，而 resourcePublicationsV2
    #   只回已發布／已排程的列 ⇒ 未發布的管道在那裡**根本沒有列**）。
    #   兩者做差集才是完整清單。本尊同樣在商品詳情查詢裡一起拿
    #   （AdminProductDetails 帶 supportedChannelsFirst: 50，82 號 §13.3）。
    #   🔴 **handle 是用來濾掉 catalog publication 的**——這個 query 回的是本店**全部**
    #     publication（欄位描述逐字「管道與 catalog 的發布容器」），而本尊把
    #     Sales Channels 與 Catalogs 分成兩節（82 號 §12.1）。handle 來自
    #     publication.channel&.handle，API 建的 catalog publication 沒有 channel ⇒ null。
    #   ⚠️ 本區塊在 template literal 內，**不得用反引號**（會提前結束字串）。
    publications { id title handle supportsFuturePublishing }
    # 🔴 排程的時區來源＝**店鋪設定**（help 明文 Store defaults），不是瀏覽器。
    #   與商品同一次往返拿，避免開彈層時才查。
    shop { ianaTimezone }
  }
`;

/**
 * 一列發布狀態（`resourcePublicationsV2` 的元素）。
 *
 * 🔴 **`isPublished` 不是「有沒有發布到這個管道」**——V2 的語義是
 * `true`＝已到點、`false`＝**已排程未到點（staged）**；「既未發布也未排程」
 * 的管道**該列根本不存在**（見 `app/graphql/types/resource_publication_v2_type.rb`
 * 的真值表）。⇒ 「這個管道開著嗎」的正確判準是**列是否存在**，不是 `isPublished`。
 * 把 toggle 綁 `isPublished` 會讓已排程的管道顯示成關閉，而該 bug 在沒有任何
 * 排程的環境下 100% 測綠。
 */
type PublicationRow = {
  isPublished: boolean;
  publishDate: string | null;
  publication: { id: string; title: string; supportsFuturePublishing: boolean };
};

/**
 * 本店的一個管道（`publications` query 的元素）。
 *
 * 🔴 **與 `PublicationRow.publication` 是同一個東西的兩個來源**，但集合不同：
 * 這裡是**全部管道**，`PublicationRow` 只有**該商品已發布或已排程**的那些。
 * modal 要列出全部（含未發布的），⇒ 以本清單為骨架、用 `PublicationRow` 標狀態。
 */
type PublicationOption = {
  id: string;
  title: string;
  /** `null`＝沒有綁 channel＝catalog publication，不是銷售管道（見 `salesChannelsOf`）。 */
  handle: string | null;
  supportsFuturePublishing: boolean;
};

/**
 * 從本店全部 publication 中取出**真正的銷售管道**。
 *
 * 🔴 `Query.publications` 回的是全部 publication——它的欄位描述逐字是
 * 「本店的 publication（**管道與 catalog** 的發布容器）」。不過濾的話，店家用已上線的
 * `publicationCreate`（S1）建出一個 catalog（例如市場目錄）之後，那個 catalog 會出現在
 * 本 modal 標題為「銷售管道」的群組列底下、與線上商店並列；群組總開關的「發布到全部管道」
 * 會把商品一併寫進該 catalog，而商家以為自己只是發布到全部**銷售管道**。
 *
 * 判準＝`handle` 是否為 null：它來自 `publication.channel&.handle`，而 channel 是
 * app 安裝流程的產物；`Publications::Write.create` 建的 catalog publication **沒有 channel**
 * （該處只寫一個 `catalog-{id}` 佔位值進 legacy 的 `channel_handle` 欄，不建 channel 列）。
 * 實證（開發庫）：`Publication.includes(:channel)` 逐列印出 channel="online_store"。
 *
 * ⚠️ 本尊在 modal 內是**分節**顯示（Sales Channels 一節、Catalogs › Regions 另一節，
 * 82 §12.1）。我方目前只做前者 ⇒ 濾掉後者而不是另起一節，屬已登記的射程邊界（S10 補）。
 */
function salesChannelsOf(publications: PublicationOption[]): PublicationOption[] {
  // 🔴 `!= null`（寬鬆）不是 `!== null`：前者連 `undefined` 一起擋掉。差別在於「查詢忘了取
  //   handle」這個情境——嚴格比較會讓每一列都通過（`undefined !== null` 為真）⇒ catalog
  //   靜默混進銷售管道，正是本判準要防的事；寬鬆比較則讓 modal 直接變空，是**看得見**的失敗。
  return publications.filter((pub) => pub.handle != null);
}

/**
 * 管道開關的 DOM id（群組總開關的 `aria-controls` 要指得到）。
 *
 * 🔴 GID 含 `/` 與 `:`，直接當 id 會讓 `aria-controls` 的**空白分隔清單**解析錯誤，
 * 而且 `document.getElementById` 以外的選擇器也會炸 ⇒ 一律先轉成安全字元。
 */
function channelSwitchId(scope: string, publicationId: string): string {
  return `${scope}-ch-${publicationId.replace(/[^a-zA-Z0-9]/g, "-")}`;
}
// ⚠️ **誠實登記：轉義目前是防禦性的，現有測試證明不了它必要**。GID 不含空白，
//   所以 `aria-controls` 的空白分隔解析在不轉義時也不會壞（M12 突變確實沒轉紅）。
//   它防的是「日後有人拿這個 id 去餵 `querySelector('#…')`」——`/` 與 `:` 在 CSS
//   選擇器裡要跳脫。本尊在這裡是**直接用裸 GID 當 host id**（82 §14 實測），
//   我方多一層 scope 前綴是因為 `useId()` 才保證得了同頁多實例的唯一性。

/**
 * 管道搜尋的比對法（本尊實測，取證 2026-08-27）。
 *
 * 🔴 **詞首前綴，不是子字串、也不是整串前綴**。實測四格：
 *   `store` → 命中 `Online Store`（⇒ 不是整串前綴）；
 *   `tore`  → 無結果（⇒ 不是子字串）；
 *   `line`  → 無結果（`Online` 的子字串但非詞首 ⇒ 再次排除子字串）；
 *   `of`    → 命中 `Point of Sale`（⇒ 中間的虛詞也算一個詞）。
 * 另實測：大小寫不敏感、前後空白會 trim。
 *
 * ⚠️ 用 `includes()` 實作的話上面第 2、3 格會**多命中**，而那個差異在只有
 * 「線上商店／門市 POS／Shop」這種短名清單上幾乎看不出來——`Shop` 這種
 * 單詞管道兩種實作都會命中。
 */
function matchChannels(publications: PublicationOption[], query: string): PublicationOption[] {
  const needle = query.trim().toLowerCase();
  if (!needle) return publications;
  return publications.filter((pub) =>
    pub.title.toLowerCase().split(/\s+/).some((word) => word.startsWith(needle)));
}

/**
 * 一筆待送出的發布。
 *
 * 🔴 **排程不另存一份狀態，它就是 `publish` 的一種**——本尊沒有獨立的 schedule mutation，
 * 「排程」＝帶未來 `publishDate` 的 `publishablePublish`（`docs/research/82` §15.8 抓包）。
 * 另開一份 `schedule` map 的話，兩份狀態會出現「schedule 有 id 但 publish 沒有」的
 * 不可能組合，而那種組合送出去就是一筆沒有目標的排程。
 *
 * `at`＝`null` 表示立即發布（送出時**不帶** `publishDate` 欄位——後端 R10 對明確傳 null
 * 一律 reject，省略才是「立即」）。
 */
type PublishEntry = { publicationId: string; at: number | null };

/** 待送出的發布變更（`FormValues.publicationDelta` 的型別別名，供純函式簽名使用）。 */
type PublicationDelta = { publish: PublishEntry[]; unpublish: string[] };

const EMPTY_DELTA: PublicationDelta = { publish: [], unpublish: [] };

/** delta 的 publish 側是否含某管道。 */
function publishEntry(delta: PublicationDelta, publicationId: string): PublishEntry | undefined {
  return delta.publish.find((entry) => entry.publicationId === publicationId);
}

/**
 * 某管道在**伺服器上**是否開著。
 *
 * 🔴 **判準是「該列是否存在」，不是 `isPublished`**（S6a 已釘死的判準，S6b 沿用）：
 * V2 的 `isPublished=false` 語義是「已排程未到點（staged）」而不是「未發布」；
 * 既未發布也未排程的管道**該列根本不存在**。綁 `isPublished` 會讓已排程的管道
 * 顯示成關閉，而該 bug 在沒有任何排程的環境下 **100% 測綠**。
 */
function isPublishedOnServer(rows: PublicationRow[], publicationId: string): boolean {
  return rows.some((row) => row.publication.id === publicationId);
}

/** 某管道**畫面上**該顯示的開關狀態＝伺服器現況套上待送 delta。 */
function channelIsOn(rows: PublicationRow[], delta: PublicationDelta, publicationId: string): boolean {
  if (publishEntry(delta, publicationId)) return true;
  if (delta.unpublish.includes(publicationId)) return false;
  return isPublishedOnServer(rows, publicationId);
}

/**
 * 兩份 delta 是否等價（集合相等，順序無關）。
 *
 * 🔴 **這是 `Done` 是否可按的判準來源**，而判準必須是「與**開啟本次 modal 時**的暫存值
 * 不同」，**不是**「draft 兩邊皆空」。差別只在「開場就已有暫存」的 session 顯現，
 * 而那正是 82 §14.4d 實測到的真實情境（暫存值跨 session 存活）：
 *
 * 商品已發布到線上商店 → 撥關 → `Done`（暫存 unpublish）→ 重開 modal → 撥回開。
 * `toggleChannel` 會把該 id 從 delta 兩邊移除 ⇒ draft 變空。若判準是「兩邊皆空」，
 * 此刻 `Done` **變回 disabled**，使用者按不下去；而 `Cancel` 依 §14.4d 只丟本次 session、
 * 先前的 unpublish 仍在 ⇒ **modal 內不存在任何路徑能撤銷它**，唯一出口是頁面層的「捨棄」，
 * 而那會連標題／價格／SEO／變體矩陣等全部未儲存編輯一起丟掉。使用者若沒察覺就儲存，
 * 商品會真的被取消發布，**而畫面上那個開關當時顯示為「開」**。
 *
 * ⚠️ 程式碼原本引 82 §12「全程在 modal 內還原後 Done 全程 disabled」當依據——
 * 那次量測的 session **開場 delta 為空**，兩種判準在該情境下重合、分不出來，
 * 射程不涵蓋本情境（本尊在「已有暫存」時 Done 的狀態＝§14.10 未取得）。
 */
function sameDelta(a: PublicationDelta, b: PublicationDelta): boolean {
  const sameIds = (x: string[], y: string[]) =>
    x.length === y.length && [ ...x ].sort().every((id, i) => id === [ ...y ].sort()[i]);
  // 🔴 publish 側要比 **(id, at) 兩個欄位**——只比 id 的話「同一個管道改了排程時間」
  //   會被判成沒變，`Done` 停在 disabled，商家改不了已暫存的排程。
  const key = (entry: PublishEntry) => `${entry.publicationId}@${entry.at ?? "now"}`;
  const samePublish = a.publish.length === b.publish.length
    && a.publish.map(key).sort().every((k, i) => k === b.publish.map(key).sort()[i]);
  return samePublish && sameIds(a.unpublish, b.unpublish);
}

/**
 * 撥動一個管道，算出新的 delta。
 *
 * 🔴 **撥回伺服器現況時必須把該 id 從 delta 兩邊都移除，而不是記到另一邊**。
 * 兩個後果，缺這條就都會發生：
 * ①送出時會多送一支沒必要的 mutation（unpublish 一個伺服器上根本不存在的列）；
 * ②`dirty` 會停在 true ⇒ SaveBar 不消失、離頁被攔，而使用者明明把它撥回原狀了。
 *
 * 本尊實測正面支持這條（82 §12：所有 toggle 動作在同一個 modal 內還原後，
 * 頁尾 `Done` **全程 disabled**＝沒有待儲存的變更）⇒ 本尊也是**與現況比對**，
 * 不是記錄操作序列。
 */
function toggleChannel(
  rows: PublicationRow[],
  delta: PublicationDelta,
  publicationId: string,
  next: boolean,
): PublicationDelta {
  const withoutId = {
    publish: delta.publish.filter((entry) => entry.publicationId !== publicationId),
    unpublish: delta.unpublish.filter((id) => id !== publicationId),
  };
  // 🔴 **撥回伺服器現況只在「該管道沒有待送的排程」時才算歸零**：已排程未到點的管道
  //   在伺服器上**有列**（V2 的 staged），把它撥開會被判成「回到現況」而清掉 delta
  //   ——連同使用者剛設的排程一起。所以帶排程的情形一律重新記進 publish。
  if (next === isPublishedOnServer(rows, publicationId)) return withoutId;
  return next
    ? { ...withoutId, publish: [ ...withoutId.publish, { publicationId, at: null } ] }
    : { ...withoutId, unpublish: [ ...withoutId.unpublish, publicationId ] };
}

/**
 * 某管道在**伺服器上**的排程時刻；未排程（或已到點）回 `null`。
 *
 * 🔴 判準是 **`isPublished === false`**——V2 的 `false` 就是「已排程未到點（staged）」。
 * ⚠️ **不能只看 `publishDate` 非空**：每一列都有 `publishDate`（已發布的列存的是
 * 「當初發布的時刻」，是過去值），只看非空會把所有已發布管道都當成排程中
 * （本尊回應的實測形態，`82` §15.8 結論 3）。
 */
function serverScheduleOf(rows: PublicationRow[], publicationId: string): number | null {
  const row = rows.find((candidate) => candidate.publication.id === publicationId);
  if (!row || row.isPublished || !row.publishDate) return null;
  const at = Date.parse(row.publishDate);
  return Number.isNaN(at) ? null : at;
}

/**
 * 設定（或更新）某管道的排程時刻。
 *
 * 🔴 **一律進 `publish` 側**，即使該管道在伺服器上已經開著——排程是一次 publish 寫入
 * （§15.8：本尊送的就是 `publishablePublish` 帶 `publishDate`），不是「開關的附屬屬性」。
 * 同理 `Remove schedule` 送的是 `at = <now>`（§15.7 抓包終態＝立即發布），不是清空。
 */
function scheduleChannel(delta: PublicationDelta, publicationId: string, at: number): PublicationDelta {
  return {
    publish: [
      ...delta.publish.filter((entry) => entry.publicationId !== publicationId),
      { publicationId, at },
    ],
    unpublish: delta.unpublish.filter((id) => id !== publicationId),
  };
}

/**
 * 發布卡的內容（S6a；`docs/research/82` §9.3 的第一種 affordance 的唯讀部分）。
 *
 * ①這是什麼：商品目前發布到哪些管道，資料來自 `resourcePublicationsV2(onlyPublished: false)`。
 * ②為什麼這樣判：🔴 **「這個管道開著嗎」＝該列是否存在**，不是 `isPublished`。
 *   V2 的 `isPublished=false` 語義是「已排程未到點（staged）」而不是「未發布」；
 *   既未發布也未排程的管道**該列根本不存在**。把開關綁 `isPublished` 會讓已排程的
 *   管道顯示成關閉，而該 bug 在沒有任何排程的環境下 **100% 測綠**。
 * ③排程列另標時間（本尊實測：Publishing 卡顯示日曆 badge ＋ tooltip 帶日期）。
 * ④跨功能影響：S6b 會在同一張卡加齒輪開 modal 做**編輯**；本切片刻意**唯讀**，
 *   因為編輯要走 `publishablePublish`／`publishableUnpublish` 且有 checkbox/toggle
 *   兩種語義不得混用的陷阱（82 §9.4）。
 */
function PublishingCard({
  publications,
  rows,
  delta,
  stale,
  t,
}: {
  publications: PublicationOption[];
  rows: PublicationRow[];
  delta: PublicationDelta;
  /** 重讀失敗 ⇒ 手上這份不再是伺服器現值，不得冒充（見 `publicationsStale`）。 */
  stale: boolean;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  if (stale) {
    return <p className="cl-pubcard__empty">{t("product.publishing.stale")}</p>;
  }
  // 🔴 **以 `rows`（伺服器現況）為骨架，`publications` 只用來查待發布管道的標題**。
  //   反過來以 `publications` 為骨架會讓卡片在該查詢缺席時整個空掉——那是 S6a 的回歸
  //   （S6a 的卡片只靠 `rows` 就能顯示）。查不到標題時退回 id，不讓該列消失。
  const shown = [
    ...rows
      .filter((row) => !delta.unpublish.includes(row.publication.id))
      .map((row) => ({
        id: row.publication.id,
        title: row.publication.title,
        row,
        // 待送的排程覆蓋伺服器現值（本尊按 Done 後卡片樂觀更新，§13.1）
        pendingAt: publishEntry(delta, row.publication.id)?.at ?? null,
      })),
    ...delta.publish
      .filter((entry) => !isPublishedOnServer(rows, entry.publicationId))
      .map((entry) => ({
        id: entry.publicationId,
        title: publications.find((pub) => pub.id === entry.publicationId)?.title ?? entry.publicationId,
        row: undefined as PublicationRow | undefined,
        pendingAt: entry.at,
      })),
  ];

  if (shown.length === 0) {
    return <p className="cl-pubcard__empty">{t("product.publishing.none")}</p>;
  }
  return (
    <ul className="cl-pubcard">
      {shown.map((entry) => (
        <li className="cl-pubcard__row" key={entry.id}>
          <span className="cl-pubcard__name">{entry.title}</span>
          {/* 🔴 三態，不是兩態。`row` 缺席＝本次 modal 剛開啟、尚未儲存的待發布管道
              （本尊實測 82 §13.1：按 Done 後卡片**樂觀更新**，SaveBar 才出現）。 */}
          {/* 🔴 待送的排程優先於伺服器現值——商家剛在彈層設好時間按了 Done，
              卡片必須立刻反映它，否則看起來像沒生效（§13.1 的樂觀更新）。 */}
          {entry.pendingAt !== null ? (
            <Badge tone="attention">
              {t("product.publishing.state.pendingAt", { at: formatPublishDate(new Date(entry.pendingAt).toISOString()) })}
            </Badge>
          ) : entry.row === undefined ? (
            <Badge tone="attention">{t("product.publishing.state.pending")}</Badge>
          ) : entry.row.isPublished ? (
            <Badge tone="success">{t("product.publishing.state.published")}</Badge>
          ) : (
            <Badge tone="info">
              {entry.row.publishDate
                ? t("product.publishing.state.scheduledAt", { at: formatPublishDate(entry.row.publishDate) })
                : t("product.publishing.state.scheduled")}
            </Badge>
          )}
        </li>
      ))}
    </ul>
  );
}

/**
 * 群組總開關（modal 內「全部管道」那一列）。
 *
 * ①這是什麼：一顆控制整組管道的三態控制項——全開／全關／**半選**（各列不一致）。
 * ②🔴 **它不是 `role="switch"`，這是刻意的**：`switch` 規範上**不支援**
 *   `aria-checked="mixed"`，指定 mixed 會被 UA 降級成 `false`
 *   （MDN《ARIA: switch role》逐字 "assigning a value of `mixed` to a `switch`
 *   instead sets the value to `false`"，取證 2026-08-27
 *   <https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Roles/switch_role>）。
 *   ⇒ 若照各列的樣子也寫成 switch，**半選態會被螢幕閱讀器讀成「關」**，
 *   視障使用者無從察覺子項不一致——而畫面上看起來完全正常，任何視覺測試都不會紅。
 *   支援 mixed 的是 `checkbox`（MDN《ARIA: checkbox role》逐字
 *   "The checkbox is partially checked, or indeterminate."）⇒ 本元件用 `role="checkbox"`。
 * ③🔴 **本尊用的是另一條路，但兩者在 AX tree 上等價**——2026-08-27 實測
 *   （`82` §14）：本尊的 toggle 是 Web Component `<s-internal-switch>`，狀態藏在
 *   shadow root 裡的原生 `<input type="checkbox">`，半選**完全靠 DOM property
 *   `input.indeterminate = true`** 承載，`aria-checked`／`role` 一個都沒有。
 *   而 W3C html-aam 逐字 "aria-checked state set to 'mixed' if the element's
 *   indeterminate IDL attribute is true"（<https://www.w3.org/TR/html-aam-1.0/>，
 *   取證 2026-08-27）⇒ 原生 `indeterminate` 會被映射成 `mixed`，**AX 結果與本行相同**。
 *   我方走顯式 `aria-checked="mixed"` 的兩個理由：①該 IDL 屬性只能經 DOM node 設定
 *   （MDN 逐字 "it cannot be set using an HTML attribute"），而 React 官方文檔
 *   **完全沒有記載** `indeterminate`（react.dev 與 legacy 兩頁皆無此字串，取證 2026-08-27）
 *   ⇒ 那條路在 React 上沒有官方依據；②顯式屬性在 DOM 上可見 ⇒ 測得到
 *   （本尊那條路連瀏覽器 a11y tree 都穿不透 shadow DOM，實測方只能改讀 DOM property）。
 *
 * ⚠️ **本尊的一個無障礙落差，我方不照抄**：實測本尊「半選」與「全關」的 accessible name
 *   **完全相同**（都是 `Publish to all`），只有 `indeterminate` 能區分。我方同樣照抄了
 *   那組 label（鐵律 12），但因為有顯式 `aria-checked="mixed"`，兩態在 AX 上仍可區分。
 * ④跨功能影響：`aria-controls` 指向各列 switch 的 id（W3C ARIA APG
 *   Checkbox (Mixed-State) Example 逐字 "identify the set of checkboxes controlled by
 *   the mixed checkbox"）。視覺沿用我方 `.cl-switch` tokens（鐵律 8）。
 *
 * 🔴 **`checked` 由各列狀態於 render 期導出，不另存 state**——React 官方
 *   《Choosing the State Structure》逐字 "Avoid contradictions in state."
 *   （<https://react.dev/learn/choosing-the-state-structure>，取證 2026-08-27）。
 */
function GroupToggle({
  checked,
  label,
  controls,
  onChange,
}: {
  checked: boolean | "mixed";
  label: string;
  controls: string;
  onChange: (next: boolean) => void;
}) {
  return (
    <button
      aria-checked={checked === "mixed" ? "mixed" : checked}
      aria-controls={controls}
      aria-label={label}
      className={`cl-switch ${checked === true ? "cl-switch--on" : ""} ${checked === "mixed" ? "cl-switch--mixed" : ""}`.trim()}
      onClick={() => onChange(checked !== true)}
      role="checkbox"
      type="button"
    >
      <span aria-hidden="true" className="cl-switch__knob" />
    </button>
  );
}

/**
 * 管道列右側的排程入口（S6b-2b；本尊的日曆＋時鐘 icon，`docs/research/82` §12.3）。
 *
 * ①這是什麼：一顆 icon 鈕 ＋ 它開出的 `SchedulePopover`。
 * ②🔴 **顯示條件是該 publication 的 `supportsFuturePublishing`，不是「目前已發布」**
 *   （§15.10 實測：toggle 關掉時 icon 仍出現、彈層仍可開）。本尊只有 Online Store 有它。
 * ③已排程時 icon **常駐顯示**並帶 tooltip（§15.9：`Publish on: …`）；未排程時本尊是
 *   hover 才出現——⚠️ 我方**一律顯示**，登記為刻意偏離：hover-only 在觸控裝置上沒有
 *   對應手勢，而本尊那個 icon 是唯一的排程入口。
 * ④跨功能影響：`values.publicationDelta` 的 `at` 欄、送出的 `publishDate`、發布卡的 badge。
 */
function ChannelScheduleButton({
  publicationId,
  shopTimezone,
  now,
  scheduledAt,
  hasSavedSchedule,
  onSchedule,
  t,
}: {
  publicationId: string;
  shopTimezone: string;
  now: number;
  scheduledAt: number | null;
  hasSavedSchedule: boolean;
  onSchedule: (at: number) => void;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  const buttonRef = useRef<HTMLButtonElement | null>(null);
  const [open, setOpen] = useState(false);

  return (
    <>
      <button
        aria-haspopup="true"
        aria-label={scheduledAt === null
          ? t("schedule.title")
          : t("schedule.publishOn", { at: formatPublishDate(new Date(scheduledAt).toISOString()) })}
        className={`cl-icon-button ${scheduledAt === null ? "" : "cl-icon-button--on"}`.trim()}
        onClick={() => setOpen(true)}
        ref={buttonRef}
        type="button"
      >
        <CalendarClock aria-hidden="true" size={14} />
      </button>
      {/* 🔴 條件渲染而非 `open` prop——`SchedulePopover` 的 state 靠 unmount 清空
          （本尊每次重開彈層完全重置，§15.10）。 */}
      {open ? (
        <SchedulePopover
          anchorRef={buttonRef}
          hasSavedSchedule={hasSavedSchedule}
          now={now}
          onApply={(at) => { onSchedule(at); setOpen(false); }}
          onClose={() => setOpen(false)}
          scheduledAt={scheduledAt}
          shopTimezone={shopTimezone}
        />
      ) : null}
    </>
  );
}

/**
 * 逐商品的發布編輯 modal（S6b；`docs/research/82` §12.1 的第一種 affordance 的編輯部分）。
 *
 * ①這是什麼：商品詳情頁 `Publishing` 卡右上齒輪開啟的模態；列出**本店全部管道**，
 *   各帶一顆 toggle，開＝發布、關＝取消發布。標題逐字對位本尊
 *   `Manage publishing for <商品標題>`（82 §12.1）。
 * ②🔴 **語義是「狀態編輯器」不是「累加」**（82 §12.2 是 S2 最重要的一條）：
 *   逐商品 modal **顯示目前狀態**、勾掉＝取消發布；而**批次** modal 開場一律全部未勾、
 *   語義是累加／扣除。**兩者不得共用元件**——把逐商品做成累加語義，商家取消勾選不會生效；
 *   把批次做成狀態編輯器，商家的一次勾選會清空整個管道。
 * ③🔴 **`Done` 不寫入任何東西**（82 §13.1 實測：按 Done 當下**零 GraphQL 請求**，
 *   只是讓頁面出現 `Unsaved changes`）。它把 modal 內的草稿提交到
 *   `values.publicationDelta`，真正的寫入在頁面層級的 `Save`。
 *   `Cancel` 丟棄草稿。無變更時 `Done` disabled（本尊同形態）。
 * ④跨功能影響：`values.publicationDelta`（頁面 dirty／SaveBar）、
 *   儲存路徑的兩支獨立 mutation、儲存後 `publicationRows` 重讀。
 *   **排程（日曆 icon）屬 S6b-2**——本包不做，理由見下方 `supportsFuturePublishing` 的說明。
 *
 * ⚠️ **本尊四節我方只做一節**：本尊左欄有 `Sales Channels`／`Agentic`／`Catalogs›Regions`
 *   （82 §12.1）。我方 **Agentic 無資料層、catalog 成員表未落地（S10）** ⇒ 只有一節，
 *   故不渲染左欄導航（單項導航是噪音）。登記為 V，S10 落地時回頭補。
 */
function PublishingModal({
  productTitle,
  publications,
  rows,
  delta,
  shopTimezone,
  now,
  onApply,
  onClose,
  restoreFocusTo,
  t,
}: {
  productTitle: string;
  publications: PublicationOption[];
  rows: PublicationRow[];
  delta: PublicationDelta;
  shopTimezone: string;
  /** 開啟這次 modal 時的「現在」。**開啟時取一次**，不是每次 render——
   *  否則排程彈層的下限會在使用者填表期間一直往前跑。 */
  now: number;
  onApply: (next: PublicationDelta) => void;
  onClose: () => void;
  restoreFocusTo: RefObject<HTMLElement | null>;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  // 草稿＝modal 內的暫存。呼叫端條件渲染本元件 ⇒ 每次開啟都是新的初值，不需同步 effect。
  const [draft, setDraft] = useState<PublicationDelta>(delta);
  const [query, setQuery] = useState("");
  const searchId = useId();

  const visible = useMemo(() => matchChannels(publications, query), [publications, query]);

  // 🔴 判準＝「與**開啟本次 modal 時**的暫存值不同」，**不是**「draft 兩邊皆空」。
  //   理由與失效情境見 `sameDelta` 檔頭（開場已有暫存時，後者會讓撤銷變成按不下去）。
  //   開場 delta 為空時兩者行為完全相同 ⇒ 82 §12 那次觀察仍然成立。
  const changed = !sameDelta(draft, delta);

  // 🔴 群組態**由各列導出，不另存 state**（React 官方《Choosing the State Structure》
  //   逐字 "Avoid contradictions in state."）。全開／全關／半選三態。
  const onCount = visible.filter((pub) => channelIsOn(rows, draft, pub.id)).length;
  const groupState: boolean | "mixed" =
    visible.length > 0 && onCount === visible.length ? true : onCount === 0 ? false : "mixed";
  // 本尊實測：群組鈕的可及名稱隨狀態變（全開＝取消發布到全部；混合／全關＝發布到全部）
  // ⇒ **半選時點下去是「全開」**，不是全關。
  const groupLabel = groupState === true
    ? t("product.publishing.modal.unpublishAll")
    : t("product.publishing.modal.publishAll");

  const applyGroup = (next: boolean) =>
    setDraft((current) =>
      visible.reduce((acc, pub) => toggleChannel(rows, acc, pub.id, next), current));

  return (
    <Modal
      footer={
        <>
          <Button onClick={onClose}>{t("common.cancel")}</Button>
          <Button disabled={!changed} onClick={() => onApply(draft)} variant="primary">
            {t("common.done")}
          </Button>
        </>
      }
      onClose={onClose}
      open
      restoreFocusTo={restoreFocusTo}
      title={t("product.publishing.modal.title", { title: productTitle })}
    >
      <div className="cl-pubmodal">
        {/* 🔴 **這三個屬性是 ours，不是實測結論**：82 §12.2 對這個控件的全部逐字內容
            只有「`Search channels` 輸入框」，§14.3 補的是**行為**（詞首前綴／trim／
            大小寫／無結果文案／清除鈕），兩節都**沒有**記 input 的 type、placeholder
            是否可見、label 是否只給輔助科技 ⇒ 已列入 82 §14.10 的未取得表。
            ⚠️ 附帶的已知偏離：我方的清除鈕靠 `type=search` 的**瀏覽器原生**實作，
            Firefox 預設不渲染它；本尊實測右側有 `⊗`（§14.3）。 */}
        <TextField
          id={searchId}
          label={t("product.publishing.modal.search")}
          labelHidden
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t("product.publishing.modal.search")}
          type="search"
          value={query}
        />
        {/* 🔴 空態涵蓋**兩種**情況：搜尋無結果，以及本店根本沒有管道（`publications`
            查詢缺席時）。文案因此取中性的「找不到管道」——本尊同樣是一句
            `No channels found` 通吃兩者（82 §14.3）。 */}
        {/* 🔴 篩選結果的 status message（WCAG 2.2 SC 4.1.3，AA）。螢幕閱讀器使用者打字後
            清單靜默變動、焦點留在輸入框 ⇒ 沒有任何回饋可分辨「輸入框沒作用」與「0 筆相符」。
            🔴 **節點必須在切換前就存在於 DOM 且位置固定，只換文字**——把 role="status"
            掛在條件渲染的空態 <p> 上，部分 AT 會漏播（節點是新插入的）。 */}
        <p aria-live="polite" className="cl-sr-only" role="status">
          {t("product.publishing.modal.matchCount", { count: visible.length })}
        </p>
        {visible.length === 0 ? (
          <p className="cl-pubcard__empty">{t("product.publishing.modal.noMatch")}</p>
        ) : (
          <>
            {/* 群組列（本尊 82 §12.2：`Sales Channels` 群組列帶自己的 toggle，
                三個管道只有一個開著時呈**半選態**）。 */}
            <div className="cl-pubmodal__group">
              <span className="cl-pubmodal__group-label">{t("product.publishing.modal.group")}</span>
              {/* 🔴 accessible name **必須含可見文字**「銷售管道」（WCAG 2.5.3 Label in Name，
                  Level A，逐字 "the name contains the text that is presented visually"）。
                  只給 `groupLabel`（「發布到全部管道」）的話，語音輸入使用者照畫面唸
                  「點擊 銷售管道」會找不到任何控件——而視覺上那行字就在它旁邊。
                  下方每一列 SwitchRow 的 aria-label 本來就等於可見文字，只有這裡會破例。
                  ⚠️ 本尊有同樣落差（82 §14.1：label 屬性視覺隱藏、可見文字是另一個節點），
                  我方此處刻意偏離——與 mixed 態用顯式 aria-checked 同一個理由。 */}
              <GroupToggle
                checked={groupState}
                controls={visible.map((pub) => channelSwitchId(searchId, pub.id)).join(" ")}
                label={`${t("product.publishing.modal.group")} — ${groupLabel}`}
                onChange={applyGroup}
              />
            </div>
            <ul className="cl-pubmodal__list">
              {visible.map((pub) => (
                <li className="cl-pubmodal__row" key={pub.id}>
                  <SwitchRow
                    checked={channelIsOn(rows, draft, pub.id)}
                    id={channelSwitchId(searchId, pub.id)}
                    label={pub.title}
                    onChange={(next) => setDraft((current) => toggleChannel(rows, current, pub.id, next))}
                  />
                  {/* 🔴 只有 `supportsFuturePublishing` 的管道有排程入口（§12.3 實測：
                      對 Point of Sale 與 Shop 做同樣 hover 都不會出現這個 icon）。 */}
                  {pub.supportsFuturePublishing ? (
                    <ChannelScheduleButton
                      hasSavedSchedule={serverScheduleOf(rows, pub.id) !== null}
                      now={now}
                      onSchedule={(at) => setDraft((current) => scheduleChannel(current, pub.id, at))}
                      publicationId={pub.id}
                      scheduledAt={publishEntry(draft, pub.id)?.at ?? serverScheduleOf(rows, pub.id)}
                      shopTimezone={shopTimezone}
                      t={t}
                    />
                  ) : null}
                </li>
              ))}
            </ul>
          </>
        )}
      </div>
    </Modal>
  );
}

/**
 * 排程時間的顯示格式。
 *
 * 🔴 用瀏覽器 locale 呈現，**不自己拼字串**——本尊實測排程輸入框右側常駐顯示
 * 店鋪時區（`GMT+8`），時區語義屬 S6b 的排程編輯面；本切片只顯示，
 * 不宣稱它換算到店鋪時區（那需要 shop timezone，目前前端沒有）。
 */
function formatPublishDate(iso: string): string {
  const at = new Date(iso);
  if (Number.isNaN(at.getTime())) return iso;
  return at.toLocaleString();
}

/** 建立態的據點清單（初始數量欄的落點；v1 數量套用到第一個據點）。 */
const LOCATIONS_QUERY = `
  query productFormLocations {
    locations { id name }
  }
`;

interface LocationsData {
  locations: { id: string; name: string }[];
}

/** 該店已啟用的內容語言（ML-2；語言集合是資料，新增語言零部署即出欄位——67 §A.2）。 */
/** 媒體重讀（上傳／刪除後只重讀這一塊，不動使用者正在編輯的欄位）。 */
/** 媒體重排（拖曳後隨儲存送出）。 */
const REORDER_MEDIA_MUTATION = `
  mutation productReorderMedia($productId: ID!, $mediaIds: [ID!]!) {
    productReorderMedia(productId: $productId, mediaIds: $mediaIds) {
      media { id position }
      userErrors { field message code }
    }
  }
`;

/**
 * 發布／取消發布（S6b）。
 *
 * 🔴 **兩個方向是兩支獨立 mutation，且都不是 `productSet` 的一部分**——本尊實測
 * （`docs/research/82` §13.2）：同一顆 `Save` 送出**兩個** POST，`ProductSaveUpdate`
 * 與 `ProductSavePublishablePublishUnpublish`；只改發布時**只送後者**。
 * ⇒ 我方不得把 publish／unpublish 併進 `productSet`。
 *
 * 🔴 **`publishDate` 本包一律不送**：排程屬 S6b-2（需要日期時間輸入面與店鋪時區）。
 * 省略它＝立即發布（`Publications::Write` 的 R1／R3）；**傳 `null` 會被 reject**（R10），
 * 所以不得為了「型別完整」而顯式送 null。
 *
 * 🔴 **兩個方向放在同一個 document，用 `@include` 各自開關**——這是本尊 admin 的
 * 實際形態，2026-08-27 抓包取得 request variables 逐字（`82` §14）：
 *
 * ```
 * "shouldPublish": true, "shouldUnpublish": false,
 * "publicationsToPublish": [{"publicationId": "gid://shopify/Publication/209681645803"}],
 * "publicationsToUnpublish": []
 * ```
 *
 * 🔴 同次抓包還揭露一件單看 operation 名字看不出來的事：**`ProductSaveUpdate`
 * 也帶同樣那兩個 publications 陣列，但它的 `shouldPublish`／`shouldUnpublish`
 * 皆為 `false`** ⇒ 兩支 document 共用變數，靠 `@include` 決定誰真的執行，
 * **不會重複寫入**。我方照這個形態做：變數名與開關名都對齊本尊，
 * 空的那一邊**整個 field 不執行**（送空陣列會讓 `Publications::Write` 白跑一次
 * transaction 並 bump 一次 stamp）。
 *
 * ⇒ 回應形狀因此是**可選的**：被 skip 的那個 field 在 `data` 裡根本不存在，
 * 讀 `data.publishablePublish.userErrors` 會炸 ⇒ 消費端一律用可選鏈。
 *
 * GraphQL 規範對 mutation 的 top-level field 是**依序執行**，故一次往返即可。
 *
 * 🔴 **`publish` 排在 `unpublish` 前面是刻意的**：若順序相反且 publish 那半失敗，
 * 商品會落在「舊管道已移除、新管道沒加上」＝**意外全下架**。反過來若 unpublish
 * 那半失敗，最壞是多發布一個管道——「多可見」遠比「全不可見」輕。
 *
 * ⚠️ **與本尊的已知差異：我方兩個 field 各自一個 transaction，不是原子的。**
 * graphql-ruby 的 mutation 各自開 transaction（`Publications::Write.write_publishable`
 * 的 `ApplicationRecord.transaction` 在單支之內）⇒ 第二支失敗時第一支已提交。
 * 本尊那份 document 內部是不是原子＝**不可觀測**（persisted query，鐵律 14.3）。
 * 我方的收斂辦法是儲存後一律**重讀**伺服器現值（見 `save`），不做樂觀翻轉。
 */
const PUBLISHING_MUTATION = `
  mutation productPublishing(
    $id: ID!
    $publicationsToPublish: [PublicationInput!]!
    $publicationsToUnpublish: [PublicationInput!]!
    $shouldPublish: Boolean!
    $shouldUnpublish: Boolean!
  ) {
    publishablePublish(id: $id, input: $publicationsToPublish) @include(if: $shouldPublish) {
      userErrors { field message code }
    }
    publishableUnpublish(id: $id, input: $publicationsToUnpublish) @include(if: $shouldUnpublish) {
      userErrors { field message code }
    }
  }
`;

const MEDIA_QUERY = `
  query productMedia($id: ID!) {
    product(id: $id) {
      media { id position alt status image { thumbUrl url }
              externalVideo { host externalId embedUrl originUrl } }
    }
  }
`;

/**
 * 發布狀態重讀（S6b；儲存後與失敗後都走這一支）。
 *
 * 🔴 **不做樂觀翻轉**：`unpublish` 在後端是**硬刪列**、`publish` 可能因商品狀態不合格
 * 被拒，且兩支不在同一個 transaction ⇒ 本地翻轉會與伺服器真相分岔，而分岔的症狀是
 * 「後台顯示已發布、前台看不到」。一律重讀。
 *
 * 兩維（purchasable／discoverable）也一起重讀：取消發布會讓它們變 false，
 * 不重讀的話狀態卡會停在舊答案（S6a-2 的伺服器唯一答案原則）。
 */
const PUBLICATIONS_QUERY = `
  query productPublications($id: ID!) {
    product(id: $id) {
      purchasable
      discoverable
      resourcePublicationsV2(onlyPublished: false) {
        isPublished
        publishDate
        publication { id title supportsFuturePublishing }
      }
    }
  }
`;

const SHOP_LOCALES_QUERY = `
  query shopLocales {
    shopLocales { locale { tag endonym } isSource position }
  }
`;

interface ShopLocalesData {
  shopLocales: { locale: { tag: string; endonym: string }; isSource: boolean; position: number }[];
}

/** 可翻欄位（v1 三組：標題／說明／SEO 兩欄）。 */
type TranslatableField = "title" | "body_html" | "meta_title" | "meta_description";

/** locale → field → 值（來源語言那格永遠對映 base 欄位，不進 translations 送出）。 */
type TranslationMap = Record<string, Partial<Record<TranslatableField, string>>>;

/** 組織分類卡 autocomplete 的建議清單（91 §12；伺服端 distinct＋字母序）。 */
const SUGGESTIONS_QUERY = `
  query productOrganizationSuggestions {
    productVendors
    productTypes
  }
`;

interface SuggestionsData {
  productVendors: string[];
  productTypes: string[];
}

interface ProductSetData {
  productSet: {
    product: {
      id: string;
      handle: string;
      status: string;
      title: string;
      lockVersion: number;
      variants?: { nodes: { id: string; selectedOptions?: { name: string; value: string }[] }[] };
    } | null;
    userErrors: { field: string[] | null; message: string; code: string }[];
  };
}

/** `PUBLISHING_MUTATION` 的回應（兩個 field 各自回 userErrors）。 */
interface PublishingMutationData {
  // 🔴 兩者都可選：`@include(if: false)` 的 field 在回應的 `data` 裡**不存在**。
  publishablePublish?: { userErrors: { field: string[] | null; message: string; code: string }[] };
  publishableUnpublish?: { userErrors: { field: string[] | null; message: string; code: string }[] };
}

interface ProductQueryData {
  product: {
    id: string;
    title: string;
    descriptionHtml: string;
    status: string;
    handle: string;
    lockVersion: number;
    vendor: string | null;
    productType: string | null;
    tags: string[];
    seo: { title: string | null; description: string | null };
    translations: { locale: string; field: string; value: string; outdated: boolean }[];
    purchasable?: boolean;
    discoverable?: boolean;
    resourcePublicationsV2?: PublicationRow[];
    media?: MediaCardItem[];
    options?: { name: string; position: number; values: { value: string; position: number }[] }[];
    variants: {
      nodes: {
        id?: string;
        title?: string;
        position?: number;
        price: string;
        compareAtPrice: string | null;
        cost: string | null;
        sku: string | null;
        barcode: string | null;
        taxable: boolean;
        weightGrams?: number;
        requiresShipping?: boolean;
        selectedOptions?: { name: string; value: string }[];
      }[];
      pageInfo?: { hasNextPage: boolean };
    };
  } | null;
  publications?: PublicationOption[];
  shop?: { ianaTimezone: string };
}

/** 表單值（原型 PD_NEW 的對應子集；金額欄以原始輸入字串保存，送出才轉）。 */
interface FormValues {
  title: string;
  description: string;
  price: string;
  compare: string;
  cost: string;
  taxable: boolean;
  /** 隱含變體（無選項）的運送回聲欄——具名變體的存在 variantRows 裡。 */
  weightGrams: number;
  requiresShipping: boolean;
  sku: string;
  barcode: string;
  handle: string;
  status: string;
  vendor: string;
  productType: string;
  tags: string[];
  seoTitle: string;
  seoDescription: string;
  /** 非來源語言的譯文（ML-2）；來源語言的值在上面那些 base 欄位。 */
  translations: TranslationMap;
  /** 選項樹（空陣列＝無選項模式，走隱含單變體路）。 */
  options: OptionDraft[];
  /** 變體列（顯式清單，非笛卡兒積——lib/variantMatrix.ts ①）。 */
  variantRows: VariantRowData[];
  /** 媒體展示序（第 27 包；拖曳後進 SaveBar，隨儲存送 mediaOrder）。空＝不動順序。 */
  mediaOrder: string[];
  /**
   * 待送出的發布變更（S6b）。兩邊都空＝發布這一塊沒有未儲存變更。
   *
   * 🔴 **形態完全比照 `mediaOrder`**：進 `values` 是為了讓 `dirty` 自動亮、
   * SaveBar 自動出現（本尊實測 82 §13.1：modal 的 `Done` 不寫入任何東西，
   * 只讓頁面出現 `Unsaved changes`）；但送出走**獨立 mutation**，不進 `productSet`
   * （§13.2：本尊同一顆 Save 送兩個 POST，發布永遠是獨立的那一支）。
   *
   * 🔴 **這與 S6a「發布狀態不進 values」不衝突**：那句禁的是把**伺服器現況**
   * （`publicationRows`）塞進快照，不是禁使用者的**待送變更**。現況仍在
   * `publicationRows`，本欄只有 delta。
   *
   * 🔴 **是 delta 不是完整期望狀態**：後端就是 publish／unpublish 兩個方向的兩支
   * mutation（`Publications::Write` 的 publish＝建列或更新、unpublish＝硬刪列）。
   * 存完整期望狀態的話，送出前還要再與伺服器現況做一次差集——而那份現況可能
   * 已經被別的分頁改掉，差集會算錯。
   */
  publicationDelta: PublicationDelta;
}

/** 建立態預設值（原型 PD_NEW：金額 null＝空字串不是 0；taxable 預設 true）。 */
const INITIAL_VALUES: FormValues = {
  title: "",
  description: "",
  price: "",
  compare: "",
  cost: "",
  taxable: true,
  weightGrams: 0,
  requiresShipping: true,
  sku: "",
  barcode: "",
  handle: "",
  status: "DRAFT",
  vendor: "",
  productType: "",
  tags: [],
  seoTitle: "",
  seoDescription: "",
  translations: {},
  options: [],
  variantRows: [],
  mediaOrder: [],
  publicationDelta: { publish: [], unpublish: [] },
};

type FieldKey =
  | "title" | "price" | "compare" | "cost" | "handle"
  | "vendor" | "productType" | "seoTitle" | "seoDescription";

/** 伺服器 userErrors path（productSet 剝 `input` 首段後）→ 表單欄位。 */
const SERVER_PATHS: Record<string, FieldKey> = {
  title: "title",
  handle: "handle",
  vendor: "vendor",
  productType: "productType",
  "seo.title": "seoTitle",
  "seo.description": "seoDescription",
  "variants.0.price": "price",
  "variants.0.compareAtPrice": "compare",
  "variants.0.cost": "cost",
};

/**
 * 狀態 listbox 選項（91 §2：本尊每項帶描述副行；**封存不在 listbox**，
 * 只能走「更多動作→封存商品」）。副行文案為我方措辭（鐵律 9 不抄本尊文案），
 * 語義取自 13 §F1.2 真值表。
 */
const STATUS_OPTIONS: { value: string; labelKey: string; hintKey: string }[] = [
  { value: "ACTIVE", labelKey: "status.active", hintKey: "status.hint.active" },
  { value: "DRAFT", labelKey: "status.draft", hintKey: "status.hint.draft" },
  { value: "UNLISTED", labelKey: "status.unlisted", hintKey: "status.hint.unlisted" },
];

/** 封存態只在目前狀態＝ARCHIVED 時出現在 listbox（顯示用；解除走選其他值）。 */
const ARCHIVED_OPTION = { value: "ARCHIVED", labelKey: "status.archived", hintKey: "status.hint.archived" };

/** 「新增選項」建議名稱（我方措辭，鐵律 9 不抄本尊文案；自訂選項恆在末位）。 */
/** 鏡射 `config/limits.yml` `product.max_media`（正典在 limits，改那邊要同步）。 */
const MAX_PRODUCT_MEDIA = 250;

const SUGGESTED_OPTION_KEYS = [
  "product.options.suggested.size",
  "product.options.suggested.color",
  "product.options.suggested.material",
  "product.options.suggested.style",
] as const;

/** SEO 計數器的 SERP 建議值（不是上限；上限＝伺服端 70／320，91 §11）。 */
const SEO_TITLE_MAX = 70;
const SEO_DESCRIPTION_SERP = 160;
const SEO_DESCRIPTION_MAX = 320;

/**
 * 狀態呈現（正典＝原型 P_STATUS，chilllove-admin-v2.html:3105；
 * 與 ProductsPage 同表——文案與 pip 不得漂移）。
 */
const STATUS_PRESENTATION: Record<string, { labelKey: string; progress: BadgeProgress; tone: BadgeTone }> = {
  ACTIVE: { labelKey: "status.active", progress: "full", tone: "success" },
  ARCHIVED: { labelKey: "status.archived", progress: "full", tone: "default" },
  DRAFT: { labelKey: "status.draft", progress: "empty", tone: "info" },
  UNLISTED: { labelKey: "status.unlisted", progress: "empty", tone: "attention" },
};

/**
 * 兩維真值表的**狀態那一層**（13 §F1.2：discoverable ⊆ purchasable 恆成立）。
 *
 * 🔴 **2026-08-27（S6a-2）起本表只剩兩個用途**，完整判定已由伺服器提供：
 *   ①**建立態**（商品還沒存檔 ⇒ 伺服器上不存在，問不到）；
 *   ②**編輯態下使用者剛改了狀態下拉、尚未儲存**時的即時回饋
 *     （伺服器答的是**已儲存**的狀態，不是草稿值）。
 *
 * 🔴 **這不是「這個商品可不可購買」的完整判定，只是狀態層**。
 * 完整判定＝狀態層 ∧ 商品發布層 ∧ 變體發布層，唯一產生處在伺服器端的
 * `Product.purchasable` / `Product.discoverable`（GraphQL 欄位，S6a-2 已接）。
 *
 * ⚠️ **不得在這裡擴充成完整判定**（鐵律 7）：前端硬算出來的第二個答案遲早與
 * 伺服器分岔，而分岔的症狀是「後台說可購買、前台買不到」。
 */
const STATUS_DIMENSIONS: Record<string, { purchasable: boolean; discoverable: boolean }> = {
  ACTIVE: { purchasable: true, discoverable: true },
  UNLISTED: { purchasable: true, discoverable: false },
  DRAFT: { purchasable: false, discoverable: false },
  ARCHIVED: { purchasable: false, discoverable: false },
};

/** 純文字說明 → 段落 HTML（伺服器端再做白名單 sanitize，雙保險的前半）。 */
export function descriptionToHtml(text: string): string {
  const paragraphs = text
    .split(/\n{2,}/)
    .map((paragraph) => paragraph.trim())
    .filter(Boolean);
  return paragraphs
    .map((paragraph) => `<p>${escapeHtml(paragraph).replaceAll("\n", "<br>")}</p>`)
    .join("");
}

/** 已儲存的段落 HTML → textarea 純文字（descriptionToHtml 的反向，編輯態載入用）。 */
export function htmlToDescription(html: string): string {
  return html
    .replaceAll(/<br\s*\/?>/gi, "\n")
    .replaceAll(/<\/p>\s*<p>/gi, "\n\n")
    .replaceAll(/<\/?p>/gi, "")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&")
    .trim();
}

/** GraphQL translations 列 → locale/field 巢狀 map（前端表單值形態）。 */
function toTranslationMap(rows: { locale: string; field: string; value: string }[]): TranslationMap {
  const map: TranslationMap = {};
  for (const row of rows) {
    map[row.locale] = { ...(map[row.locale] ?? {}), [row.field as TranslatableField]: row.value };
  }
  return map;
}

/**
 * 表單 map → productSet 的 translations 陣列。
 *
 * 🔴 逐欄位一列（不是每語言一包 JSON）：67 §E.2-1 硬規則 1——map 形態承載不了
 * 六個稽核欄，也毀掉欄位級 digest／過期標記／翻譯 CSV。
 * 🔴 來源語言略過：它的文字在 base row，寫進 translations 會被伺服端 reject（INVALID）。
 */
function translationEntries(map: TranslationMap, sourceLocale: string) {
  const fields: TranslatableField[] = [ "title", "body_html", "meta_title", "meta_description" ];
  const entries: { locale: string; field: TranslatableField; value: string }[] = [];
  for (const [ locale, byField ] of Object.entries(map)) {
    if (locale === sourceLocale) continue;
    for (const field of fields) {
      const value = byField[field];
      if (value === undefined) continue;
      entries.push({ locale, field, value });
    }
  }
  return entries;
}

function escapeHtml(raw: string): string {
  return raw
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

/** 開關列（原型 .swrow；v1 多為未接線 ⇒ disabled）。 */
function SwitchRow({
  label,
  hint,
  checked,
  disabled,
  id,
  onChange,
}: {
  label: string;
  hint?: string;
  checked: boolean;
  disabled?: boolean;
  /** 給群組總開關的 `aria-controls` 指得到（S6b）。 */
  id?: string;
  onChange?: (next: boolean) => void;
}) {
  return (
    <div className="cl-swrow">
      <div className="cl-swrow__text">
        {label}
        {hint ? <span>{hint}</span> : null}
      </div>
      <button
        aria-checked={checked}
        aria-label={label}
        className={`cl-switch ${checked ? "cl-switch--on" : ""}`}
        disabled={disabled}
        id={id}
        onClick={onChange ? () => onChange(!checked) : undefined}
        role="switch"
        type="button"
      >
        <span aria-hidden="true" className="cl-switch__knob" />
      </button>
    </div>
  );
}

/** pill 收合組（原型 .pills/.pillpanel：透明無框、展開 sunken 底、▾ 旋轉）。 */
function PillGroup({
  pills,
  open,
  onToggle,
}: {
  pills: { key: string; label: string; value?: string }[];
  open: ReadonlySet<string>;
  onToggle: (key: string) => void;
}) {
  return (
    <div className="cl-pills">
      {pills.map((pill) => (
        <button
          aria-expanded={open.has(pill.key)}
          className="cl-pill"
          key={pill.key}
          onClick={() => onToggle(pill.key)}
          type="button"
        >
          {pill.label}
          {pill.value ? <span className="cl-pill__value">{pill.value}</span> : null}
          <span aria-hidden="true" className="cl-pill__chevron">
            ▾
          </span>
        </button>
      ))}
    </div>
  );
}

/**
 * 狀態選單（91 §2 形態：按鈕＋listbox popover，每項主文＋描述副行）。
 * 原生 select 的 option 放不下副行 ⇒ 自訂 listbox；鍵盤：Escape 關閉、點選即選取。
 */
function StatusListbox({
  value,
  onChange,
  labelId,
}: {
  value: string;
  onChange: (next: string) => void;
  labelId?: string;
}) {
  const t = useT();
  const [open, setOpen] = useState(false);
  const listId = useId();
  const options = value === "ARCHIVED" ? [ ...STATUS_OPTIONS, ARCHIVED_OPTION ] : STATUS_OPTIONS;
  const current = options.find((option) => option.value === value) ?? STATUS_OPTIONS[1];

  return (
    <div className="cl-statusbox">
      <button
        aria-controls={listId}
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-labelledby={labelId}
        className="cl-field__input cl-statusbox__button"
        onClick={() => setOpen((state) => !state)}
        onKeyDown={(event) => {
          if (event.key === "Escape") setOpen(false);
        }}
        type="button"
      >
        {t(current.labelKey)}
        <ChevronDown aria-hidden="true" size={14} />
      </button>
      {open ? (
        <ul aria-label={t("product.status.label")} className="cl-statusbox__list" id={listId} role="listbox">
          {options.map((option) => (
            <li
              aria-selected={option.value === value}
              className={`cl-statusbox__option ${option.value === value ? "cl-statusbox__option--active" : ""}`}
              key={option.value}
              onClick={() => {
                onChange(option.value);
                setOpen(false);
              }}
              role="option"
            >
              <span className="cl-statusbox__check">
                {option.value === value ? <Check aria-hidden="true" size={14} /> : null}
              </span>
              <span className="cl-statusbox__text">
                {t(option.labelKey)}
                <span>{t(option.hintKey)}</span>
              </span>
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}

/**
 * 標籤欄（91 §12：token 多值）。Enter／逗號提交；chip × 移除。
 * 草稿輸入獨立於表單值 ⇒ 只敲了一半的標籤不會弄髒 SaveBar。
 */
function TagsField({
  tags,
  onChange,
  suggestions,
  label,
  placeholder,
  removeLabel,
}: {
  tags: string[];
  onChange: (next: string[]) => void;
  suggestions: string[];
  /** 欄位標籤；預設＝商品標籤（既有唯一呼叫端）。 */
  label?: string;
  placeholder?: string;
  removeLabel?: (tag: string) => string;
}) {
  const t = useT();
  const [draft, setDraft] = useState("");
  const inputId = useId();
  const listId = useId();

  const commit = () => {
    const value = draft.trim().replace(/,+$/, "").trim();
    setDraft("");
    if (!value || tags.includes(value)) return;
    onChange([ ...tags, value ]);
  };

  return (
    <div className="cl-field">
      <label className="cl-field__label" htmlFor={inputId}>
        {label ?? t("product.org.tags")}
      </label>
      {tags.length > 0 ? (
        <div className="cl-chips">
          {tags.map((tag) => (
            <span className="cl-chip" key={tag}>
              {tag}
              <button
                aria-label={removeLabel ? removeLabel(tag) : t("product.org.tags.remove", { tag })}
                className="cl-chip__remove"
                onClick={() => onChange(tags.filter((existing) => existing !== tag))}
                type="button"
              >
                <X aria-hidden="true" size={11} />
              </button>
            </span>
          ))}
        </div>
      ) : null}
      <input
        className="cl-field__input"
        id={inputId}
        list={listId}
        onChange={(event) => {
          if (event.target.value.endsWith(",")) {
            setDraft(event.target.value);
            // 逗號輸入即提交（IME 安全：組字期間不會產生裸逗號）
            const value = event.target.value.slice(0, -1).trim();
            setDraft("");
            if (value && !tags.includes(value)) onChange([ ...tags, value ]);
            return;
          }
          setDraft(event.target.value);
        }}
        onKeyDown={(event) => {
          if (event.key === "Enter") {
            event.preventDefault();
            commit();
          }
        }}
        placeholder={placeholder ?? t("product.org.tags.placeholder")}
        value={draft}
      />
      <datalist id={listId}>
        {suggestions.map((suggestion) => (
          <option key={suggestion} value={suggestion} />
        ))}
      </datalist>
    </div>
  );
}

/**
 * 呈現商品建立／編輯頁。
 *
 * @param props - isNew 分流。
 * @returns 對齊原型卡片樹的商品表單。
 */
export function ProductDetailPage({ isNew }: ProductDetailPageProps) {
  const navigate = useNavigate();
  const params = useParams();
  const t = useT();
  const { showToast } = useToast();
  const registerSaveBar = useSaveBarRegister();

  const productGid = isNew ? null : decodeURIComponent(params.id ?? "");

  const [values, setValues] = useState<FormValues>(INITIAL_VALUES);
  const [errors, setErrors] = useState<Partial<Record<FieldKey, string>>>({});
  const [saving, setSaving] = useState(false);
  const [loadState, setLoadState] = useState<"loading" | "ready" | "missing">(
    isNew ? "ready" : "loading",
  );
  const [lockVersion, setLockVersion] = useState(0);
  const [openPills, setOpenPills] = useState<ReadonlySet<string>>(new Set());
  const [shakeSignal, setShakeSignal] = useState(0);
  const [seoOpen, setSeoOpen] = useState(false);
  const [actionsOpen, setActionsOpen] = useState(false);
  // 「新增選項」建議選單（排程：popover→自訂選項→inline→chips；menu-popover 形態）
  const [optionMenuOpen, setOptionMenuOpen] = useState(false);
  // 破壞性動作確認（包 4）：null＝無待確認；封存走確認框、取消封存不用（可逆）。
  const [confirmAction, setConfirmAction] = useState<"discard" | "archive" | null>(null);
  const [suggestions, setSuggestions] = useState<SuggestionsData>({ productVendors: [], productTypes: [] });
  // 發布狀態（唯讀顯示，S6a）。🔴 **不進 `values`／`snapshot`**——它不是本表單的欄位，
  //   發布寫入走 `publishablePublish`／`publishableUnpublish` 獨立 mutation（S6b），
  //   混進表單快照會讓 SaveBar 對「不是本表單負責的東西」報髒。
  const [publicationRows, setPublicationRows] = useState<PublicationRow[]>([]);
  // 本店全部管道（modal 的骨架；`publicationRows` 只有已發布／已排程的那些）。
  const [publications, setPublications] = useState<PublicationOption[]>([]);
  const [publishingOpen, setPublishingOpen] = useState(false);
  // 🔴 排程一律用**店鋪時區**（`Query.shop.ianaTimezone`）。載入前先給 UTC——
  //   此時彈層也開不起來（齒輪只在編輯態且資料載入後才可按），不會用瀏覽器時區算錯。
  const [shopTimezone, setShopTimezone] = useState("UTC");
  // 🔴 開啟 modal 那一刻的「現在」。**不能每次 render 取**——排程彈層用它算下限
  //   （今天之前灰掉、過去時間夾到 now），每次 render 都新的話下限會在使用者填表期間
  //   一直往前爬，剛選好的時間下一秒就變成「過去」。
  const [publishingOpenedAt, setPublishingOpenedAt] = useState(0);
  // 🔴 重讀失敗的第三態。**不能用「空清單」代替**——那會冒充「沒有發布到任何管道」，
  //   與「不知道現在發布到哪些管道」是兩件完全不同的事。
  const [publicationsStale, setPublicationsStale] = useState(false);
  // 伺服器算的可見性兩維（`null`＝尚未載入／建立態）。
  const [serverVisibility, setServerVisibility] =
    useState<{ purchasable: boolean; discoverable: boolean } | null>(null);
  // 伺服器那份答案對應的**已儲存狀態**——用來判斷使用者是否改了下拉還沒存。
  const [savedStatus, setSavedStatus] = useState<string>("DRAFT");
  // 變體列的逐列錯誤（index → 訊息）；選項模式下取代 price/compare/cost 的欄位級映射
  const [rowErrors, setRowErrors] = useState<Record<number, string>>({});
  // 建立態據點（初始數量欄；v1 套用到第一個據點）
  const [locations, setLocations] = useState<{ id: string; name: string }[]>([]);
  // 🔴 變體超過 250（查詢截斷）：宣告式儲存會把沒載到的變體整批刪掉（審查 C0）
  //    ——整頁儲存封鎖，顯示 tooMany 警示，交 API／29 包子頁處理。
  const [variantOverflow, setVariantOverflow] = useState(false);
  // 內容語言（來源語言排第一）；載入前先給來源語言一格，避免建立頁閃空。
  const [contentLocales, setContentLocales] = useState<{ tag: string; endonym: string; isSource: boolean }[]>([]);
  // 媒體清單（伺服端真相；上傳／刪除後重讀。只有「順序」是表單值＝values.mediaOrder）
  const [media, setMedia] = useState<MediaCardItem[]>([]);
  // locale → 已過期的欄位集合（伺服端 translations.outdated；前端不自行推算，重載才更新）。
  const [outdatedFields, setOutdatedFields] = useState<Record<string, Set<TranslatableField>>>({});
  // 更多動作→封存／取消封存：改狀態後立即儲存（本尊為即時動作，不停在 SaveBar）。
  const pendingAutoSave = useRef(false);

  // 冪等鍵：建立態專用（更新態是宣告式覆寫、天然冪等，防線是 lockVersion——D-PS5）。
  const idempotencyKey = useRef<string>(uuidV4());
  const fieldRefs = useRef<Partial<Record<FieldKey, HTMLInputElement | null>>>({});
  // modal 焦點還原目標（觸發鈕隨開框 unmount：選單項→更多動作鈕、SaveBar→頁標題）
  const actionsButtonRef = useRef<HTMLButtonElement | null>(null);
  const headingRef = useRef<HTMLHeadingElement | null>(null);
  const publishingButtonRef = useRef<HTMLButtonElement | null>(null);
  const rowPriceRefs = useRef<(HTMLInputElement | null)[]>([]);
  // 本編輯階段被剔除的列（審查 C1：刪值再加回要復活原列，不是空白 freshRow
  // ——空白列會被後端 digest-match 後宣告式抹掉既有變體的回聲欄）
  const rowGraveyard = useRef(new Map<string, VariantRowData>());
  // 伺服錯誤的待聚焦目標：saving 期間 fieldset disabled、focus() 打不進——
  // 存起來等 saving 落 false 的 effect 再聚焦。
  const pendingErrorFocus = useRef<{ field?: FieldKey; row?: number } | null>(null);

  const snapshot = useRef(JSON.stringify(INITIAL_VALUES));
  const dirty = useMemo(() => JSON.stringify(values) !== snapshot.current, [values]);

  /**
   * 有排程的管道數（發布卡標題列的 badge，本尊 §15.9）。
   *
   * 🔴 **伺服器現值套上待送 delta**，不是只數伺服器——商家剛在彈層設好時間按了 Done，
   * badge 要立刻出現（§13.1 的樂觀更新）；同理被取消發布的管道要扣掉。
   */
  const scheduledCount = useMemo(() => {
    const ids = new Set<string>();
    for (const row of publicationRows) {
      if (serverScheduleOf(publicationRows, row.publication.id) !== null) ids.add(row.publication.id);
    }
    for (const entry of values.publicationDelta.publish) {
      if (entry.at === null) ids.delete(entry.publicationId);   // 改成立即發布 ⇒ 不再是排程
      else ids.add(entry.publicationId);
    }
    for (const id of values.publicationDelta.unpublish) ids.delete(id);
    return ids.size;
  }, [publicationRows, values.publicationDelta]);

  // 編輯態：載入既有商品填表（隱含變體恆一筆，B1-2）。
  useEffect(() => {
    if (isNew || !productGid) return;
    const controller = new AbortController();
    setLoadState("loading");

    requestAdminGraphQL<ProductQueryData, { id: string }>(
      PRODUCT_QUERY,
      { id: productGid },
      controller.signal,
    )
      .then((data) => {
        const product = data.product;
        if (!product) {
          setLoadState("missing");
          return;
        }
        const variant = product.variants.nodes[0];
        const optionDrafts: OptionDraft[] = [ ...(product.options ?? []) ]
          .sort((left, right) => left.position - right.position)
          .map((option) => ({
            key: uuidV4(),
            name: option.name,
            values: [ ...option.values ].sort((a, b) => a.position - b.position).map((v) => v.value),
          }));
        const variantRows: VariantRowData[] = optionDrafts.length === 0 ? [] :
          product.variants.nodes.map((node) => ({
            id: node.id ?? null,
            coords: optionDrafts.map((option) =>
              (node.selectedOptions ?? []).find((so) => so.name === option.name)?.value ?? ""),
            price: node.price,
            sku: node.sku ?? "",
            quantity: "",
            compare: node.compareAtPrice ?? "",
            cost: node.cost ?? "",
            barcode: node.barcode ?? "",
            taxable: node.taxable,
            // 🔴 回聲欄（第 29 包）：不載入就等於「送出時不送」＝把變體子頁設好的
            //    重量清成 0、requiresShipping 清成 true。
            weightGrams: node.weightGrams ?? 0,
            requiresShipping: node.requiresShipping ?? true,
          }));
        const loaded: FormValues = {
          title: product.title,
          description: htmlToDescription(product.descriptionHtml),
          price: variant?.price ?? "",
          compare: variant?.compareAtPrice ?? "",
          cost: variant?.cost ?? "",
          taxable: variant?.taxable ?? true,
          weightGrams: variant?.weightGrams ?? 0,
          requiresShipping: variant?.requiresShipping ?? true,
          sku: variant?.sku ?? "",
          barcode: variant?.barcode ?? "",
          handle: product.handle,
          status: product.status,
          vendor: product.vendor ?? "",
          productType: product.productType ?? "",
          tags: product.tags ?? [],
          seoTitle: product.seo?.title ?? "",
          seoDescription: product.seo?.description ?? "",
          translations: toTranslationMap(product.translations),
          options: optionDrafts,
          variantRows,
          mediaOrder: [],
          publicationDelta: { publish: [], unpublish: [] },
        };
        snapshot.current = JSON.stringify(loaded);
        setValues(loaded);
        setPublicationRows(product.resourcePublicationsV2 ?? []);
        setPublications(salesChannelsOf(data.publications ?? []));
        if (data.shop?.ianaTimezone) setShopTimezone(data.shop.ianaTimezone);
        setServerVisibility(
          typeof product.purchasable === "boolean" && typeof product.discoverable === "boolean"
            ? { purchasable: product.purchasable, discoverable: product.discoverable }
            : null,
        );
        setSavedStatus(product.status);
        setMedia([ ...(product.media ?? []) ].sort((a, b) => a.position - b.position));
        rowGraveyard.current.clear();
        setVariantOverflow(product.variants.pageInfo?.hasNextPage ?? false);
        setOutdatedFields(
          product.translations.reduce<Record<string, Set<TranslatableField>>>((accumulator, row) => {
            if (!row.outdated) return accumulator;
            const set = accumulator[row.locale] ?? new Set<TranslatableField>();
            set.add(row.field as TranslatableField);
            return { ...accumulator, [row.locale]: set };
          }, {}),
        );
        setLockVersion(product.lockVersion);
        setLoadState("ready");
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        showToast(reason instanceof Error ? reason.message : t("product.loadFailed"));
        setLoadState("missing");
      });

    return () => controller.abort();
  }, [isNew, productGid, showToast, t]);

  const setValue = useCallback(<Key extends keyof FormValues>(key: Key, value: FormValues[Key]) => {
    setValues((current) => ({ ...current, [key]: value }));
  }, []);

  // 組織分類卡的 autocomplete 建議（91 §12）。失敗靜默：建議清單是增強不是資料，
  // 空清單只是少了 datalist，欄位照常可打字。
  useEffect(() => {
    const controller = new AbortController();
    requestAdminGraphQL<SuggestionsData, Record<string, never>>(SUGGESTIONS_QUERY, {}, controller.signal)
      .then((data) => setSuggestions(data))
      .catch(() => {});
    return () => controller.abort();
  }, []);

  // 建立態據點（初始數量欄）。失敗靜默：沒有據點清單只是數量欄不出現，表單照常。
  useEffect(() => {
    if (!isNew) return;
    const controller = new AbortController();
    requestAdminGraphQL<LocationsData, Record<string, never>>(LOCATIONS_QUERY, {}, controller.signal)
      .then((data) => setLocations(data.locations))
      .catch(() => {});
    return () => controller.abort();
  }, [isNew]);

  // 已啟用內容語言（ML-2）。失敗時退回「只有來源語言」——寧可少幾格，不要整頁掛掉。
  useEffect(() => {
    const controller = new AbortController();
    requestAdminGraphQL<ShopLocalesData, Record<string, never>>(SHOP_LOCALES_QUERY, {}, controller.signal)
      .then((data) => {
        const rows = [ ...data.shopLocales ].sort((left, right) => {
          if (left.isSource !== right.isSource) return left.isSource ? -1 : 1;
          return left.position - right.position;
        });
        setContentLocales(rows.map((row) => ({ tag: row.locale.tag, endonym: row.locale.endonym, isSource: row.isSource })));
      })
      .catch(() => setContentLocales([]));
    return () => controller.abort();
  }, []);

  // 選項變更唯一入口（加/刪選項、加/刪值都走這裡；🔴 改名不走——coords 是位置制，
  // 改名不動列；若把改名餵進 rebuildRows 會被當成刪＋加、整個維度的列值歸位重置）。
  const applyOptionsChange = useCallback((nextOptions: OptionDraft[]) => {
    // 🔴 零值選項＝UI 草稿，不進列模型——否則「先加選項、後打值」的空檔
    //    會把既有列清光（cartesian 含空值集＝零組合），值回來時 id／價格全重置。
    const effective = (list: OptionDraft[]) => list.filter((option) => option.values.length > 0);
    const seed: RowSeed = {
      price: values.price, sku: values.sku, compare: values.compare,
      cost: values.cost, barcode: values.barcode, taxable: values.taxable,
    };
    const effPrev = effective(values.options);
    const effNext = effective(nextOptions);
    // 埋葬現行列（座標身分＝選項 key 序＋座標）——之後座標重現即復活原列
    for (const row of values.variantRows) {
      rowGraveyard.current.set(graveKey(effPrev, row.coords), row);
    }
    const rows = rebuildRows(effPrev, effNext, values.variantRows, seed, rowGraveyard.current);
    if (rows === null) {
      // 超渲染上限：不套用且明說（審查 C6——靜默丟輸入不可接受）
      showToast(t("product.options.overflow"));
      return;
    }
    setValues((current) => ({ ...current, options: nextOptions, variantRows: rows }));
    setRowErrors({});
  }, [showToast, t, values]);

  const renameOption = useCallback((index: number, name: string) => {
    setValues((current) => ({
      ...current,
      options: current.options.map((option, i) => (i === index ? { ...option, name } : option)),
    }));
  }, []);

  const setRowField = useCallback((index: number, key: "price" | "sku" | "quantity", value: string) => {
    setValues((current) => ({
      ...current,
      variantRows: current.variantRows.map((row, i) => (i === index ? { ...row, [key]: value } : row)),
    }));
  }, []);

  const togglePill = useCallback((key: string) => {
    setOpenPills((current) => {
      const next = new Set(current);
      if (next.has(key)) next.delete(key);
      else next.add(key);
      return next;
    });
  }, []);

  // 原型 formValidate：req/max/money/handle 規則；失敗 → toast＋shake＋focus 首個壞欄位。
  const validate = useCallback((): boolean => {
    const found: Partial<Record<FieldKey, string>> = {};
    const rowFound: Record<number, string> = {};
    if (!values.title.trim()) found.title = t("product.validation.titleBlank");
    else if (values.title.length > 255) found.title = t("product.validation.titleTooLong", { max: 255 });

    if (values.options.length > 0) {
      // 選項模式：金額規則落在逐列；選項本身要名稱非空不重複、至少一個值
      const names = values.options.map((option) => option.name.trim());
      if (names.some((name) => !name) || new Set(names).size !== names.length ||
          values.options.some((option) => option.values.length === 0)) {
        rowFound[-1] = t("product.validation.optionsInvalid"); // -1＝選項層錯誤：只 toast＋shake，不聚焦列
      }
      values.variantRows.forEach((row, index) => {
        if (!row.price.trim()) rowFound[index] = t("product.validation.priceRequired");
        else if (!isValidMoneyInput(row.price)) rowFound[index] = t("product.validation.moneyInvalid");
        else if (row.quantity.trim() && !/^\d+$/.test(row.quantity.trim())) {
          rowFound[index] = t("product.validation.quantityInvalid");
        }
      });
    } else {
      if (!values.price.trim()) found.price = t("product.validation.priceRequired");
      else if (!isValidMoneyInput(values.price)) {
        found.price = t("product.validation.moneyInvalid");
      }
      if (!isValidMoneyInput(values.compare)) {
        found.compare = t("product.validation.moneyInvalid");
      }
      if (!isValidMoneyInput(values.cost)) {
        found.cost = t("product.validation.moneyInvalid");
      }
    }
    if (values.handle && !/^[a-z0-9-]+$/.test(values.handle)) {
      found.handle = t("product.validation.handleInvalid");
    }
    if (values.seoTitle.length > SEO_TITLE_MAX) {
      found.seoTitle = t("product.validation.seoTitleTooLong", { max: SEO_TITLE_MAX });
    }
    if (values.seoDescription.length > SEO_DESCRIPTION_MAX) {
      found.seoDescription = t("product.validation.seoDescriptionTooLong", { max: SEO_DESCRIPTION_MAX });
    }

    setErrors(found);
    setRowErrors(rowFound);
    const firstBad = (Object.keys(found) as FieldKey[])[0];
    const firstBadRow = Object.keys(rowFound).map(Number).filter((i) => i >= 0).sort((a, b) => a - b)[0];
    if (firstBad || Object.keys(rowFound).length > 0) {
      showToast(t("product.validation.failed"));
      setShakeSignal((signal) => signal + 1);
      if (firstBad) fieldRefs.current[firstBad]?.focus();
      else if (firstBadRow !== undefined) rowPriceRefs.current[firstBadRow]?.focus();
      return false;
    }
    return true;
  }, [isNew, showToast, t, values]);

  const applyServerErrors = useCallback(
    (userErrors: ProductSetData["productSet"]["userErrors"]) => {
      const mapped: Partial<Record<FieldKey, string>> = {};
      const rowMapped: Record<number, string> = {};
      const unmapped: string[] = [];
      const optionsMode = values.options.length > 0;
      for (const userError of userErrors) {
        const path = userError.field?.join(".") ?? "";
        const rowMatch = optionsMode ? /^variants\.(\d+)(?:\.|$)/.exec(path) : null;
        if (rowMatch) {
          rowMapped[Number(rowMatch[1])] = userError.message;
          continue;
        }
        const key = userError.field ? SERVER_PATHS[path] : undefined;
        if (key) mapped[key] = userError.message;
        else unmapped.push(userError.message);
      }
      setErrors(mapped);
      setRowErrors(rowMapped);
      showToast(unmapped[0] ?? t("product.validation.failed"));
      setShakeSignal((signal) => signal + 1);
      const firstBad = (Object.keys(mapped) as FieldKey[])[0];
      const firstBadRow = Object.keys(rowMapped).map(Number).sort((a, b) => a - b)[0];
      pendingErrorFocus.current =
        firstBad ? { field: firstBad } :
        firstBadRow !== undefined ? { row: firstBadRow } : { field: "title" };
    },
    [showToast, t, values.options.length],
  );

  // 伺服錯誤聚焦（見 pendingErrorFocus 註）：等 saving 解鎖、DOM 已重繪再聚焦。
  useEffect(() => {
    if (saving) return;
    const target = pendingErrorFocus.current;
    if (!target) return;
    pendingErrorFocus.current = null;
    if (target.field) fieldRefs.current[target.field]?.focus();
    else if (target.row !== undefined) rowPriceRefs.current[target.row]?.focus();
  }, [saving, errors, rowErrors]);

  // 媒體重讀（上傳／刪除／alt 之後）。只重讀媒體不重讀整個表單——
  // 否則使用者打到一半的欄位會被伺服端值蓋掉。
  /** 重讀發布狀態與可見性兩維（儲存後與失敗後都走這裡；見 `PUBLICATIONS_QUERY` 檔頭）。 */
  const reloadPublications = useCallback(async () => {
    if (!productGid) return;
    try {
      const data = await requestAdminGraphQL<ProductQueryData, { id: string }>(
        PUBLICATIONS_QUERY, { id: productGid },
      );
      setPublicationRows(data.product?.resourcePublicationsV2 ?? []);
      setServerVisibility(
        typeof data.product?.purchasable === "boolean" && typeof data.product?.discoverable === "boolean"
          ? { purchasable: data.product.purchasable, discoverable: data.product.discoverable }
          : null,
      );
      setPublicationsStale(false);
    } catch (reason: unknown) {
      // 🔴 **旗標比 toast 重要**：toast 幾秒後就消失，而此刻 `publicationRows` 已經是
      //   過期的（伺服器上那筆取消發布已生效、delta 也已歸零、SaveBar 也消失了）。
      //   不標記的話卡片會繼續把已下架的管道顯示成綠色「已發布」，商家重開 modal 看到
      //   開關是「開」、再撥關一次再存——而 unpublish 對不存在的列是 no-op success
      //   ⇒ 畫面永遠不變，只有重新整理才看得到真相。
      setPublicationsStale(true);
      showToast(reason instanceof Error ? reason.message : t("product.publishing.reloadFailed"));
    }
  }, [productGid, showToast, t]);

  const reloadMedia = useCallback(async () => {
    if (!productGid) return;

    try {
      const data = await requestAdminGraphQL<ProductQueryData, { id: string }>(
        MEDIA_QUERY, { id: productGid },
      );
      const rows = [ ...(data.product?.media ?? []) ].sort((a, b) => a.position - b.position);
      setMedia(rows);
      // 🔴 **只在「待存順序已對不上伺服端集合」時才清**（審查 C7）：原本無條件清空，
      //    上傳／刪除／alt 失焦都會靜默丟掉使用者拖好還沒存的順序。
      //    對得上就保留——新上傳的圖接在待存順序尾端（orderedMedia 負責併上）。
      setValues((current) => {
        if (current.mediaOrder.length === 0) return current;

        const live = new Set(rows.map((row) => row.id));
        const stale = current.mediaOrder.some((id) => !live.has(id));
        return stale ? { ...current, mediaOrder: [] } : current;
      });
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("product.media.reloadFailed"));
    }
  }, [productGid, showToast, t]);

  // 顯示序＝待存的拖曳結果（若有）否則伺服端序
  const orderedMedia = useMemo(() => {
    if (values.mediaOrder.length === 0) return media;

    const byId = new Map(media.map((item) => [ item.id, item ]));
    const ordered = values.mediaOrder
      .map((id) => byId.get(id))
      .filter((item): item is MediaCardItem => !!item);
    // 🔴 待存順序之外的媒體（拖曳後才上傳的那幾張）接在尾端——直接 filter 掉會讓
    //    使用者剛傳好的圖從畫面上消失（審查 C7 的下半）。
    const known = new Set(values.mediaOrder);
    return [ ...ordered, ...media.filter((item) => !known.has(item.id)) ];
  }, [media, values.mediaOrder]);

  const save = useCallback(async () => {
    if (saving) return;
    if (variantOverflow) {
      // 宣告式全量：只載到前 250 列，儲存＝把其餘變體整批刪掉 ⇒ 整頁封鎖
      showToast(t("product.variants.tooMany"));
      return;
    }
    if (!validate()) return;
    // 🔴 儲存期間不留著 modal：它會把 `#admin-root` 釘在 inert，之後任何 toast
    //   （成功、userErrors、重讀失敗）都對輔助科技靜默。與齒輪的 `disabled={saving}`
    //   合起來才是完整的——只擋入口擋不住「按下儲存時 modal 已經開著」那條路。
    setPublishingOpen(false);
    setSaving(true);
    try {
      // 🔴 B.4 規則 1：送**完整樹**（不是 dirty fields）。
      // 建立態顯式 DRAFT；編輯態帶 id＋lockVersion＋狀態卡的值。
      // handle：建立可手填；編輯不送（v1 handle 不可變，缺席＝保持現值）。
      const input: Record<string, unknown> = {
        title: values.title.trim(),
        descriptionHtml: descriptionToHtml(values.description),
        status: values.status,
        // 組織分類＋SEO 恆送（宣告式：空字串／空陣列＝清除，伺服端契約同語義）。
        vendor: values.vendor.trim(),
        productType: values.productType.trim(),
        tags: values.tags,
        seo: {
          title: values.seoTitle.trim(),
          description: values.seoDescription.trim(),
        },
        // 譯文恆送（宣告式）：空字串＝刪除該譯文列、回落來源語言（67 §C.4(b)）。
        // 🔴 來源語言那一格**不送**——它的內容在 base 欄位（title／descriptionHtml／seo）。
        translations: translationEntries(values.translations, sourceLocale),
        // 選項模式：options 樹＋逐列 variants（🔴 既有列必帶 id——改名選項時
        // 後端靠 id-match 保座標；回聲欄照送，宣告式缺席＝清除）。
        ...(values.options.length > 0
          ? { options: values.options.map((option) => ({ name: option.name.trim(), values: option.values })) }
          : {}),
        // 🔴 走共用的 payload builder（`lib/variantMatrix`）。變體子頁存檔時用的是
        //    同一支——兩個畫面各寫一份的話，其中一份遲早少送一個回聲欄，症狀是
        //    「在 A 頁存檔把 B 頁設好的值抹掉」，而兩邊各自的測試都會綠。
        variants: buildVariantsPayload(
          values.options.length > 0 ? values.variantRows : [ {
            id: null,
            coords: [],
            price: values.price,
            sku: values.sku,
            quantity: "",
            compare: values.compare,
            cost: values.cost,
            barcode: values.barcode,
            taxable: values.taxable,
            weightGrams: values.weightGrams,
            requiresShipping: values.requiresShipping,
          } ],
          values.options,
          (raw: string) => centsToApiString(parseMoneyToCents(raw) ?? null),
          isNew && locations[0] ? locations[0].id : undefined,
        ),
      };
      // 第 6 包：handle 兩態都送（同值＝伺服端 no-op；改值＝同 txn 寫 301；
      // 空字串＝presence nil＝保持現值，handle 本來就清不掉）。
      if (values.handle) input.handle = values.handle.trim();
      if (!isNew) {
        input.id = productGid;
        input.lockVersion = lockVersion;
      }

      const data = await requestAdminGraphQL<ProductSetData, Record<string, unknown>>(
        PRODUCT_SET_MUTATION,
        isNew ? { input, idempotencyKey: idempotencyKey.current } : { input },
      );

      const { product, userErrors } = data.productSet;
      if (userErrors.length > 0 || !product) {
        applyServerErrors(userErrors);
        return;
      }

      // 🔴 **`productSet` 一成功就立刻吸收新版本**，不等後面的媒體／發布兩支。
      //   `Catalog::SaveProduct` 每次更新都 bump `lock_version`；而後面兩支是**各自獨立的
      //   HTTP 往返**，任何一支拋例外都會直接跳到 catch ⇒ 舊寫法（在最後才 setLockVersion）
      //   會讓本地版本永遠停在舊值，使用者按重試時 `productSet` 帶著過期的 lockVersion
      //   ⇒ 回 `STALE_OBJECT`，**此後每一次儲存都是同樣的衝突**，連標題也存不回去，
      //   只有整頁重載才能脫困——而錯誤訊息（「資料已被他人修改」）會把人導向完全錯誤的診斷。
      //   ⚠️ 這裡吸收的是**版本**；快照（snapshot）仍必須等全部副作用落地後才提交，
      //   兩者不是同一件事：版本落後會鎖死，快照提前則會讓失敗的變更被當成已存。
      setLockVersion(product.lockVersion);

      // 媒體排序（第 27 包工作卡：排序隨商品儲存送出）。
      // 🔴 順序寫入是**獨立 mutation**——productSet 的宣告式全量語義不適用於媒體：
      //    媒體卡的上傳／刪除是即時動作，把媒體塞進 productSet 會讓「沒載入 media
      //    就存檔＝清空」的坑重演（同 collection productIds 的先例）。
      // 🔴 **必須在確認 productSet 成功之後才送**（審查 C9/C19）：原本擺在
      //    userErrors 檢查之前，商品儲存被伺服端拒絕時媒體順序照樣被永久改掉，
      //    而使用者看到的是「儲存失敗」。
      let mediaOrderApplied = false;
      if (!isNew && values.mediaOrder.length > 0) {
        const reordered = await requestAdminGraphQL<
          { productReorderMedia: { userErrors: { message: string }[] } },
          Record<string, unknown>
        >(REORDER_MEDIA_MUTATION, { productId: productGid, mediaIds: values.mediaOrder });
        const reorderErrors = reordered.productReorderMedia.userErrors;
        if (reorderErrors.length > 0) {
          // 🔴 失敗時清掉這份順序（審查 C13）：留著會讓之後每次儲存都重送同一份
          //    失敗清單（例如其中一張圖已被別的分頁刪掉，永遠對不上全量判準）。
          showToast(reorderErrors[0].message);
          setValue("mediaOrder", []);
          void reloadMedia();
        } else {
          mediaOrderApplied = true;
        }
      }

      // 🔴 發布變更（S6b）——**必須在 `productSet` 成功之後**（與 mediaOrder 的 C9/C19
      //    同構：擺在 userErrors 檢查之前的話，商品儲存被伺服端拒絕時發布照樣被永久改掉，
      //    而使用者看到的是「儲存失敗」）。
      // 🔴 **只在該部分 dirty 時才送**——本尊同形態（82 §13.2 結論 3：只改發布的那次
      //    沒有送 `ProductSaveUpdate`）。反過來也成立：沒改發布就不送這一支。
      let publicationsTouched = false;
      const pubDelta = values.publicationDelta;
      if (!isNew && (pubDelta.publish.length > 0 || pubDelta.unpublish.length > 0)) {
        publicationsTouched = true;
        const applied = await requestAdminGraphQL<PublishingMutationData, Record<string, unknown>>(
          PUBLISHING_MUTATION,
          {
            id: productGid,
            // 🔴 `publishDate` **只在有排程時才出現這個 key**——後端 R10 對「明確傳 null」
            //    一律 reject（官方對 null 完全沉默，不得自行定義成「取消排程」），
            //    省略才是「立即發布」。格式＝UTC 帶毫秒 `Z`（本尊抓包形態，82 §15.8）。
            publicationsToPublish: pubDelta.publish.map((entry) => (
              entry.at === null
                ? { publicationId: entry.publicationId }
                : { publicationId: entry.publicationId, publishDate: new Date(entry.at).toISOString() }
            )),
            publicationsToUnpublish: pubDelta.unpublish.map((id) => ({ publicationId: id })),
            shouldPublish: pubDelta.publish.length > 0,
            shouldUnpublish: pubDelta.unpublish.length > 0,
          },
        );
        // 🔴 兩支各自回 userErrors，**兩邊都要看**：只看 publish 的話，
        //    「取消發布被拒」會靜默成功，而卡片重讀後會顯示那個管道還在——
        //    使用者只會看到「存了但沒變」，沒有任何訊息。
        const pubErrors = [
          ...(applied.publishablePublish?.userErrors ?? []),
          ...(applied.publishableUnpublish?.userErrors ?? []),
        ];
        if (pubErrors.length > 0) showToast(pubErrors[0].message);
      }

      // 就地認 id（審查 C4）：本次新建的列在回應裡以座標對回 id——否則之後
      //    改名選項（改名＝後端刪＋加）時 id-less 列 digest 對不上、變體被換新。
      const savedNodes = product.variants?.nodes ?? [];
      const adoptedRows = values.variantRows.map((row) => {
        if (row.id) return row;
        const match = savedNodes.find((node) =>
          values.options.filter((option) => option.values.length > 0).every((option, index) =>
            (node.selectedOptions ?? []).find((so) => so.name === option.name.trim())?.value === row.coords[index]));
        return match ? { ...row, id: match.id } : row;
      });
      // 🔴 快照必須是「順序已落地＝mediaOrder 清空」的形狀（審查 C8/C20）：
      //    存進舊的非空 mediaOrder，之後 reloadMedia 把它清成 [] 就永遠不相等，
      //    頁面停在 dirty、SaveBar 不消失、離頁還會被攔。
      // 🔴 `publicationDelta` 一併歸零。**成敗都歸零**（mediaOrder 的 C13 同構）：
      //    留著的後果是**下次儲存重送同一份 delta**，且發布卡一直掛著「待儲存」badge。
      //    使用者看得到真實狀態——下面的 `reloadPublications` 會把伺服器現值拉回來，
      //    部分成功的那一半也會如實顯示。
      //    ⚠️ **這裡的失效形態與 mediaOrder 的 C8/C20 不同，不要照抄那句話**：
      //    mediaOrder 有 `reloadMedia` 會把 `values.mediaOrder` 清成 `[]`，而快照記著
      //    非空 ⇒ 兩者永遠不相等、SaveBar 不消失。delta **沒有**那個清空機制 ⇒ 漏掉歸零時
      //    快照與 values 雙雙停在非空、彼此相等，**SaveBar 照樣消失**，症狀只剩「重送」
      //    這一個且完全無聲。本包的 M5 突變就是在這裡發現我原本寫錯了機制。
      const savedValues = {
        ...values, variantRows: adoptedRows, mediaOrder: [], publicationDelta: EMPTY_DELTA,
      };
      snapshot.current = JSON.stringify(savedValues);
      showToast(t("product.saved"));
      if (isNew) {
        navigate("/admin/products");
      } else {
        // 編輯態留在頁上：認回 id，快照歸零 dirty（lockVersion 已在 productSet 成功當下吸收）。
        setValues(savedValues);
        if (mediaOrderApplied) void reloadMedia();
        // 🔴 成敗都重讀：部分成功（publish 過了、unpublish 被拒）時，只有伺服器知道
        //    真實組合。不重讀的話卡片會停在送出前的樂觀畫面。
        if (publicationsTouched) void reloadPublications();
      }
    } catch (reason: unknown) {
      // 鐵律 4 三層的另外兩層：top-level（THROTTLED／ACCESS_DENIED／
      // IDEMPOTENCY_KEY_REQUIRED）與非 200——都要有人話訊息，不得靜默空畫面。
      if (reason instanceof AdminGraphQLError) {
        showToast(reason.message);
      } else {
        showToast(reason instanceof Error ? reason.message : t("product.saveFailed"));
      }
    } finally {
      setSaving(false);
    }
  }, [applyServerErrors, isNew, locations, lockVersion, navigate, productGid, reloadMedia, reloadPublications, saving, showToast, t, validate, values, variantOverflow]);

  const applyDiscard = useCallback(() => {
    setValues(JSON.parse(snapshot.current) as FormValues);
    setErrors({});
    showToast(t("product.discarded"));
  }, [showToast, t]);

  // 捨棄走確認框（包 4）：還原快照不可復原，SaveBar 的捨棄鈕先問後做。
  const requestDiscard = useCallback(() => setConfirmAction("discard"), []);

  // 封存／取消封存：狀態寫入 state 後由本 effect 立即觸發儲存（91 §1 本尊為即時動作）。
  useEffect(() => {
    if (!pendingAutoSave.current) return;
    // 手動儲存進行中不消費 flag——save() 首行 `if (saving) return` 會靜默吞掉
    // 這次封存；等 saving 轉 false 本 effect 重跑再送。
    if (saving) return;
    pendingAutoSave.current = false;
    void save();
  }, [save, saving, values.status]);

  const applyStatusAction = useCallback(
    (status: string) => {
      pendingAutoSave.current = true;
      setActionsOpen(false);
      setValue("status", status);
    },
    [setValue],
  );

  // SaveBar 註冊（topbar 渲染；離頁清除）。
  useEffect(() => {
    registerSaveBar({ dirty, saving, onSave: () => void save(), onDiscard: requestDiscard, shakeSignal });
    return () => registerSaveBar(null);
  }, [dirty, registerSaveBar, requestDiscard, save, saving, shakeSignal]);

  // guardNav（原型 §4453：dirty 首次攔截 shake＋toast，4 秒內再點同意離開）。
  const blocker = useBlocker(dirty && !saving);
  const lastBlockAt = useRef(0);
  useEffect(() => {
    if (blocker.state !== "blocked") return;
    const now = Date.now();
    if (now - lastBlockAt.current < 4000) {
      blocker.proceed();
      return;
    }
    lastBlockAt.current = now;
    showToast(t("product.leaveWarning"));
    setShakeSignal((signal) => signal + 1);
    blocker.reset();
  }, [blocker, showToast, t]);

  const priceCents = parseMoneyToCents(values.price);
  const costCents = parseMoneyToCents(values.cost);
  const profit = profitState(
    typeof priceCents === "number" ? priceCents : null,
    typeof costCents === "number" ? costCents : null,
  );

  const bindField = (key: FieldKey) => (node: HTMLInputElement | null) => {
    fieldRefs.current[key] = node;
  };

  // 內容語言（ML-2）。來源語言那一格讀寫的是 base 欄位；其餘語言讀寫 values.translations。
  const sourceLocale = contentLocales.find((locale) => locale.isSource)?.tag ?? "en";
  const localeOptionsFor = (field: TranslatableField): LocaleOption[] =>
    contentLocales.map((locale) => ({
      tag: locale.tag,
      endonym: locale.endonym,
      outdated: outdatedFields[locale.tag]?.has(field) ?? false,
    }));

  const baseFieldFor: Record<TranslatableField, FieldKey | "description"> = {
    title: "title",
    body_html: "description",
    meta_title: "seoTitle",
    meta_description: "seoDescription",
  };

  /** 某語言某欄位的目前值（來源語言＝base 欄位，其餘＝譯文 map）。 */
  const localizedValues = (field: TranslatableField): Record<string, string> => {
    const map: Record<string, string> = {};
    for (const locale of contentLocales) {
      map[locale.tag] = locale.isSource
        ? String(values[baseFieldFor[field] as keyof FormValues] ?? "")
        : values.translations[locale.tag]?.[field] ?? "";
    }
    return map;
  };

  /** 寫回：來源語言寫 base 欄位；其餘寫譯文 map（保留其他語言與欄位）。 */
  const setLocalized = (field: TranslatableField, locale: string, next: string) => {
    if (locale === sourceLocale) {
      setValue(baseFieldFor[field] as keyof FormValues, next as never);
      return;
    }
    setValues((current) => ({
      ...current,
      translations: {
        ...current.translations,
        [locale]: { ...(current.translations[locale] ?? {}), [field]: next },
      },
    }));
  };

  if (loadState === "loading") {
    return (
      <div className="cl-page cl-page--detail cl-product-detail">
        <p className="cl-card-note">{t("product.loading")}</p>
      </div>
    );
  }

  if (loadState === "missing") {
    return (
      <div className="cl-page cl-page--detail cl-product-detail">
        <Card padded>
          <h3>{t("product.notFound.title")}</h3>
          <p className="cl-card-note">{t("product.notFound.body")}</p>
          <Button onClick={() => navigate("/admin/products")}>{t("product.notFound.back")}</Button>
        </Card>
      </div>
    );
  }

  const statusBadge = STATUS_PRESENTATION[values.status] ?? STATUS_PRESENTATION.DRAFT;
  // 🔴 **伺服器答案優先**（三層 AND 的前兩層），三種情形退回狀態層 fallback：
  //   ①建立態（伺服器上還不存在）②尚未載入 ③使用者剛改了狀態下拉還沒存
  //     （伺服器答的是**已儲存**的狀態，此時顯示它會與畫面上的下拉矛盾）。
  const statusDirty = values.status !== savedStatus;
  const serverDimensions = serverVisibility;
  const dimensions =
    serverDimensions && !statusDirty
      ? serverDimensions
      : (STATUS_DIMENSIONS[values.status] ?? STATUS_DIMENSIONS.DRAFT);

  // SERP 預覽（91 §11）：覆寫值優先，留空 fallback 商品標題／說明摘要。
  const serpHost = window.location.host;
  const serpTitle = values.seoTitle.trim() || values.title.trim();
  const serpDescription = (values.seoDescription.trim() || values.description.trim().replaceAll("\n", " "))
    .slice(0, SEO_DESCRIPTION_SERP);

  return (
    <div className="cl-page cl-page--detail cl-product-detail">
      <header className="cl-detail-head">
        <button
          aria-label={t("product.backToList")}
          className="cl-icon-button"
          onClick={() => navigate("/admin/products")}
          type="button"
        >
          <ArrowLeft aria-hidden="true" size={16} />
        </button>
        <h1 ref={headingRef} tabIndex={-1}>{isNew ? t("product.new") : values.title || t("product.untitled")}</h1>
        <Badge progress={statusBadge.progress} tone={statusBadge.tone}>
          {t(statusBadge.labelKey)}
        </Badge>
        {/* 內容語言 chip：建立一律在來源語言（67 §E.2）；編輯態的切換器屬多語言包 */}
        <span className="cl-locale-chip" title={t("product.contentLocale")}>
          {contentLocales.find((locale) => locale.isSource)?.endonym ?? sourceLocale}
        </span>
        <div className="cl-detail-head__actions">
          {isNew ? null : (
            <div className="cl-actionsmenu">
              <Button
                aria-expanded={actionsOpen}
                aria-haspopup="menu"
                onClick={() => setActionsOpen((state) => !state)}
                ref={actionsButtonRef}
              >
                {t("product.moreActions")} <MoreHorizontal aria-hidden="true" size={14} />
              </Button>
              {actionsOpen ? (
                <div className="cl-actionsmenu__list" role="menu">
                  <button className="cl-actionsmenu__item" disabled role="menuitem" title={t("product.duplicate.pending")} type="button">
                    {t("product.duplicate")}
                  </button>
                  {values.status === "ARCHIVED" ? (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => applyStatusAction("DRAFT")}
                      role="menuitem"
                      type="button"
                    >
                      {t("product.unarchive")}
                    </button>
                  ) : (
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => {
                        setActionsOpen(false);
                        setConfirmAction("archive");
                      }}
                      role="menuitem"
                      type="button"
                    >
                      {t("product.archive")}
                    </button>
                  )}
                  <button
                    className="cl-actionsmenu__item cl-actionsmenu__item--danger"
                    disabled
                    role="menuitem"
                    title={t("product.delete.pending")}
                    type="button"
                  >
                    {t("product.delete")}
                  </button>
                </div>
              ) : null}
            </div>
          )}
          <Button loading={saving} loadingLabel={t("common.saving")} onClick={() => void save()} variant="primary">
            {t("common.save")}
          </Button>
        </div>
      </header>

      <div className="cl-od-grid">
        <div className="cl-od-grid__main">
          <Card padded>
            <h3>{t("product.card.titleDescription")}</h3>
            {/* 標題＝堆疊式（67 §E.2-1：短單行欄位一次看完所有語言，才看得出譯錯語言／漏一語）。 */}
            <LocalizedField
              error={errors.title}
              hint={isNew ? t("product.field.title.hint") : t("product.contentLocale.hint")}
              label={t("product.field.title")}
              locales={localeOptionsFor("title")}
              maxLength={255}
              mode="stacked"
              onChange={(locale, next) => setLocalized("title", locale, next)}
              placeholder={t("product.field.title.placeholder")}
              sourceLocale={sourceLocale}
              sourceRef={bindField("title")}
              values={localizedValues("title")}
            />
            {/* 說明＝分頁式（長內容／富文本：N 個實例＝N 條工具列與載入成本，67 §E.2-1(b)）。 */}
            <LocalizedField
              label={t("product.field.description")}
              locales={localeOptionsFor("body_html")}
              mode="tabbed"
              onChange={(locale, next) => setLocalized("body_html", locale, next)}
              renderTabbed={(locale, value, onValueChange) => (
                <>
                  <div className="cl-rte-toolbar" title={t("product.rte.hint")}>
                    <button className="cl-rte-tool" disabled type="button">
                      <Sparkles aria-hidden="true" size={13} /> {t("product.rte.ai")}
                    </button>
                  </div>
                  <textarea
                    aria-label={`${t("product.field.description")}（${locale}）`}
                    className="cl-field__input cl-field__textarea"
                    id={locale === sourceLocale ? "product-description" : undefined}
                    lang={locale}
                    onChange={(event) => onValueChange(event.target.value)}
                    rows={4}
                    value={value}
                  />
                </>
              )}
              sourceLocale={sourceLocale}
              values={localizedValues("body_html")}
            />
          </Card>

          <Card padded>
            <h3>{t("product.card.media")}</h3>
            <MediaCard
              maxMedia={MAX_PRODUCT_MEDIA}
              media={orderedMedia}
              onRefresh={() => void reloadMedia()}
              onReorder={(mediaIds) => setValue("mediaOrder", mediaIds)}
              productGid={productGid}
            />
          </Card>

          <Card padded>
            <h3>{t("product.card.category")}</h3>
            <TextField
              disabled
              hint={t("product.category.hint")}
              label={t("product.category.label")}
              placeholder={t("product.category.placeholder")}
              value=""
            />
            <div className="cl-derow">
              <div className="cl-de">
                {t("product.category.taxRule")} <b className="cl-de--unknown">--</b>
              </div>
              <div className="cl-de">
                {t("product.category.metafields")} <b className="cl-de--unknown">--</b>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.pricing")}</h3>
            {values.options.length > 0 ? (
              // 選項模式：金額落在變體表逐列（Shopify 同型——有變體即無商品級價格）
              <p className="cl-card-note">{t("product.pricing.perVariant")}</p>
            ) : (
            <>
            <TextField
              error={errors.price}
              inputMode="decimal"
              label={t("product.price.label")}
              onChange={(event) => setValue("price", event.target.value)}
              placeholder="0.00"
              ref={bindField("price")}
              value={values.price}
            />
            <div className="cl-pillset">
              <PillGroup
                onToggle={togglePill}
                open={openPills}
                pills={[
                  { key: "compare", label: t("product.pill.compare"), value: values.compare || undefined },
                  { key: "unit", label: t("product.pill.unit") },
                  { key: "tax", label: t("product.pill.tax"), value: values.taxable ? t("common.yes") : t("common.no") },
                  { key: "cost", label: t("product.pill.cost"), value: values.cost || undefined },
                ]}
              />
              {openPills.has("compare") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.compare}
                    hint={t("product.compare.hint")}
                    inputMode="decimal"
                    label={t("product.compare.label")}
                    onChange={(event) => setValue("compare", event.target.value)}
                    placeholder={t("product.compare.placeholder")}
                    ref={bindField("compare")}
                    value={values.compare}
                  />
                </div>
              ) : null}
              {openPills.has("unit") ? (
                <div className="cl-pillpanel">
                  <div className="cl-field">
                    <label className="cl-field__label" htmlFor="unit-pricing">
                      {t("product.unit.label")}
                    </label>
                    <select className="cl-field__input" disabled id="unit-pricing">
                      <option>{t("product.unit.off")}</option>
                      <option>{t("product.unit.per100ml")}</option>
                      <option>{t("product.unit.per100g")}</option>
                      <option>{t("product.unit.per1kg")}</option>
                      <option>{t("product.unit.per1m")}</option>
                    </select>
                  </div>
                </div>
              ) : null}
              {openPills.has("tax") ? (
                <div className="cl-pillpanel">
                  <label className="cl-checkrow">
                    <input
                      checked={values.taxable}
                      onChange={(event) => setValue("taxable", event.target.checked)}
                      type="checkbox"
                    />
                    {t("product.tax.checkbox")}
                  </label>
                </div>
              ) : null}
              {openPills.has("cost") ? (
                <div className="cl-pillpanel">
                  <TextField
                    error={errors.cost}
                    hint={t("product.cost.hint")}
                    inputMode="decimal"
                    label={t("product.cost.label")}
                    onChange={(event) => setValue("cost", event.target.value)}
                    placeholder="0.00"
                    ref={bindField("cost")}
                    value={values.cost}
                  />
                  <div className="cl-derow">
                    <div className="cl-de">
                      {t("product.profit")}{" "}
                      {profit.profit === null ? (
                        <b className="cl-de--unknown">--</b>
                      ) : (
                        <b className="cl-num">{centsToApiString(profit.profit)}</b>
                      )}
                    </div>
                    <div className="cl-de">
                      {t("product.margin")}{" "}
                      {profit.margin === null ? (
                        <b className="cl-de--unknown">--</b>
                      ) : (
                        <b className="cl-num">{profit.margin}%</b>
                      )}
                    </div>
                  </div>
                </div>
              ) : null}
            </div>
            </>
            )}
          </Card>

          <Card padded>
            <h3>{t("product.card.inventory")}</h3>
            <SwitchRow checked disabled hint={t("product.inventory.tracked.hint")} label={t("product.inventory.tracked")} />
            {isNew ? (
              // 建立態：變體與 inventory_item 還不存在（callback 在 create 之後才跑），
              // 所以只留欄位形狀。初始數量走 productSet 的 initialQuantities＝第 22 包。
              <div className="cl-grid2">
                <TextField disabled hint={t("product.inventory.quantity.hint")} label={t("product.inventory.quantity")} value="0" />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="inventory-location">
                    {t("product.inventory.location")}
                  </label>
                  <select className="cl-field__input" disabled id="inventory-location">
                    <option>Shop location</option>
                  </select>
                </div>
              </div>
            ) : (
              // 編輯態：真實數量＋行內調整（第 18 包 B 塊；卡內自己的儲存鈕，
              // 不掛頁面 SaveBar——理由見 InventoryCard 檔頭③）。
              <InventoryCard productId={productGid ?? ""} />
            )}
            {values.options.length > 0 ? (
              <p className="cl-card-note">{t("product.inventory.perVariant")}</p>
            ) : (
            <div className="cl-pillset">
              <PillGroup
                onToggle={togglePill}
                open={openPills}
                pills={[
                  { key: "sku", label: t("product.pill.sku"), value: values.sku || undefined },
                  { key: "barcode", label: t("product.pill.barcode"), value: values.barcode || undefined },
                  { key: "continue", label: t("product.pill.continue") },
                ]}
              />
              {openPills.has("sku") ? (
                <div className="cl-pillpanel">
                  <TextField
                    hint={t("product.sku.hint")}
                    label={t("product.sku.label")}
                    maxLength={64}
                    onChange={(event) => setValue("sku", event.target.value)}
                    value={values.sku}
                  />
                </div>
              ) : null}
              {openPills.has("barcode") ? (
                <div className="cl-pillpanel">
                  <TextField
                    label={t("product.barcode.label")}
                    onChange={(event) => setValue("barcode", event.target.value)}
                    value={values.barcode}
                  />
                </div>
              ) : null}
              {openPills.has("continue") ? (
                <div className="cl-pillpanel">
                  <label className="cl-checkrow">
                    <input disabled type="checkbox" />
                    {t("product.continue.checkbox")}
                  </label>
                </div>
              ) : null}
            </div>
            )}
          </Card>

          <Card padded>
            <h3>{t("product.card.shipping")}</h3>
            <label className="cl-checkrow">
              <input defaultChecked disabled type="checkbox" />
              {t("product.shipping.physical")}
            </label>
            <div className="cl-grid2">
              <TextField disabled label={t("product.shipping.weight")} placeholder="0.00" value="" />
              <div className="cl-field">
                <label className="cl-field__label" htmlFor="shipping-package">
                  {t("product.shipping.package")}
                </label>
                <select className="cl-field__input" disabled id="shipping-package">
                  <option>{t("product.shipping.packageDefault")}</option>
                </select>
              </div>
            </div>
          </Card>

          <Card padded>
            <h3>{t("product.card.variants")}</h3>
            {variantOverflow ? (
              <p className="cl-card-note cl-card-note--warn">{t("product.variants.tooMany")}</p>
            ) : null}
            <fieldset className="cl-fieldset-plain" disabled={saving || variantOverflow}>
            {values.options.map((option, optionIndex) => (
              <div className="cl-option-row" key={optionIndex}>
                <div className="cl-option-row__head">
                  <TextField
                    label={t("product.options.name")}
                    onChange={(event) => renameOption(optionIndex, event.target.value)}
                    placeholder={t("product.options.name.placeholder")}
                    value={option.name}
                  />
                  <Button
                    aria-label={t("product.options.remove", { name: option.name || t("product.options.name") })}
                    onClick={() => applyOptionsChange(values.options.filter((_, i) => i !== optionIndex))}
                    size="small"
                  >
                    {t("common.remove")}
                  </Button>
                </div>
                <TagsField
                  label={t("product.options.values")}
                  onChange={(nextValues) =>
                    applyOptionsChange(values.options.map((existing, i) =>
                      (i === optionIndex ? { ...existing, values: nextValues } : existing)))}
                  placeholder={t("product.options.values.placeholder")}
                  removeLabel={(value) => t("product.options.values.remove", { value })}
                  suggestions={[]}
                  tags={option.values}
                />
              </div>
            ))}
            {values.options.length < MAX_PRODUCT_OPTIONS ? (
              <div className="cl-actionsmenu">
                <Button
                  aria-expanded={optionMenuOpen}
                  aria-haspopup="menu"
                  onClick={() => setOptionMenuOpen((state) => !state)}
                  size="small"
                >
                  {t("product.options.add")}
                </Button>
                {optionMenuOpen ? (
                  <div className="cl-actionsmenu__list" role="menu">
                    {SUGGESTED_OPTION_KEYS.map((suggestedKey) => {
                      const name = t(suggestedKey);
                      const used = values.options.some((option) => option.name.trim() === name);
                      return (
                        <button
                          className="cl-actionsmenu__item"
                          disabled={used}
                          key={suggestedKey}
                          onClick={() => {
                            setOptionMenuOpen(false);
                            applyOptionsChange([ ...values.options, { key: uuidV4(), name, values: [] } ]);
                          }}
                          role="menuitem"
                          type="button"
                        >
                          {name}
                        </button>
                      );
                    })}
                    <button
                      className="cl-actionsmenu__item"
                      onClick={() => {
                        setOptionMenuOpen(false);
                        applyOptionsChange([ ...values.options, { key: uuidV4(), name: "", values: [] } ]);
                      }}
                      role="menuitem"
                      type="button"
                    >
                      {t("product.options.custom")}
                    </button>
                  </div>
                ) : null}
              </div>
            ) : null}
            {values.options.length === 0 ? (
              <p className="cl-card-note">{t("product.variants.note")}</p>
            ) : null}
            {values.variantRows.length > 0 ? (
              <div className="cl-variant-table-wrap">
                <table
                  aria-label={t("product.variants.table.caption", { count: values.variantRows.length })}
                  className="cl-variant-table"
                >
                  <thead>
                    <tr>
                      <th scope="col">{t("product.variants.table.variant")}</th>
                      <th scope="col">{t("product.variants.table.price")}</th>
                      <th scope="col">{t("product.variants.table.sku")}</th>
                      {isNew && locations[0] ? (
                        <th scope="col">{t("product.variants.table.quantity", { location: locations[0].name })}</th>
                      ) : null}
                    </tr>
                  </thead>
                  <tbody>
                    {values.variantRows.map((variantRow, rowIndex) => {
                      const variantTitle = variantRow.coords.join(" / ");
                      const priceClass = rowErrors[rowIndex]
                        ? "cl-field__input cl-variant-table__input cl-field__input--error"
                        : "cl-field__input cl-variant-table__input";
                      return (
                        <tr key={variantRow.coords.join("|")}>
                          <th scope="row">
                            {/* 🔴 只有**已存在**的變體才給連結（第 29 包）：新列還沒有
                                GID，點進去沒有東西可載。建立態整張表都沒有連結。 */}
                            {variantRow.id && !isNew ? (
                              <Link
                                to={`/admin/products/${encodeURIComponent(productGid ?? "")}` +
                                    `/variants/${encodeURIComponent(variantRow.id)}`}
                              >
                                {variantTitle}
                              </Link>
                            ) : variantTitle}
                          </th>
                          <td>
                            <input
                              aria-invalid={rowErrors[rowIndex] ? true : undefined}
                              aria-label={t("product.variants.table.priceFor", { variant: variantTitle })}
                              className={priceClass}
                              inputMode="decimal"
                              onChange={(event) => setRowField(rowIndex, "price", event.target.value)}
                              ref={(node) => {
                                rowPriceRefs.current[rowIndex] = node;
                              }}
                              value={variantRow.price}
                            />
                            {rowErrors[rowIndex] ? (
                              <p className="cl-field__error">{rowErrors[rowIndex]}</p>
                            ) : null}
                          </td>
                          <td>
                            <input
                              aria-label={t("product.variants.table.skuFor", { variant: variantTitle })}
                              className="cl-field__input cl-variant-table__input"
                              onChange={(event) => setRowField(rowIndex, "sku", event.target.value)}
                              value={variantRow.sku}
                            />
                          </td>
                          {isNew && locations[0] ? (
                            <td>
                              <input
                                aria-label={t("product.variants.table.quantityFor", { variant: variantTitle })}
                                className="cl-field__input cl-variant-table__input"
                                inputMode="numeric"
                                onChange={(event) => setRowField(rowIndex, "quantity", event.target.value)}
                                value={variantRow.quantity}
                              />
                            </td>
                          ) : null}
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            ) : null}
            </fieldset>
          </Card>

          <Card padded>
            <h3>{t("product.card.purchaseOptions")}</h3>
            <div className="cl-detail-head__actions cl-purchase-options">
              {[
                t("product.purchase.subscription"),
                t("product.purchase.preorder"),
                t("product.purchase.tryBeforeBuy"),
              ].map((label) => (
                <Button key={label} onClick={() => showToast(t("common.comingSoon", { label }))} size="small">
                  {label}
                </Button>
              ))}
            </div>
          </Card>

          <Card padded>
            <h3>
              {t("product.card.seo")}
              <span className="cl-card__head-action">
                <button
                  aria-expanded={seoOpen}
                  aria-label={t("product.seo.edit")}
                  className="cl-icon-button"
                  onClick={() => setSeoOpen((state) => !state)}
                  type="button"
                >
                  <Pencil aria-hidden="true" size={14} />
                </button>
              </span>
            </h3>
            {/* SERP 預覽（91 §11 收合態）：站名 → 麵包屑 URL → 標題連結 → 描述 → 價格列。 */}
            {serpTitle ? (
              <div className="cl-serp">
                <div className="cl-serp__site">CHILL LOVE</div>
                <div className="cl-serp__url">
                  {serpHost} › products › {values.handle || "…"}
                </div>
                <div className="cl-serp__title">{serpTitle}</div>
                {serpDescription ? <div className="cl-serp__desc">{serpDescription}</div> : null}
                {values.price.trim() ? (
                  <div className="cl-serp__price">HK${values.price.trim()} HKD</div>
                ) : null}
              </div>
            ) : (
              <p className="cl-card-note">{t("product.seo.empty")}</p>
            )}
            {seoOpen ? (
              <>
                {/* SEO 標題＋描述＝分頁式整組（判準不是「長」，是「一組要一起讀才判斷得出來」）。 */}
                <LocalizedField
                  error={errors.seoTitle}
                  hint={t("product.seo.pageTitle.hint", { used: values.seoTitle.length, max: SEO_TITLE_MAX })}
                  label={t("product.seo.pageTitle")}
                  locales={localeOptionsFor("meta_title")}
                  maxLength={SEO_TITLE_MAX}
                  mode="tabbed"
                  onChange={(locale, next) => setLocalized("meta_title", locale, next)}
                  sourceLocale={sourceLocale}
                  sourceRef={bindField("seoTitle")}
                  values={localizedValues("meta_title")}
                />
                <div className="cl-field">
                  <label className="cl-field__label" htmlFor="seo-description">
                    {t("product.seo.meta")}
                  </label>
                  <LocalizedField
                    label={t("product.seo.meta")}
                    locales={localeOptionsFor("meta_description")}
                    mode="tabbed"
                    onChange={(locale, next) => setLocalized("meta_description", locale, next)}
                    renderTabbed={(locale, value, onValueChange) => (
                      <textarea
                        aria-invalid={locale === sourceLocale && errors.seoDescription ? true : undefined}
                        aria-label={`${t("product.seo.meta")}（${locale}）`}
                        className="cl-field__input cl-field__textarea"
                        id={locale === sourceLocale ? "seo-description" : undefined}
                        lang={locale}
                        maxLength={SEO_DESCRIPTION_MAX}
                        onChange={(event) => onValueChange(event.target.value)}
                        rows={3}
                        value={value}
                      />
                    )}
                    sourceLocale={sourceLocale}
                    values={localizedValues("meta_description")}
                  />
                  {/* 160 是 SERP 建議值不是上限（91 §11：本尊 203/160 照樣可存；硬上限 320）。 */}
                  {errors.seoDescription ? (
                    <p className="cl-field__error">{errors.seoDescription}</p>
                  ) : (
                    <p className="cl-field__hint">
                      {t("product.seo.meta.hint", {
                        used: values.seoDescription.length,
                        serp: SEO_DESCRIPTION_SERP,
                        max: SEO_DESCRIPTION_MAX,
                      })}
                    </p>
                  )}
                </div>
                <TextField
                  error={errors.handle}
                  hint={isNew ? t("product.seo.handle.hintNew") : t("product.seo.handle.hintEdit")}
                  label={t("product.seo.handle")}
                  onChange={(event) => setValue("handle", event.target.value)}
                  placeholder={t("product.seo.handle.placeholder")}
                  ref={bindField("handle")}
                  value={values.handle}
                />
              </>
            ) : null}
          </Card>
        </div>

        <div className="cl-od-grid__aside">
          {isNew ? null : (
            <Card padded>
              <h3>{t("product.card.status")}</h3>
              <div className="cl-field">
                <span className="cl-field__label" id="product-status-label">
                  {t("product.status.label")}
                </span>
                {/* 91 §2：listbox 每項帶描述副行；封存不在清單（走更多動作）。 */}
                <StatusListbox
                  labelId="product-status-label"
                  onChange={(next) => setValue("status", next)}
                  value={values.status}
                />
              </div>
              {/* 兩維讀值（13 §F1.2）：是/否文字本身承載語意，顏色只加速掃視 */}
              <div className="cl-derow">
                <div className="cl-de">
                  {t("product.status.purchasable")} <b className={dimensions.purchasable ? "" : "cl-de--unknown"}>{dimensions.purchasable ? t("common.yes") : t("common.no")}</b>
                </div>
                <div className="cl-de">
                  {t("product.status.discoverable")} <b className={dimensions.discoverable ? "" : "cl-de--unknown"}>{dimensions.discoverable ? t("common.yes") : t("common.no")}</b>
                </div>
              </div>
            </Card>
          )}
          <Card padded>
            {/* 齒輪開發布編輯 modal（本尊觸發步驟逐字：商品詳情頁 → Publishing 卡
                → **右上角的設定圖示**，82 §12.1）。形態沿用 SEO 卡的標題列 icon 鈕。 */}
            <h3>
              {t("product.card.publishing")}
              {/* 🔴 排程 badge（本尊 §15.9）：日曆-時鐘 icon ＋**有排程的管道數**。
                  數字要把待送的排程也算進去——商家剛設好按了 Done，badge 必須立刻出現，
                  否則看起來像沒生效。本尊同樣是存檔前就顯示（樂觀更新，§13.1）。 */}
              {scheduledCount > 0 ? (
                <span className="cl-card__head-badge">
                  <Badge tone="attention">
                    <CalendarClock aria-hidden="true" size={11} />
                    {scheduledCount}
                  </Badge>
                </span>
              ) : null}
              {/* 🔴 建立態不給齒輪：商品尚未存在 ⇒ 沒有可傳給 publishablePublish 的 GID，
                  且該態下管道清單根本沒查（PRODUCT_QUERY 只在編輯態跑）。 */}
              {isNew ? null : (
                <span className="cl-card__head-action">
                  {/* 🔴 兩個 disabled 條件，各自擋一個真實事故：
                      ①`saving`——儲存進行中若讓使用者重開 modal，之後射出的錯誤 toast
                        會落在被 `inert` 的 `#admin-root` 內（Modal 開啟時 `lockBackground`
                        對它加 inert），WHATWG 逐字 "user agents do not expose the inert
                        nodes to accessibility APIs or assistive technologies"
                        ⇒ 訊息對輔助科技**完全靜默**，而明眼人看得到（toast 的 z 比 dialog 高）。
                        `Modal.tsx` 檔頭的「modal 開著時的訊息要進 modal 本體」就是這條。
                      ②`variantOverflow`——`save()` 在變體超過 250 時**整頁封鎖、一個請求都不送**
                        （審查 C0 的既有裁定）。不擋的話使用者可以撥、可以按完成、卡片會掛
                        「待儲存」badge、SaveBar 會亮，但按儲存只得到一句與發布無關的
                        「變體太多」，且該商品的發布狀態從此改不了。⇒ 寧可讓入口本身說不行。 */}
                  <button
                    aria-haspopup="dialog"
                    aria-label={t("product.publishing.manage")}
                    className="cl-icon-button"
                    disabled={saving || variantOverflow}
                    onClick={() => { setPublishingOpenedAt(Date.now()); setPublishingOpen(true); }}
                    ref={publishingButtonRef}
                    title={variantOverflow ? t("product.publishing.blockedByVariants") : undefined}
                    type="button"
                  >
                    <Settings aria-hidden="true" size={14} />
                  </button>
                </span>
              )}
            </h3>
            <PublishingCard
              delta={values.publicationDelta}
              publications={publications}
              rows={publicationRows}
              stale={publicationsStale}
              t={t}
            />
          </Card>
          {/* 組織分類卡（91 §12：類型 search-or-create、廠商 autocomplete、標籤 token、佈景範本）。 */}
          <Card padded>
            <h3>{t("product.card.organization")}</h3>
            <TextField
              error={errors.productType}
              label={t("product.org.type")}
              list="product-type-suggestions"
              maxLength={255}
              onChange={(event) => setValue("productType", event.target.value)}
              placeholder={t("product.org.type.placeholder")}
              ref={bindField("productType")}
              value={values.productType}
            />
            <datalist id="product-type-suggestions">
              {suggestions.productTypes.map((type) => (
                <option key={type} value={type} />
              ))}
            </datalist>
            <TextField
              error={errors.vendor}
              label={t("product.org.vendor")}
              list="product-vendor-suggestions"
              maxLength={255}
              onChange={(event) => setValue("vendor", event.target.value)}
              ref={bindField("vendor")}
              value={values.vendor}
            />
            <datalist id="product-vendor-suggestions">
              {suggestions.productVendors.map((vendor) => (
                <option key={vendor} value={vendor} />
              ))}
            </datalist>
            <TagsField
              onChange={(tags) => setValue("tags", tags)}
              suggestions={[]}
              tags={values.tags}
            />
            <div className="cl-field">
              <label className="cl-field__label" htmlFor="theme-template">
                {t("product.org.template")}
              </label>
              <select className="cl-field__input" disabled id="theme-template">
                <option>{t("product.org.template.default")}</option>
              </select>
            </div>
          </Card>
        </div>
      </div>

      {/* 破壞性動作確認框（包 4）。封存確認後沿既有 applyStatusAction 通道自動儲存。 */}
      {/* 🔴 條件渲染而非傳 `open`：modal 內的草稿是 local state，
          每次開啟都要是 `values.publicationDelta` 的新鮮初值。Modal 原語的焦點還原
          寫在 `useEffect` 的 cleanup ⇒ unmount 同樣會跑，不因此失效。 */}
      {publishingOpen ? (
        <PublishingModal
          delta={values.publicationDelta}
          now={publishingOpenedAt}
          shopTimezone={shopTimezone}
          onApply={(next) => {
            setValue("publicationDelta", next);
            setPublishingOpen(false);
          }}
          onClose={() => setPublishingOpen(false)}
          productTitle={values.title}
          publications={publications}
          restoreFocusTo={publishingButtonRef}
          rows={publicationRows}
          t={t}
        />
      ) : null}
      <ConfirmDialog
        confirmLabel={t("confirm.discard.action")}
        danger
        message={t("confirm.discard.body")}
        onCancel={() => setConfirmAction(null)}
        onConfirm={() => {
          setConfirmAction(null);
          applyDiscard();
        }}
        open={confirmAction === "discard"}
        restoreFocusTo={headingRef}
        title={t("confirm.discard.title")}
      />
      <ConfirmDialog
        confirmLabel={t("confirm.archive.action")}
        message={t("confirm.archive.body")}
        onCancel={() => setConfirmAction(null)}
        onConfirm={() => {
          setConfirmAction(null);
          applyStatusAction("ARCHIVED");
        }}
        open={confirmAction === "archive"}
        restoreFocusTo={actionsButtonRef}
        title={t("confirm.archive.title")}
      />
    </div>
  );
}
