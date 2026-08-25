import { useT } from "../i18n/I18nContext";

/**
 * 媒體縮圖的**呈現層**（第 29 包抽出共用）。
 *
 * ①這是什麼：一格方形縮圖——ready 且有衍生尺寸就顯示圖，否則顯示狀態占位。
 * ②🔴 **只抽呈現、不抽行為**（整合規格 §1.1「複用不改語義」）：媒體卡的 tile 可拖曳
 *   重排、有精選標記、有 alt 就地編輯；變體圖只有一格（`max_images_per_variant`＝1）、
 *   不排序也沒有精選概念。把整個 tile 搬過去等於把拖曳語義帶進一個不能拖的地方。
 *   兩邊真正共用的只有「這張圖現在該顯示什麼」這件事。
 * ③🔴 **處理中不拿原圖冒充縮圖**：20MB 原圖當縮圖會炸列表（第 26 包既有紀律）。
 * ④跨功能影響：`MediaCard`（商品媒體格）與 `VariantImageSlot`（變體圖）共用。
 *   改這裡兩邊都會變——這正是抽它的目的，但也代表改之前要兩邊都看。
 */
export interface MediaThumbProps {
  /** 衍生縮圖 URL；null＝尚未產出。 */
  thumbUrl: string | null;
  /** 四態之一。 */
  status: "UPLOADED" | "PROCESSING" | "READY" | "FAILED" | string;
  /** 圖片替代文字（D48：檔案層、全店一份）。 */
  alt: string | null;
}

export function MediaThumb({ thumbUrl, status, alt }: MediaThumbProps) {
  const t = useT();
  if (status === "READY" && thumbUrl) {
    return <img alt={alt ?? ""} loading="lazy" src={thumbUrl} />;
  }

  return (
    <span className="cl-media-tile__pending">
      {status === "FAILED" ? t("product.media.processingFailed") : t("product.media.processing")}
    </span>
  );
}
