import { PlayCircle } from "lucide-react";
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
 * ⑤第 37 包：外嵌影片走**自己的分支**——它沒有縮圖（A 面 `preview` 恆 null，
 *   要縮圖得等 B 面的 oEmbed），所以顯示平台名＋播放圖示，而不是「處理中」。
 *   🔴 不落到 `status` 分支：外嵌影片建立即 ready，落過去會顯示一個永遠不會結束
 *   的「處理中」。
 */
export interface MediaThumbProps {
  /** 衍生縮圖 URL；null＝尚未產出。 */
  thumbUrl: string | null;
  /** 四態之一。 */
  status: "UPLOADED" | "PROCESSING" | "READY" | "FAILED" | string;
  /** 圖片替代文字（D48：檔案層、全店一份）。 */
  alt: string | null;
  /** 外嵌影片的平台；非外嵌則省略（第 37 包）。 */
  videoHost?: "YOUTUBE" | "VIMEO" | null;
}

const HOST_LABEL: Record<string, string> = { YOUTUBE: "YouTube", VIMEO: "Vimeo" };

export function MediaThumb({ thumbUrl, status, alt, videoHost }: MediaThumbProps) {
  const t = useT();

  // 🔴 外嵌影片先判（見檔頭⑤）：它建立即 ready 且恆無縮圖，
  //    落到下面的 status 分支會顯示一個永遠不會結束的「處理中」。
  if (videoHost) {
    return (
      <span className="cl-media-tile__video">
        <PlayCircle aria-hidden="true" size={22} />
        <span className="cl-media-tile__video-host">{HOST_LABEL[videoHost] ?? videoHost}</span>
      </span>
    );
  }

  if (status === "READY" && thumbUrl) {
    return <img alt={alt ?? ""} loading="lazy" src={thumbUrl} />;
  }

  return (
    <span className="cl-media-tile__pending">
      {status === "FAILED" ? t("product.media.processingFailed") : t("product.media.processing")}
    </span>
  );
}
