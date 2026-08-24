import { requestAdminGraphQL } from "../api/graphql";

/**
 * 直傳的前兩步（第 28 包抽出共用）。
 *
 * ①這是什麼：`stagedUploadsCreate`（簽發）→ `POST` multipart 到簽發回傳的 url。
 *   第 3 步因呼叫端而異——商品媒體走 `productCreateMedia`（`lib/mediaUpload.ts`），
 *   檔案庫走 `fileCreate`（`lib/filesApi.ts`）——所以**只有前兩步在這裡**。
 * ②🔴 抽出來的理由不是「省行數」，是**簽名協定只能有一份**：簽名參數要原樣回送、
 *   大小已被釘進簽名（`Storage::SignedUpload`），兩個呼叫端各抄一份的話，改協定時
 *   一定會漏掉一邊，而漏掉的那邊會在上傳當下才炸。
 * ③型別／大小的前端預檢在**呼叫端**做（各自的上限不同：商品媒體只收圖，檔案庫
 *   之後會收更多型別）；伺服端一律會再驗一次，前端那道只是省一次往返。
 */

/** 簽發回來的上傳目標。 */
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

/** CSRF token（與 api/graphql.ts 同源；multipart 走 fetch 需自帶）。 */
function csrfToken(): string {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content ?? "";
}

/** 失敗時丟出，訊息已是可直接顯示給使用者的文案。 */
export class StagedUploadError extends Error {}

/**
 * 簽發並把位元組送上去，回傳可交給第 3 步的 `resourceUrl`。
 *
 * @param file - 使用者選的檔案。
 * @returns staged resourceUrl。
 * @throws {StagedUploadError} 簽發被拒或 multipart 上傳非 2xx。
 */
export async function stageAndUpload(file: File): Promise<string> {
  const staged = await requestAdminGraphQL<
    { stagedUploadsCreate: { stagedTargets: StagedTarget[]; userErrors: { message: string }[] } },
    Record<string, unknown>
  >(STAGED_MUTATION, {
    input: [ { filename: file.name, mimeType: file.type, fileSize: file.size } ],
  });
  const result = staged.stagedUploadsCreate;
  if (result.userErrors.length > 0) throw new StagedUploadError(result.userErrors[0].message);

  const target = result.stagedTargets[0];
  const body = new FormData();
  for (const parameter of target.parameters) body.append(parameter.name, parameter.value);
  body.append("file", file);
  const response = await fetch(target.url, {
    method: "POST",
    body,
    headers: { "X-CSRF-Token": csrfToken() },
    credentials: "same-origin",
  });
  if (!response.ok) throw new StagedUploadError(`HTTP ${response.status}`);

  return target.resourceUrl;
}
