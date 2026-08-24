import { ImagePlus, Star, X } from "lucide-react";
import { useCallback, useId, useRef, useState } from "react";
import type { ChangeEvent, DragEvent } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { useT } from "../i18n/I18nContext";
import { uploadProductMedia } from "../lib/mediaUpload";
import { uuidV4 } from "../lib/uuid";
import { useToast } from "../lib/ToastContext";
import { Button } from "./Button";
import { ConfirmDialog } from "./ConfirmDialog";

/**
 * 商品媒體卡（第 27 包；原型 `pd-media` 的移植）。
 *
 * ①這是什麼：縮圖網格＋拖放上傳＋拖曳排序＋刪除確認＋alt 編輯。
 *   第一格＝精選圖（原型逐字「首格＝精選圖」；後端 position 1-based）。
 * ②🔴 **上傳是立即動作、排序是待儲存動作**：上傳完圖就該出現（否則使用者不知道
 *   傳成功沒有）；排序照工作卡「排序進 SaveProduct 同 transaction」——拖完進
 *   SaveBar，與商品其他欄位一起存。刪除是立即但先過確認框（不可復原）。
 * ③處理中狀態：`status !== READY` ⇒ 顯示占位而非原圖（20MB 原圖當縮圖會炸列表，
 *   第 26 包 ImageType 檔頭同紀律）。父層輪詢由 `onRefresh` 觸發。
 * ④送簽之前先做**型別與大小**的前端檢查（審查 C11：本註釋原本宣稱有、實際沒有）
 *   ——錯的檔連簽都不發；伺服端仍會再驗一次（`stagedUploadsCreate` 的配額預檢，
 *   12 §D.7-5），前端這道只是省一次往返與更快的錯誤訊息。
 * ⑤跨功能影響：第 28 包「選取現有檔案」接同一個 `productCreateMedia`（fileId 分支）；
 *   第 29 包變體子頁圖格複用本元件的 tile。
 */
export interface MediaCardItem {
  id: string;
  position: number;
  alt: string | null;
  status: string;
  image: { thumbUrl: string | null; url: string } | null;
}

/** 前端可接受的圖片型別（鏡射 limits `media.image_content_types`）。 */
const ACCEPTED_TYPES = [ "image/jpeg", "image/png", "image/webp", "image/gif" ];
/** 圖片大小上限（鏡射 limits `content.files_image_max_mb`）。 */
const MAX_IMAGE_BYTES = 20 * 1024 * 1024;

export interface MediaCardProps {
  /** 商品 GID；建立態為 null（媒體要先有商品才能掛）。 */
  productGid: string | null;
  /** 目前媒體（position 序）。 */
  media: readonly MediaCardItem[];
  /** 排序變更（拖曳後）——父層收進表單值，隨儲存送出。 */
  onReorder: (mediaIds: string[]) => void;
  /** 上傳／刪除後請父層重讀商品。 */
  onRefresh: () => void;
  /** 媒體數上限（limits.product.max_media 的前端鏡射由父層傳入）。 */
  maxMedia: number;
}

const DELETE_MUTATION = `
  mutation productDeleteMedia($productId: ID!, $mediaIds: [ID!]!) {
    productDeleteMedia(productId: $productId, mediaIds: $mediaIds) {
      deletedMediaIds
      userErrors { field message code }
    }
  }
`;

const UPDATE_MUTATION = `
  mutation productUpdateMedia($productId: ID!, $media: [UpdateMediaInput!]!) {
    productUpdateMedia(productId: $productId, media: $media) {
      media { id alt }
      userErrors { field message code }
    }
  }
`;

/**
 * 呈現媒體卡。
 *
 * @param props - 商品 GID、媒體清單與回呼。
 * @returns 建立態的空態 dropzone 或編輯態的縮圖網格。
 */
export function MediaCard({ productGid, media, onReorder, onRefresh, maxMedia }: MediaCardProps) {
  const t = useT();
  const { showToast } = useToast();
  const inputId = useId();
  const fileInput = useRef<HTMLInputElement | null>(null);
  const addButtonRef = useRef<HTMLButtonElement | null>(null);
  const [uploading, setUploading] = useState(false);
  const [dragOver, setDragOver] = useState(false);
  const [dragFrom, setDragFrom] = useState<number | null>(null);
  const [pendingDelete, setPendingDelete] = useState<MediaCardItem | null>(null);
  const [deleting, setDeleting] = useState(false);

  const upload = useCallback(
    async (files: FileList | File[]) => {
      if (!productGid) return;

      // 送簽前先擋（審查 C11）：型別與大小。拖放進來的檔案沒有 accept 屬性把關，
      // 這道是唯一的前端防線。
      const all = Array.from(files);
      const rejected = all.filter(
        (file) => !ACCEPTED_TYPES.includes(file.type) || file.size > MAX_IMAGE_BYTES,
      );
      if (rejected.length > 0) {
        showToast(t("product.media.rejected", { filename: rejected[0].name }));
      }
      const list = all.filter((file) => !rejected.includes(file));
      if (list.length === 0) return;

      const room = maxMedia - media.length;
      if (list.length > room) {
        showToast(t("product.media.overLimit", { max: maxMedia }));
        if (room <= 0) return;
      }
      setUploading(true);
      try {
        // 🔴 逐檔獨立：一檔失敗不影響其他檔（見 lib/mediaUpload ③）。
        //    序列而非 Promise.all（審查 C10）：後端以 FOR UPDATE 序列化同商品的
        //    position 分配，前端一次噴 N 個請求只是讓它們排隊等鎖；逐一送還能讓
        //    room 的判斷跟著實際結果走。
        const outcomes: Awaited<ReturnType<typeof uploadProductMedia>>[] = [];
        for (const file of list.slice(0, Math.max(room, 0))) {
          outcomes.push(await uploadProductMedia(file, productGid, uuidV4()));
        }
        const failed = outcomes.filter((outcome) => outcome.error);
        if (failed.length > 0) {
          showToast(t("product.media.uploadFailed", { filename: failed[0].filename, reason: failed[0].error ?? "" }));
        }
        if (failed.length < outcomes.length) onRefresh();
      } finally {
        setUploading(false);
      }
    },
    [maxMedia, media.length, onRefresh, productGid, showToast, t],
  );

  const onPick = (event: ChangeEvent<HTMLInputElement>) => {
    if (event.target.files?.length) void upload(event.target.files);
    event.target.value = ""; // 同一個檔連選兩次也要觸發
  };

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    setDragOver(false);
    if (event.dataTransfer.files?.length) void upload(event.dataTransfer.files);
  };

  // 縮圖拖曳排序：放開時把新順序交給父層（隨儲存送出，不立即寫 DB）
  const onTileDrop = (event: DragEvent<HTMLLIElement>, toIndex: number) => {
    event.preventDefault();
    if (dragFrom === null || dragFrom === toIndex) return;

    const next = media.map((item) => item.id);
    const [ moved ] = next.splice(dragFrom, 1);
    next.splice(toIndex, 0, moved);
    setDragFrom(null);
    onReorder(next);
  };

  const confirmDelete = async () => {
    if (!pendingDelete || !productGid) return;

    setDeleting(true);
    try {
      const data = await requestAdminGraphQL<
        { productDeleteMedia: { userErrors: { message: string }[] } },
        Record<string, unknown>
      >(DELETE_MUTATION, { productId: productGid, mediaIds: [ pendingDelete.id ] });
      const errors = data.productDeleteMedia.userErrors;
      if (errors.length > 0) showToast(errors[0].message);
      else onRefresh();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("product.media.deleteFailed"));
    } finally {
      setDeleting(false);
      setPendingDelete(null);
    }
  };

  const saveAlt = async (item: MediaCardItem, alt: string) => {
    if (!productGid || alt === (item.alt ?? "")) return;

    try {
      const data = await requestAdminGraphQL<
        { productUpdateMedia: { userErrors: { message: string }[] } },
        Record<string, unknown>
      >(UPDATE_MUTATION, { productId: productGid, media: [ { id: item.id, alt } ] });
      const errors = data.productUpdateMedia.userErrors;
      if (errors.length > 0) showToast(errors[0].message);
      else onRefresh();
    } catch (reason: unknown) {
      showToast(reason instanceof Error ? reason.message : t("product.media.altFailed"));
    }
  };

  // 建立態：商品還不存在 ⇒ 媒體無處可掛（原型同語義：空態只有兩顆按鈕）
  if (!productGid) {
    return (
      <div className="cl-dropzone">
        <ImagePlus aria-hidden="true" size={20} />
        <p>{t("product.media.afterSave")}</p>
      </div>
    );
  }

  return (
    <>
      <div
        className={dragOver ? "cl-dropzone cl-dropzone--over" : "cl-dropzone"}
        onDragLeave={() => setDragOver(false)}
        onDragOver={(event) => {
          event.preventDefault();
          setDragOver(true);
        }}
        onDrop={onDrop}
      >
        <ImagePlus aria-hidden="true" size={20} />
        <div className="cl-dropzone__actions">
          <Button
            loading={uploading}
            onClick={() => fileInput.current?.click()}
            ref={addButtonRef}
            size="small"
          >
            {t("product.media.upload")}
          </Button>
          <Button disabled size="small" title={t("product.media.selectExisting.pending")} variant="ghost">
            {t("product.media.selectExisting")}
          </Button>
        </div>
        <p>{t("product.media.accept", { max: maxMedia })}</p>
        <input
          accept="image/jpeg,image/png,image/webp,image/gif"
          aria-label={t("product.media.upload")}
          className="cl-visually-hidden"
          id={inputId}
          multiple
          onChange={onPick}
          ref={fileInput}
          type="file"
        />
      </div>

      {media.length > 0 ? (
        <ul aria-label={t("product.media.grid")} className="cl-media-grid">
          {media.map((item, index) => {
            const ready = item.status === "READY" && item.image?.thumbUrl;
            return (
              <li
                className={index === 0 ? "cl-media-tile cl-media-tile--lead" : "cl-media-tile"}
                draggable
                key={item.id}
                onDragEnd={() => setDragFrom(null)}
                onDragOver={(event) => event.preventDefault()}
                onDragStart={() => setDragFrom(index)}
                onDrop={(event) => onTileDrop(event, index)}
              >
                {index === 0 ? (
                  <span className="cl-media-tile__tag">
                    <Star aria-hidden="true" size={11} /> {t("product.media.featured")}
                  </span>
                ) : null}
                {ready ? (
                  <img alt={item.alt ?? ""} loading="lazy" src={item.image?.thumbUrl ?? ""} />
                ) : (
                  <span className="cl-media-tile__pending">
                    {item.status === "FAILED"
                      ? t("product.media.processingFailed")
                      : t("product.media.processing")}
                  </span>
                )}
                <input
                  aria-label={t("product.media.altFor", { position: index + 1 })}
                  className="cl-media-tile__alt"
                  defaultValue={item.alt ?? ""}
                  maxLength={512}
                  onBlur={(event) => void saveAlt(item, event.target.value)}
                  placeholder={t("product.media.altPlaceholder")}
                />
                <button
                  aria-label={t("product.media.remove", { position: index + 1 })}
                  className="cl-media-tile__remove"
                  onClick={() => setPendingDelete(item)}
                  type="button"
                >
                  <X aria-hidden="true" size={12} />
                </button>
              </li>
            );
          })}
        </ul>
      ) : null}

      <ConfirmDialog
        busy={deleting}
        confirmLabel={t("product.media.delete.action")}
        danger
        message={t("product.media.delete.body")}
        onCancel={() => setPendingDelete(null)}
        onConfirm={() => void confirmDelete()}
        open={pendingDelete !== null}
        restoreFocusTo={addButtonRef}
        title={t("product.media.delete.title")}
      />
    </>
  );
}
