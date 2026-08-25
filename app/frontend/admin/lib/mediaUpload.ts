import { requestAdminGraphQL } from "../api/graphql";

/**
 * 媒體上傳的三步直傳（第 27 包；12 §D.7 兩段式＋掛商品）。
 *
 * ①這是什麼：`stagedUploadsCreate`（簽發）→ `POST /admin/uploads/staged`（直傳
 *   multipart）→ `productCreateMedia`（掛商品，內部走 fileCreate 建檔）。
 *   後端三支在第 25／27 包已就緒，本檔是**第一個前端呼叫者**。
 * ②🔴 第 2 步走 HTTP 不走 GraphQL：二進位是檔案通道（同 TranslationCsvCard 的
 *   CSV 匯入先例），資料讀寫仍只走 GraphQL（D5）。
 * ③🔴 逐檔獨立：一檔失敗不影響其他檔——媒體卡要能顯示「這三張成功、那張失敗」，
 *   而不是整批 rollback（使用者剛拖進來的十張圖不該因為一張壞掉全部消失）。
 * ④型別／大小的前端預檢在呼叫端（`MediaCard`）做，本檔只負責三步的協定；
 *   伺服端仍會再驗一次（`stagedUploadsCreate` 的配額預檢，12 §D.7-5）——
 *   前端那道只是省一次往返，不是防線。
 */

/** 單檔上傳結果；`error` 有值＝該檔失敗（其餘檔不受影響）。 */
export interface MediaUploadOutcome {
  filename: string;
  error?: string;
  /** 成功時的媒體 GID。變體圖格靠它把剛傳好的圖直接指給變體（第 29 包）；
   *  媒體卡不需要（它重讀整份列表），但回傳它不花任何代價。 */
  mediaId?: string;
}

interface StagedTarget {
  url: string;
  resourceUrl: string;
  parameters: { name: string; value: string }[];
}

const STAGED_MUTATION = `
  mutation stagedUploadsCreate($input: [StagedUploadInput!]!) {
    stagedUploadsCreate(input: $input) {
      stagedTargets { url resourceUrl parameters { name value } }
      userErrors { field message code }
    }
  }
`;

const CREATE_MEDIA_MUTATION = `
  mutation productCreateMedia($productId: ID!, $media: [CreateMediaInput!]!, $idempotencyKey: String) {
    productCreateMedia(productId: $productId, media: $media, idempotencyKey: $idempotencyKey) {
      media { id }
      userErrors { field message code }
    }
  }
`;

interface UserError {
  message: string;
}

/** CSRF token（與 api/graphql.ts 同源；multipart 走 fetch 需自帶）。 */
function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
}

/**
 * 上傳一個檔案並掛到商品上。
 *
 * @param file - 使用者選的檔案。
 * @param productGid - 目標商品 GID。
 * @param idempotencyKey - 本次建立的冪等鍵（建立型 mutation 強制）。
 * @returns 成功時 `{ filename }`；失敗時帶 `error` 訊息。
 */
export async function uploadProductMedia(
  file: File,
  productGid: string,
  idempotencyKey: string,
): Promise<MediaUploadOutcome> {
  try {
    // 第 1 步：簽發（伺服端在此做配額預檢並把大小釘進簽名）
    const staged = await requestAdminGraphQL<
      { stagedUploadsCreate: { stagedTargets: StagedTarget[]; userErrors: UserError[] } },
      Record<string, unknown>
    >(STAGED_MUTATION, {
      input: [ { filename: file.name, mimeType: file.type, fileSize: file.size } ],
    });
    const stagedResult = staged.stagedUploadsCreate;
    if (stagedResult.userErrors.length > 0) {
      return { filename: file.name, error: stagedResult.userErrors[0].message };
    }
    const target = stagedResult.stagedTargets[0];

    // 第 2 步：直傳（multipart；簽名參數原樣回送）
    const body = new FormData();
    for (const parameter of target.parameters) body.append(parameter.name, parameter.value);
    body.append("file", file);
    const uploadResponse = await fetch(target.url, {
      method: "POST",
      body,
      headers: { "X-CSRF-Token": csrfToken() },
      credentials: "same-origin",
    });
    if (!uploadResponse.ok) {
      return { filename: file.name, error: `上傳失敗（HTTP ${uploadResponse.status}）` };
    }

    // 第 3 步：掛商品（內部走 fileCreate 建檔＋發 media.uploaded 事件）
    const created = await requestAdminGraphQL<
      { productCreateMedia: { media: { id: string }[]; userErrors: UserError[] } },
      Record<string, unknown>
    >(CREATE_MEDIA_MUTATION, {
      productId: productGid,
      media: [ { originalSource: target.resourceUrl } ],
      idempotencyKey,
    });
    const createErrors = created.productCreateMedia.userErrors;
    if (createErrors.length > 0) return { filename: file.name, error: createErrors[0].message };

    return { filename: file.name, mediaId: created.productCreateMedia.media[0]?.id };
  } catch (reason: unknown) {
    return { filename: file.name, error: reason instanceof Error ? reason.message : "上傳失敗" };
  }
}
