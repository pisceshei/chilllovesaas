import { ImagePlus, X } from "lucide-react";
import { useCallback, useId, useRef, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { uuidV4 } from "../lib/uuid";
import { isAcceptableImage } from "../lib/imageUploadRules";
import { uploadProductMedia } from "../lib/mediaUpload";
import { Button } from "./Button";
import { FilePickerModal } from "./FilePickerModal";
import { MediaThumb } from "./MediaThumb";

/**
 * 變體圖格（第 29 包；93 §2 實測「主欄：變體圖『+』上傳格」）。
 *
 * ①這是什麼：**一格**——`limits.product.max_images_per_variant` 是 1（官方值）。
 *   已掛圖時顯示縮圖＋移除鈕；未掛時顯示「+」，可上傳新檔或從檔案庫選。
 * ②🔴 **不複用媒體卡的 tile**（整合規格 §1.1「複用不改語義」）：那個 tile 可拖曳
 *   重排、有精選標記——變體只有一格，拖曳與精選在這裡沒有意義。共用的只有
 *   `MediaThumb`（呈現層）。
 * ③🔴 **掛圖走 `productVariantAppendMedia`，不是 `productCreateMedia`**：
 *   變體圖是「把商品已有的某張圖指給這個變體」，`mediaId: null` 即卸圖。
 *   上傳新檔時要兩步——先 `productCreateMedia` 建進商品媒體，再 append 給變體。
 *   服務端會自動卸掉超出上限的舊圖（`Catalog::MediaSync#append_to_variant`）。
 * ④跨功能影響：卸圖**不刪商品媒體**——那張圖仍在商品的媒體卡裡，只是不再是
 *   這個變體的圖。要真的刪圖請去媒體卡或檔案庫。
 */
export interface VariantImageSlotProps {
  /** 商品 GID。 */
  productGid: string;
  /** 變體 GID。 */
  variantGid: string;
  /** 目前的變體圖；null＝未掛。 */
  image: { id: string; thumbUrl: string | null; status: string; alt: string | null } | null;
  /** 掛／卸之後請父層重讀。 */
  onChange: () => void;
}

const APPEND_MUTATION = `
  mutation productVariantAppendMedia($productId: ID!, $variantId: ID!, $mediaId: ID, $idempotencyKey: String) {
    productVariantAppendMedia(productId: $productId, variantId: $variantId,
                              mediaId: $mediaId, idempotencyKey: $idempotencyKey) {
      media { id }
      userErrors { field message code }
    }
  }
`;

const CREATE_FROM_FILE = `
  mutation productCreateMedia($productId: ID!, $media: [CreateMediaInput!]!, $idempotencyKey: String) {
    productCreateMedia(productId: $productId, media: $media, idempotencyKey: $idempotencyKey) {
      media { id }
      userErrors { field message code }
    }
  }
`;

export function VariantImageSlot({ productGid, variantGid, image, onChange }: VariantImageSlotProps) {
  const t = useT();
  const { showToast } = useToast();
  const inputId = useId();
  const fileInput = useRef<HTMLInputElement | null>(null);
  const pickerButton = useRef<HTMLButtonElement | null>(null);
  const [busy, setBusy] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);

  const append = useCallback(async (mediaId: string | null) => {
    const data = await requestAdminGraphQL<
      { productVariantAppendMedia: { userErrors: { message: string }[] } },
      Record<string, unknown>
    >(APPEND_MUTATION, {
      productId: productGid, variantId: variantGid, mediaId, idempotencyKey: uuidV4(),
    });
    const errors = data.productVariantAppendMedia.userErrors;
    if (errors.length > 0) {
      showToast(errors[0].message);
      return false;
    }
    return true;
  }, [productGid, showToast, variantGid]);

  // 上傳新檔：先進商品媒體，再指給這個變體（見檔頭③）。
  const onUpload = useCallback(async (picked: FileList | null) => {
    const file = picked?.[0];
    if (!file) return;
    if (!isAcceptableImage(file)) {
      showToast(t("product.media.rejected", { filename: file.name }));
      return;
    }

    setBusy(true);
    try {
      const outcome = await uploadProductMedia(file, productGid, uuidV4());
      if (outcome.error) {
        showToast(t("product.media.uploadFailed", { filename: outcome.filename, reason: outcome.error }));
        return;
      }
      // 上傳完**直接指給這個變體**——使用者在變體圖格按上傳，意圖就是要它當變體圖，
      // 再要求選一次是多餘的。`uploadProductMedia` 回傳的 mediaId 就是為了這一步。
      if (outcome.mediaId && await append(outcome.mediaId)) onChange();
      else onChange();
    } finally {
      setBusy(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }, [append, onChange, productGid, showToast, t]);

  // 從檔案庫選：先把檔案掛成商品媒體（fileId 分支），再指給變體。
  const onPick = useCallback(async (fileIds: string[]) => {
    setPickerOpen(false);
    const fileId = fileIds[0];
    if (!fileId) return;

    setBusy(true);
    try {
      const created = await requestAdminGraphQL<
        { productCreateMedia: { media: { id: string }[]; userErrors: { message: string }[] } },
        Record<string, unknown>
      >(CREATE_FROM_FILE, {
        productId: productGid, media: [ { fileId } ], idempotencyKey: uuidV4(),
      });
      const errors = created.productCreateMedia.userErrors;
      if (errors.length > 0) {
        showToast(errors[0].message);
        return;
      }
      const mediaId = created.productCreateMedia.media[0]?.id;
      if (mediaId && await append(mediaId)) onChange();
    } finally {
      setBusy(false);
    }
  }, [append, onChange, productGid, showToast]);

  const detach = useCallback(async () => {
    setBusy(true);
    try {
      if (await append(null)) onChange();
    } finally {
      setBusy(false);
    }
  }, [append, onChange]);

  return (
    <div className="cl-variant-image">
      {image ? (
        <div className="cl-variant-image__tile">
          <MediaThumb alt={image.alt} status={image.status} thumbUrl={image.thumbUrl} />
          <button
            aria-label={t("variant.image.detach")}
            className="cl-media-tile__remove"
            disabled={busy}
            onClick={() => void detach()}
            type="button"
          >
            <X aria-hidden="true" size={12} />
          </button>
        </div>
      ) : (
        <div className="cl-variant-image__empty">
          <ImagePlus aria-hidden="true" size={20} />
          <div className="cl-variant-image__actions">
            <Button disabled={busy} onClick={() => fileInput.current?.click()} size="small">
              {t("product.media.upload")}
            </Button>
            <Button
              disabled={busy}
              onClick={() => setPickerOpen(true)}
              ref={pickerButton}
              size="small"
              variant="ghost"
            >
              {t("product.media.selectExisting")}
            </Button>
          </div>
        </div>
      )}

      <input
        accept="image/jpeg,image/png,image/webp,image/gif"
        aria-label={t("product.media.upload")}
        className="cl-visually-hidden"
        id={inputId}
        onChange={(event) => void onUpload(event.target.files)}
        ref={fileInput}
        type="file"
      />

      <FilePickerModal
        maxSelectable={1}
        onClose={() => setPickerOpen(false)}
        onSelect={(fileIds) => void onPick(fileIds)}
        open={pickerOpen}
        restoreFocusTo={pickerButton}
      />
    </div>
  );
}
