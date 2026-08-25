import { useCallback, useEffect, useRef, useState } from "react";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";

/**
 * cursor 分頁的共用 hook（D48「所有的都跟 Shopify」：本尊列表可翻頁，我方原本
 * 三個列表頁都只取第一頁）。
 *
 * ①這是什麼：把「載第一頁 → 使用者按載入更多 → 接在後面」這條線收成一支。
 *   `ProductsPage`／`CollectionsPage`／`FilesPage` 三個消費者共用。
 * ②🔴 **篩選條件改變 ⇒ 回到第一頁並丟棄已累積的**：這不是可有可無的細節。
 *   不重置的話，切了狀態篩選之後畫面上會是「舊條件的 50 筆 ＋ 新條件的 50 筆」，
 *   而且捲到底再按載入更多會用**舊 cursor** 去要新條件的下一頁——keyset 的
 *   cursor 綁定排序位置，換了 WHERE 條件就沒有意義。
 * ③🔴 **世代計數器擋過期回應**：使用者在 loadMore 還在飛的時候改了篩選，
 *   那個舊請求回來時**不得**把資料接上去。AbortController 只擋得住還沒回的請求，
 *   擋不住「已經回來但 setState 還沒跑」的競態——所以另外用一個遞增的 generation
 *   比對，不是本世代的回應一律丟掉。
 * ④跨功能影響：伺服端一律回 `{ nodes, pageInfo { hasNextPage, endCursor } }`
 *   （`Products::KeysetConnection` 的形狀，products／collections／files／variants 共用）。
 *   新的列表頁接這支之前，先確認它的 query 有選 `pageInfo`。
 */

/** 伺服端 connection 的 pageInfo（keyset 契約，見 docs/research/28 §0.3）。 */
export interface PageInfo {
  hasNextPage: boolean;
  endCursor: string | null;
}

/** 一頁的回傳。 */
export interface Page<T> {
  nodes: T[];
  pageInfo: PageInfo;
}

export interface CursorPagination<T> {
  /** 累積到目前為止的列；`null`＝第一頁還在載入（骨架態）。 */
  items: T[] | null;
  /** 第一頁失敗的訊息；載入更多失敗走 `loadMoreError`（不清掉已顯示的資料）。 */
  error: string | null;
  /** 載入更多失敗的訊息。 */
  loadMoreError: string | null;
  hasNextPage: boolean;
  loadingMore: boolean;
  loadMore: () => void;
  /** 重新載入第一頁（retry 與寫入後重讀共用）。 */
  reload: () => void;
}

/**
 * @param fetchPage - 取一頁；`cursor` 為 `null` 代表第一頁。
 * @param deps - 篩選條件。**變動即重置**（見檔頭②）。
 * @param fallbackMessage - 非 Error 例外時的顯示文案。
 */
export function useCursorPagination<T>(
  fetchPage: (cursor: string | null, signal: AbortSignal) => Promise<Page<T>>,
  deps: readonly unknown[],
  fallbackMessage: string,
): CursorPagination<T> {
  const [items, setItems] = useState<T[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loadMoreError, setLoadMoreError] = useState<string | null>(null);
  const [pageInfo, setPageInfo] = useState<PageInfo>({ hasNextPage: false, endCursor: null });
  const [loadingMore, setLoadingMore] = useState(false);
  const [requestKey, setRequestKey] = useState(0);

  // 🔴 世代計數器（見檔頭③）。ref 而非 state：它要在 async callback 裡被讀到
  //    「現在最新的值」，state 的閉包會抓到當時那一份。
  const generation = useRef(0);
  const fetchRef = useRef(fetchPage);
  fetchRef.current = fetchPage;
  // 🔴 `fallbackMessage` 是**顯示文案**不是查詢條件。放進 effect 依賴的話，
  //    使用者切換後台介面語言就會讓已經「載入更多」出來的幾百列全部消失、退回第一頁。
  const fallbackRef = useRef(fallbackMessage);
  fallbackRef.current = fallbackMessage;
  // 🔴 loadMore 自己的 controller：第一頁 effect 的 cleanup 只 abort 得到它自己那個，
  //    loadMore 的請求會在元件 unmount 之後繼續跑到完成（伺服端照樣做完那次掃描）。
  const loadMoreController = useRef<AbortController | null>(null);

  // 卸載時把還在飛的 loadMore 一起收掉。
  useEffect(() => () => loadMoreController.current?.abort(), []);

  // 第一頁：deps 或 requestKey 變動時重跑，並丟棄累積結果。
  useEffect(() => {
    const controller = new AbortController();
    generation.current += 1;
    const mine = generation.current;

    setItems(null);
    setError(null);
    setLoadMoreError(null);
    // 🔴 條件變更時也要把 loadingMore 歸零：舊世代的 loadMore 還在飛，
    //    它的 finally 會因為世代不符而不清這個旗標（見 loadMore 的註釋）。
    setLoadingMore(false);
    setPageInfo({ hasNextPage: false, endCursor: null });

    fetchRef.current(null, controller.signal)
      .then((page) => {
        if (mine !== generation.current) return;

        setItems(page.nodes);
        setPageInfo(page.pageInfo);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted || mine !== generation.current) return;
        setError(reason instanceof Error ? reason.message : fallbackRef.current);
      });
    return () => controller.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps -- deps 由呼叫端定義（篩選條件）
  }, [requestKey, ...deps]);

  const loadMore = useCallback(() => {
    if (loadingMore || !pageInfo.hasNextPage) return;

    const controller = new AbortController();
    loadMoreController.current = controller;
    const mine = generation.current;
    setLoadingMore(true);
    setLoadMoreError(null);

    fetchRef.current(pageInfo.endCursor, controller.signal)
      .then((page) => {
        // 🔴 世代不符＝這期間篩選條件變了，這一頁屬於舊條件，丟掉。
        if (mine !== generation.current) return;

        setItems((current) => [ ...(current ?? []), ...page.nodes ]);
        setPageInfo(page.pageInfo);
      })
      .catch((reason: unknown) => {
        if (controller.signal.aborted || mine !== generation.current) return;
        // 🔴 載入更多失敗**不清掉已顯示的資料**：使用者已經看到的 50 筆不該消失。
        setLoadMoreError(reason instanceof Error ? reason.message : fallbackRef.current);
      })
      .finally(() => {
        // 🔴 **要世代守衛**：沒有的話，過期世代那筆（它的 controller 沒人 abort，
        //    一定會跑完）回來時會清掉**現行世代**的 in-flight 旗標 ⇒ 防重入失效 ⇒
        //    同一個 endCursor 被送兩次 ⇒ 同一頁被 append 兩次。
        // 🔴 而「守衛會不會讓旗標卡在 true」由**第一頁 effect 一併重置**解決（見上），
        //    不是靠這裡無條件清。兩件事各有各的機制，合成一個就會壞掉一邊——
        //    本輪先寫成無條件清（修好卡住），對抗審查抓到它製造了重複 append。
        if (mine === generation.current) setLoadingMore(false);
      });
  }, [loadingMore, pageInfo.endCursor, pageInfo.hasNextPage]);

  const reload = useCallback(() => setRequestKey((key) => key + 1), []);

  return {
    items,
    error,
    loadMoreError,
    hasNextPage: pageInfo.hasNextPage,
    loadingMore,
    loadMore,
    reload,
  };
}

export { DEFAULT_PAGE_SIZE };
