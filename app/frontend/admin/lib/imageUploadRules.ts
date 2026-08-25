/**
 * 圖片上傳的前端預檢規則（單一來源）。
 *
 * 🔴 **鐵律 6：上限值不得硬編**。這三個值原本在 `MediaCard`／`FilesPage`／
 *   `FilePickerModal` 各有一份**逐字相同**的拷貝——三份同時鏡射同一組 limits 鍵，
 *   改一處就漂移，而漂移的症狀是「這個入口擋、那個入口不擋」。
 *
 * 🔴 前端無法在執行期讀 YAML，所以這裡仍是**鏡射**而不是真正的單一來源；
 *   綁定方式是本註釋（同 `api/pagination.ts` 的既有作法）：
 *   - `ACCEPTED_TYPES` ← `limits.media.image_content_types`
 *   - `MAX_IMAGE_BYTES` ← `limits.content.files_image_max_mb`（20）
 *   - `UPLOAD_BATCH_MAX` ← `limits.content.files_upload_batch_max`（20）
 *   改那三個 limits 鍵時必須同步改這裡。
 *
 * 🔴 這道預檢**不是防線**：伺服端一律會再驗一次（`stagedUploadsCreate` 的配額預檢，
 *   12 §D.7-5）。它的作用是省一次往返並給出更快、更具體的錯誤訊息。
 */
export const ACCEPTED_TYPES = [ "image/jpeg", "image/png", "image/webp", "image/gif" ];
export const MAX_IMAGE_BYTES = 20 * 1024 * 1024;
export const UPLOAD_BATCH_MAX = 20;

/** 型別與大小都合格才回 true。 */
export function isAcceptableImage(file: File): boolean {
  return ACCEPTED_TYPES.includes(file.type) && file.size <= MAX_IMAGE_BYTES;
}
