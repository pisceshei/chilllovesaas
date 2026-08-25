import { RefreshCw } from "lucide-react";
import { Button } from "./Button";
import { useT } from "../i18n/I18nContext";

/**
 * 列表底部的「載入更多」（D48「所有的都跟 Shopify」：本尊列表可翻頁，
 * 我方原本三個列表頁都只取第一頁）。
 *
 * 🔴 **沒有下一頁時整個不渲染**——不是渲染一顆 disabled 按鈕。
 *   disabled 的「載入更多」在只有一頁的店裡會永遠掛在畫面底部，
 *   讀起來像「還有東西但你不能看」。
 * 🔴 載入更多**失敗不清畫面**：錯誤訊息顯示在按鈕旁，已載入的列留著
 *   （呼叫端的 `loadMoreError` 與 `error` 是兩個狀態，就是為了這件事）。
 */
export interface LoadMoreProps {
  hasNextPage: boolean;
  loading: boolean;
  error: string | null;
  onLoadMore: () => void;
}

export function LoadMore({ hasNextPage, loading, error, onLoadMore }: LoadMoreProps) {
  const t = useT();
  if (!hasNextPage) return null;

  return (
    <div className="cl-load-more">
      {error ? <p className="cl-load-more__error" role="alert">{error}</p> : null}
      <Button disabled={loading} onClick={onLoadMore} variant="secondary">
        {loading ? <RefreshCw aria-hidden="true" className="cl-spin" size={14} /> : null}
        {loading ? t("common.loading") : t("common.loadMore")}
      </Button>
    </div>
  );
}
