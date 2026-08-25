import { FolderUp, ImageOff, RefreshCw, Trash2, Upload } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { ConfirmDialog } from "../components/ConfirmDialog";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { deleteFiles, fetchFilesPage, formatBytes, updateFile, uploadToLibrary } from "../lib/filesApi";
import type { FileNode, FileSortKey, FilesFilter } from "../lib/filesApi";
import { LoadMore } from "../components/LoadMore";
import { useCursorPagination } from "../lib/useCursorPagination";
import { DEFAULT_PAGE_SIZE } from "../api/pagination";
import { uuidV4 } from "../lib/uuid";
import { ACCEPTED_TYPES, UPLOAD_BATCH_MAX, isAcceptableImage } from "../lib/imageUploadRules";

/**
 * 檔案庫 `/admin/content/files`（第 28 包；整合規格 §4-28）。
 *
 * ①這是什麼：整店檔案的列表——縮圖、檔名、型別、大小、**引用數**、狀態、
 *   上傳日期；可上傳、可改 alt／檔名、可（批次）刪除、可依檔名／狀態／引用篩選。
 * ②🔴 **引用數欄是這一頁存在的理由**：沒有它，使用者不知道哪些檔可以安全刪、
 *   刪掉會弄壞哪幾個商品。它的數字來源只有一個（`file_usages`，經
 *   `StoredFile::USAGE_COUNT_SELECT` 一次帶出），與刪除確認框用的是同一個值
 *   ——兩套計數＝事故（排程 §四.28）。
 * ③🔴 **刪檔會連帶拿掉商品上的圖**（官方語義，取證 2026-08-25：
 *   "the mutation automatically removes those references and reorders any remaining
 *   media"）。所以確認框必須先講清楚會影響幾個商品，**不能只說「確定刪除？」**。
 * ④跨功能影響：`FilePickerModal` 讀同一份 `lib/filesApi`；上傳走
 *   `lib/stagedUpload` 的前兩步（與商品媒體同一份簽名協定）；刪檔後商品頁的
 *   媒體卡下次載入就少一張且**剩下的會補位**。
 */
type StatusFilter = "ALL" | FileNode["status"];
type UsageFilter = "ALL" | "PRODUCT" | "NONE";

const STATUS_TONE: Record<FileNode["status"], "default" | "info" | "success" | "critical"> = {
  UPLOADED: "default",
  PROCESSING: "info",
  READY: "success",
  FAILED: "critical",
};

export function FilesPage() {
  const t = useT();
  const { showToast } = useToast();
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  const [status, setStatus] = useState<StatusFilter>("ALL");
  const [usage, setUsage] = useState<UsageFilter>("ALL");
  // 🔴 `IndexTable` 的選取是**非受控**、且 `onSelectionChange` 回傳的是整列不是 id
  //    ——這裡存整列而不是 id 陣列，才不會為了做刪除確認再去 files 裡找回來。
  const [sortKey, setSortKey] = useState<FileSortKey>("CREATED_AT");
  const [reverse, setReverse] = useState(false);
  const [selected, setSelected] = useState<FileNode[]>([]);
  const [pendingDelete, setPendingDelete] = useState<FileNode[] | null>(null);
  const [busy, setBusy] = useState(false);
  const fileInput = useRef<HTMLInputElement | null>(null);
  const uploadButton = useRef<HTMLButtonElement | null>(null);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);

  const filter = useMemo<FilesFilter>(() => ({
    query: debounced || undefined,
    status: status === "ALL" ? undefined : status,
    usedIn: usage === "ALL" ? undefined : usage,
    sortKey,
    reverse,
  }), [debounced, status, usage, sortKey, reverse]);

  const fetchPage = useCallback(
    (cursor: string | null, signal: AbortSignal) =>
      fetchFilesPage(DEFAULT_PAGE_SIZE, filter, cursor, signal),
    [filter],
  );
  const {
    items: files, error, loadMoreError, hasNextPage, loadingMore, loadMore, reload,
  } = useCursorPagination(fetchPage, [ filter ], t("files.loadError"));

  // 🔴 重讀後把已不存在的選取丟掉——留著會讓批次刪除送出一批幽靈 id。
  //    改成對 `files` 的變化收斂（分頁 hook 自己管資料），而不是在載入回呼裡做。
  useEffect(() => {
    // 🔴 `files` 變 null（重載中）時 `IndexTable` 整個 unmount、它的非受控選取歸零，
    //    父層若不跟著清就會留下**畫面上沒有勾、標題列卻說要刪 N 個**的幽靈選取。
    if (files === null) {
      setSelected((current) => (current.length === 0 ? current : []));
      return;
    }

    setSelected((current) => {
      if (current.length === 0) return current;

      const live = new Set(files.map((row) => row.id));
      const kept = current.filter((row) => live.has(row.id));
      return kept.length === current.length ? current : kept;
    });
  }, [files]);
  const hasFilter = debounced !== "" || status !== "ALL" || usage !== "ALL";

  const onUpload = useCallback(async (picked: FileList | null) => {
    if (!picked || picked.length === 0) return;

    const all = Array.from(picked);
    const rejected = all.filter((file) => !isAcceptableImage(file));
    if (rejected.length > 0) showToast(t("files.rejected", { filename: rejected[0].name }));
    const list = all.filter((file) => !rejected.includes(file)).slice(0, UPLOAD_BATCH_MAX);
    if (list.length === 0) return;
    if (all.length > UPLOAD_BATCH_MAX) showToast(t("files.batchLimit", { max: UPLOAD_BATCH_MAX }));

    setBusy(true);
    try {
      // 逐檔序列：一檔失敗不影響其他檔，且失敗訊息能指名是哪一個檔
      const failed: string[] = [];
      for (const file of list) {
        const outcome = await uploadToLibrary(file, uuidV4());
        if (outcome.error) failed.push(outcome.filename);
      }
      if (failed.length > 0) showToast(t("files.uploadFailed", { filename: failed[0] }));
      reload();
    } finally {
      setBusy(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }, [reload, showToast, t]);

  const onAltCommit = useCallback(async (row: FileNode, alt: string) => {
    if (alt === (row.alt ?? "")) return;

    const message = await updateFile(row.id, { alt });
    // 🔴 **成功時不 reload**（對抗審查抓到）：`reload()` 會把 items 設回 null，
    //    整張表 unmount ⇒ ⓐ使用者正在另一列打到一半的 alt（非受控 defaultValue）
    //    連同焦點一起被銷毀 ⓑ已「載入更多」累積的第 2、3 頁全部丟掉。
    //    而 alt 是使用者自己剛打的值，畫面上已經是對的——沒有需要跟伺服端同步的東西。
    if (message) showToast(message);
  }, [showToast]);

  const confirmDelete = useCallback(async () => {
    if (!pendingDelete) return;

    setBusy(true);
    try {
      const message = await deleteFiles(pendingDelete.map((row) => row.id));
      if (message) showToast(message);
      else {
        setSelected([]);
        reload();
      }
    } finally {
      setBusy(false);
      setPendingDelete(null);
    }
  }, [pendingDelete, reload, showToast]);

  const columns: readonly IndexTableColumn<FileNode>[] = [
    {
      key: "preview",
      header: t("files.col.preview"),
      render: (row) => (row.thumbUrl ? (
        <img alt={row.alt ?? ""} className="cl-file-row__thumb" loading="lazy" src={row.thumbUrl} />
      ) : (
        <span className="cl-file-row__thumb cl-file-row__thumb--empty">
          <ImageOff aria-hidden="true" size={14} />
        </span>
      )),
    },
    {
      key: "filename",
      header: t("files.col.filename"),
      render: (row) => <span className="cl-product-title">{row.filename}</span>,
    },
    {
      key: "alt",
      header: t("files.col.alt"),
      render: (row) => (
        <input
          aria-label={t("files.altFor", { filename: row.filename })}
          className="cl-file-row__alt"
          defaultValue={row.alt ?? ""}
          disabled={row.status !== "READY"}
          maxLength={512}
          onBlur={(event) => void onAltCommit(row, event.target.value)}
          placeholder={t("files.altPlaceholder")}
        />
      ),
    },
    {
      key: "status",
      header: t("files.col.status"),
      render: (row) => (
        <Badge tone={STATUS_TONE[row.status]}>
          {t(`files.status.${row.status}`)}
        </Badge>
      ),
    },
    {
      align: "right",
      key: "usage",
      header: t("files.col.usage"),
      // 🔴 0 與「用在 N 個商品」是兩件事，要看得出差別——0 是「可安全刪除」的訊號
      render: (row) => (row.usageCount === 0
        ? <span className="cl-file-row__unused">{t("files.unused")}</span>
        : t("files.usedIn", { count: row.usageCount })),
    },
    { align: "right", key: "size", header: t("files.col.size"), render: (row) => formatBytes(row.byteSize) },
  ];

  const actions = (
    <>
      {selected.length > 0 ? (
        <Button onClick={() => setPendingDelete(selected)} variant="critical">
          <Trash2 aria-hidden="true" size={15} />
          {t("files.deleteSelected", { count: selected.length })}
        </Button>
      ) : null}
      <Button disabled={busy} onClick={() => fileInput.current?.click()} ref={uploadButton} variant="primary">
        <Upload aria-hidden="true" size={15} />
        {busy ? t("files.uploading") : t("files.upload")}
      </Button>
    </>
  );

  /** 刪除確認的內文——**先講會影響幾個商品**（見檔頭③）。 */
  const deleteMessage = useMemo(() => {
    if (!pendingDelete) return null;

    const attached = pendingDelete.filter((row) => row.usageCount > 0);
    const references = attached.reduce((sum, row) => sum + row.usageCount, 0);
    return (
      <>
        <p>{t("files.delete.body", { count: pendingDelete.length })}</p>
        {attached.length > 0 ? (
          <p className="cl-file-delete__warning">
            {t("files.delete.inUse", { files: attached.length, references })}
          </p>
        ) : (
          <p>{t("files.delete.unused")}</p>
        )}
      </>
    );
  }, [pendingDelete, t]);

  return (
    <Page actions={actions} title={t("files.title")} width="index">
      <input
        accept={ACCEPTED_TYPES.join(",")}
        className="cl-visually-hidden"
        multiple
        onChange={(event) => void onUpload(event.target.files)}
        ref={fileInput}
        type="file"
      />

      <Card className="cl-files-filters">
        <input
          aria-label={t("files.search")}
          className="cl-files-filters__search"
          onChange={(event) => setSearch(event.target.value)}
          placeholder={t("files.search")}
          type="search"
          value={search}
        />
        <label className="cl-files-filters__select">
          <span>{t("files.col.status")}</span>
          <select onChange={(event) => setStatus(event.target.value as StatusFilter)} value={status}>
            <option value="ALL">{t("files.filter.all")}</option>
            <option value="READY">{t("files.status.READY")}</option>
            <option value="PROCESSING">{t("files.status.PROCESSING")}</option>
            <option value="UPLOADED">{t("files.status.UPLOADED")}</option>
            <option value="FAILED">{t("files.status.FAILED")}</option>
          </select>
        </label>
        <label className="cl-files-filters__select">
          <span>{t("files.col.sort")}</span>
          <select onChange={(event) => setSortKey(event.target.value as FileSortKey)} value={sortKey}>
            <option value="CREATED_AT">{t("files.sort.CREATED_AT")}</option>
            <option value="FILENAME">{t("files.sort.FILENAME")}</option>
            <option value="ORIGINAL_UPLOAD_SIZE">{t("files.sort.ORIGINAL_UPLOAD_SIZE")}</option>
          </select>
        </label>
        <label className="cl-files-filters__check">
          <input checked={reverse} onChange={(event) => setReverse(event.target.checked)} type="checkbox" />
          <span>{t("files.sort.reverse")}</span>
        </label>
        <label className="cl-files-filters__select">
          <span>{t("files.col.usage")}</span>
          <select onChange={(event) => setUsage(event.target.value as UsageFilter)} value={usage}>
            <option value="ALL">{t("files.filter.all")}</option>
            <option value="PRODUCT">{t("files.filter.used")}</option>
            <option value="NONE">{t("files.filter.unused")}</option>
          </select>
        </label>
      </Card>

      {error ? (
        <div className="cl-error-banner" role="alert">
          <div>
            <strong>{t("files.loadFailed")}</strong>
            <p>{error}</p>
          </div>
          <Button onClick={reload} size="small" variant="secondary">
            <RefreshCw aria-hidden="true" size={14} />
            {t("common.retry")}
          </Button>
        </div>
      ) : files === null ? (
        <Card aria-label={t("files.loading")} className="cl-products-loading">
          <span className="cl-sr-only" role="status">{t("files.loading")}</span>
          {Array.from({ length: 4 }, (_, index) => <span className="cl-skeleton" key={index} />)}
        </Card>
      ) : files.length === 0 ? (
        <Card className="cl-products-empty">
          <EmptyState
            action={hasFilter ? null : (
              <Button onClick={() => fileInput.current?.click()} variant="primary">
                <Upload aria-hidden="true" size={15} />
                {t("files.upload")}
              </Button>
            )}
            description={hasFilter ? t("files.noMatch.description") : t("files.empty.description")}
            illustration={<FolderUp size={30} strokeWidth={1.7} />}
            title={hasFilter ? t("files.noMatch.title") : t("files.empty.title")}
          />
        </Card>
      ) : (
        <Card>
          <IndexTable
            caption={t("files.caption")}
            columns={columns}
            getRowKey={(row) => row.id}
            getRowLabel={(row) => row.filename}
            onSelectionChange={setSelected}
            rows={files}
          />
        </Card>
      )}

      <LoadMore
        error={loadMoreError}
        hasNextPage={hasNextPage}
        loading={loadingMore}
        onLoadMore={loadMore}
      />

      <ConfirmDialog
        busy={busy}
        confirmLabel={t("files.delete.action")}
        danger
        message={deleteMessage}
        onCancel={() => setPendingDelete(null)}
        onConfirm={() => void confirmDelete()}
        open={pendingDelete !== null}
        restoreFocusTo={uploadButton}
        title={t("files.delete.title", { count: pendingDelete?.length ?? 0 })}
      />
    </Page>
  );
}
