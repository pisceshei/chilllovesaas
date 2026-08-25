import { requestAdminGraphQL } from "../api/graphql";
import { StagedUploadError, stageAndUpload } from "./stagedUpload";
import type { Page } from "./useCursorPagination";

/**
 * 檔案庫的資料存取（第 28 包）——`files` query＋`fileCreate`／`fileUpdate`／`fileDelete`。
 *
 * 消費者有兩個且**共用同一份型別**：檔案庫頁（`pages/FilesPage.tsx`）與選檔 modal
 * （`components/FilePickerModal.tsx`）。共用是刻意的：modal 裡看到的欄位若與列表
 * 不同（例如少了 `usageCount`），使用者在兩個地方對同一個檔會得到兩種印象。
 */

/** 檔案庫的一列。欄位集合＝`Types::FileType`。 */
export interface FileNode {
  id: string;
  filename: string;
  contentType: string;
  byteSize: number;
  status: "UPLOADED" | "PROCESSING" | "READY" | "FAILED";
  alt: string | null;
  url: string;
  thumbUrl: string | null;
  previewUrl: string | null;
  usageCount: number;
  processingError: string | null;
  createdAt: string;
}

/** 排序鍵（值域＝`Types::FileSortKeysEnum`）。 */
export type FileSortKey = "CREATED_AT" | "FILENAME" | "ORIGINAL_UPLOAD_SIZE";

export interface FilesFilter {
  query?: string;
  status?: FileNode["status"];
  usedIn?: "PRODUCT" | "NONE";
  sortKey?: FileSortKey;
  /** 反轉該鍵的**預設**方向（不是「改成 desc」——見伺服端 `file_order`）。 */
  reverse?: boolean;
}

const FILE_FIELDS = `
  id filename contentType byteSize status alt url
  thumbUrl previewUrl usageCount processingError createdAt
`;

const FILES_QUERY = `
  query filesList($first: Int!, $after: String, $query: String, $status: FileStatus,
                  $usedIn: FileUsedInFilter, $sortKey: FileSortKeys, $reverse: Boolean) {
    files(first: $first, after: $after, query: $query, status: $status,
          usedIn: $usedIn, sortKey: $sortKey, reverse: $reverse) {
      nodes { ${FILE_FIELDS} }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

const FILE_CREATE = `
  mutation fileCreate($files: [FileCreateInput!]!, $idempotencyKey: String) {
    fileCreate(files: $files, idempotencyKey: $idempotencyKey) {
      files { ${FILE_FIELDS} }
      userErrors { field message code }
    }
  }
`;

const FILE_UPDATE = `
  mutation fileUpdate($files: [FileUpdateInput!]!) {
    fileUpdate(files: $files) {
      files { ${FILE_FIELDS} }
      userErrors { field message code }
    }
  }
`;

const FILE_DELETE = `
  mutation fileDelete($fileIds: [ID!]!) {
    fileDelete(fileIds: $fileIds) {
      deletedFileIds
      userErrors { field message code }
    }
  }
`;

interface UserError {
  message: string;
}

/** 讀一頁檔案（含 `pageInfo`，供 `useCursorPagination` 接續）。 */
export async function fetchFilesPage(
  first: number,
  filter: FilesFilter,
  after: string | null,
  signal?: AbortSignal,
): Promise<Page<FileNode>> {
  const data = await requestAdminGraphQL<
    { files: Page<FileNode> },
    Record<string, unknown>
  >(FILES_QUERY, { first, after, ...filter }, signal);
  return data.files;
}

/** 只要第一頁的節點（選檔 modal 用；它不翻頁）。 */
export async function fetchFiles(
  first: number,
  filter: FilesFilter,
  signal?: AbortSignal,
): Promise<FileNode[]> {
  return (await fetchFilesPage(first, filter, null, signal)).nodes;
}

/** 單檔上傳結果；`error` 有值＝該檔失敗（其餘檔不受影響）。 */
export interface FileUploadOutcome {
  filename: string;
  file?: FileNode;
  error?: string;
}

/**
 * 上傳一個檔案到檔案庫（三步：簽發 → multipart → `fileCreate`）。
 *
 * 🔴 逐檔獨立——一檔失敗不影響其他檔（十個裡壞一個不該讓其他九個消失）。
 *
 * @param file - 使用者選的檔案。
 * @param idempotencyKey - 建立型 mutation 強制帶。
 */
export async function uploadToLibrary(
  file: File,
  idempotencyKey: string,
): Promise<FileUploadOutcome> {
  try {
    const resourceUrl = await stageAndUpload(file);
    const created = await requestAdminGraphQL<
      { fileCreate: { files: FileNode[]; userErrors: UserError[] } },
      Record<string, unknown>
    >(FILE_CREATE, {
      files: [ { originalSource: resourceUrl, filename: file.name } ],
      idempotencyKey,
    });
    const errors = created.fileCreate.userErrors;
    if (errors.length > 0) return { filename: file.name, error: errors[0].message };

    return { filename: file.name, file: created.fileCreate.files[0] };
  } catch (reason: unknown) {
    const message = reason instanceof StagedUploadError || reason instanceof Error
      ? reason.message
      : "";
    return { filename: file.name, error: message };
  }
}

/** 改檔案層 alt／檔名。回傳 userErrors 的第一則訊息（空＝成功）。 */
export async function updateFile(
  id: string,
  changes: { alt?: string; filename?: string },
): Promise<string | null> {
  const data = await requestAdminGraphQL<
    { fileUpdate: { userErrors: UserError[] } },
    Record<string, unknown>
  >(FILE_UPDATE, { files: [ { id, ...changes } ] });
  return data.fileUpdate.userErrors[0]?.message ?? null;
}

/** 刪檔（連帶解除商品引用）。回傳 userErrors 的第一則訊息（空＝成功）。 */
export async function deleteFiles(fileIds: string[]): Promise<string | null> {
  const data = await requestAdminGraphQL<
    { fileDelete: { userErrors: UserError[] } },
    Record<string, unknown>
  >(FILE_DELETE, { fileIds });
  return data.fileDelete.userErrors[0]?.message ?? null;
}

/** 人類可讀的檔案大小（列表欄與刪除確認共用——兩處不得各寫一份格式）。 */
export function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  const units = [ "KB", "MB", "GB" ];
  let value = bytes / 1024;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value < 10 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`;
}
