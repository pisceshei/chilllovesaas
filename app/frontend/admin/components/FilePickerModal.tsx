import { ImageOff, Search, Upload } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { RefObject } from "react";
import { Button } from "./Button";
import { EmptyState } from "./EmptyState";
import { Modal } from "./Modal";
import { useT } from "../i18n/I18nContext";
import { fetchFiles, formatBytes, uploadToLibrary } from "../lib/filesApi";
import { uuidV4 } from "../lib/uuid";
import { ACCEPTED_TYPES, UPLOAD_BATCH_MAX, isAcceptableImage } from "../lib/imageUploadRules";
import { useToast } from "../lib/ToastContext";
import type { FileNode } from "../lib/filesApi";

/**
 * 「選取現有檔案」modal（第 28 包；整合規格 §1.7 的第三個 Modal 消費者）。
 *
 * ①這是什麼：從檔案庫挑既有檔案掛到商品上。挑完回傳 **file GID 陣列**給呼叫端，
 *   由呼叫端送 `productCreateMedia` 的 `fileId` 分支——那條分支第 27 包就做好了，
 *   本元件是它的第一個使用者。
 * ②**多選**：本尊的選檔器支援批次（Files 頁「Select up to 20 files」同一批次上限），
 *   我方沿用 `content.files_upload_batch_max`。選了幾個顯示在動作鈕上。
 * ③🔴 **從檔案庫「列出」時只列 READY**：處理中或失敗的舊檔沒有縮圖，列一整格
 *   空白 tile 幫不上選圖。⇒ 篩掉是刻意的，不是漏了 `status` 篩選。
 *   ⚠️ **例外：使用者剛在這裡上傳的那一個**。它必然是 `uploaded`（管線還沒跑），
 *   但它不是「卡住的舊檔」——幾秒後就會 ready，而且掛上商品也沒問題
 *   （第 27 包審查 C2 之後媒體卡讀的是 `files.status`，會自己從「處理中」變成縮圖）。
 *   它以 placeholder tile 呈現，與舊檔的差別在於**使用者知道自己剛傳了它**。
 * ④**可以在這裡直接上傳**（D48「所有的都跟 Shopify」：本尊的 picker 有
 *   「Upload new」）。傳完的檔會直接出現在下方網格且**自動選取**——
 *   使用者按「上傳」的意圖就是要用它，還要再點一次是多餘的一步。
 * ⑤跨功能影響：`MediaCard`（商品頁）是目前唯一呼叫者；第 29 包變體子頁的圖格
 *   會是第二個。**props 介面改動要先對齊整合規格 §1.7**（Modal 原語同紀律）。
 */


export interface FilePickerModalProps {
  /** 是否顯示。 */
  open: boolean;
  /** 關閉請求。 */
  onClose: () => void;
  /** 確認選取——回傳 file GID 陣列（順序＝使用者點選順序）。 */
  onSelect: (fileIds: string[]) => void;
  /** 本次最多還能選幾個（呼叫端算：商品媒體上限 − 現有數）。 */
  maxSelectable: number;
  /** 關閉後的焦點還原目標。 */
  restoreFocusTo?: RefObject<HTMLElement | null>;
}

export function FilePickerModal({
  open, onClose, onSelect, maxSelectable, restoreFocusTo,
}: FilePickerModalProps) {
  const t = useT();
  const { showToast } = useToast();
  const [files, setFiles] = useState<FileNode[] | null>(null);
  const [uploading, setUploading] = useState(false);
  const fileInput = useRef<HTMLInputElement | null>(null);
  // 🔴 modal 已關閉時，in-flight 的上傳不得再寫狀態：清空掛在「關閉」那一刻，
  //    晚回來的 `setSelected` 會把選取塞回去、並存活到下一次開啟。
  const openRef = useRef(open);
  openRef.current = open;
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");
  // 🔴 選取數的即時鏡射。上傳迴圈要在**呼叫 setSelected 之前**知道還有沒有名額——
  //    把計數寫在 updater 裡是錯的：React 可能還沒跑那個 updater，迴圈就已經結束，
  //    於是「達上限」的提示永遠不會出現（本輪實測踩到）。
  const selectedRef = useRef<string[]>([]);
  selectedRef.current = selected;

  // 300ms debounce（同 ProductsPage 的伺服器端搜尋節奏）
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(search.trim()), 300);
    return () => clearTimeout(timer);
  }, [search]);

  // 每次開啟都重讀＋清空選取：上一次的選取在這一次沒有意義，
  // 留著會讓使用者在不知情下重複掛同一張圖。
  useEffect(() => {
    if (!open) {
      setSelected([]);
      setSearch("");
      return;
    }
    const controller = new AbortController();
    setFiles(null);
    setError(null);
    fetchFiles(50, { status: "READY", query: debounced || undefined }, controller.signal)
      .then(setFiles)
      .catch((reason: unknown) => {
        if (controller.signal.aborted) return;
        setError(reason instanceof Error ? reason.message : t("files.loadError"));
      });
    return () => controller.abort();
  }, [open, debounced, t]);

  // 🔴 `selected` 只保留還在網格裡的 id。上傳途中改搜尋 ⇒ refetch 覆蓋掉剛
  //    prepend 的新檔，若不收斂就會留下一個**畫面上看不到、卻會被送出**的選取。
  useEffect(() => {
    if (files === null) return;

    setSelected((current) => {
      if (current.length === 0) return current;

      const live = new Set(files.map((row) => row.id));
      const kept = current.filter((id) => live.has(id));
      return kept.length === current.length ? current : kept;
    });
  }, [files]);

  const toggle = useCallback((id: string) => {
    setSelected((current) => {
      if (current.includes(id)) return current.filter((item) => item !== id);
      // 已達上限就不再加（動作鈕旁的提示會說明還能選幾個）
      if (current.length >= maxSelectable) return current;
      return [ ...current, id ];
    });
  }, [maxSelectable]);

  // 在 modal 內上傳（D48）。傳完直接塞進網格頂端並自動選取——
  // 使用者按上傳就是要用它，再要求點一次是多餘的。
  const onUpload = useCallback(async (picked: FileList | null) => {
    if (!picked || picked.length === 0) return;

    const all = Array.from(picked);
    const rejected = all.filter((file) => !isAcceptableImage(file));
    if (rejected.length > 0) showToast(t("files.rejected", { filename: rejected[0].name }));
    // 🔴 單次批量上限與檔案庫頁同一個（鐵律 6：`content.files_upload_batch_max`）。
    //    這條路徑原本沒套，等於同一個上限在兩個入口不一致。
    const accepted = all.filter((file) => !rejected.includes(file));
    const list = accepted.slice(0, UPLOAD_BATCH_MAX);
    if (accepted.length > UPLOAD_BATCH_MAX) {
      showToast(t("files.batchLimit", { max: UPLOAD_BATCH_MAX }));
    }
    if (list.length === 0) return;

    setUploading(true);
    let unselected = 0;
    // 呼叫 setSelected 之前先算好還剩幾個名額（見 selectedRef 的註釋）。
    let room = Math.max(maxSelectable - selectedRef.current.length, 0);
    try {
      for (const file of list) {
        const outcome = await uploadToLibrary(file, uuidV4());
        // 🔴 modal 已被關掉 ⇒ 不再寫任何狀態（檔案仍會建立，那是對的：
        //    使用者確實傳了它，它就該在檔案庫裡）。
        if (!openRef.current) continue;

        if (outcome.error || !outcome.file) {
          showToast(t("files.uploadFailed", { filename: outcome.filename }));
          continue;
        }
        const created = outcome.file;
        setFiles((current) => [ created, ...(current ?? []) ]);
        if (room > 0) {
          room -= 1;
          setSelected((current) => (current.includes(created.id) ? current : [ ...current, created.id ]));
        } else {
          unselected += 1;
        }
      }
    } finally {
      if (openRef.current) setUploading(false);
      if (fileInput.current) fileInput.current.value = "";
    }
    // 🔴 達選取上限時**明說**：檔案已經進檔案庫但沒被選取。
    //    不說的話使用者只看到 tile 是 disabled 態，會以為上傳失敗。
    if (unselected > 0) showToast(t("files.picker.uploadedNotSelected", { count: unselected }));
  }, [maxSelectable, showToast, t]);

  const confirm = useCallback(() => {
    if (selected.length === 0) return;
    onSelect(selected);
  }, [onSelect, selected]);

  const atLimit = selected.length >= maxSelectable;
  const footer = useMemo(() => (
    <>
      <span className="cl-file-picker__count">
        {atLimit
          ? t("files.picker.atLimit", { max: maxSelectable })
          : t("files.picker.selected", { count: selected.length })}
      </span>
      <Button disabled={uploading} onClick={() => fileInput.current?.click()} variant="secondary">
        <Upload aria-hidden="true" size={14} />
        {uploading ? t("files.picker.uploading") : t("files.picker.uploadNew")}
      </Button>
      <Button onClick={onClose} variant="secondary">{t("common.cancel")}</Button>
      <Button disabled={selected.length === 0} onClick={confirm} variant="primary">
        {t("files.picker.confirm", { count: selected.length })}
      </Button>
    </>
  ), [atLimit, confirm, maxSelectable, onClose, onUpload, selected.length, t, uploading]);

  return (
    <Modal
      footer={footer}
      onClose={onClose}
      open={open}
      restoreFocusTo={restoreFocusTo}
      title={t("files.picker.title")}
    >
      <div className="cl-file-picker">
        <input
          accept={ACCEPTED_TYPES.join(",")}
          aria-label={t("files.picker.uploadNew")}
          className="cl-visually-hidden"
          multiple
          onChange={(event) => void onUpload(event.target.files)}
          ref={fileInput}
          type="file"
        />
        <label className="cl-file-picker__search">
          <Search aria-hidden="true" size={15} />
          <input
            aria-label={t("files.picker.search")}
            data-autofocus
            onChange={(event) => setSearch(event.target.value)}
            placeholder={t("files.picker.search")}
            type="search"
            value={search}
          />
        </label>

        {error ? (
          <p className="cl-file-picker__error" role="alert">{error}</p>
        ) : files === null ? (
          <div aria-label={t("files.loading")} className="cl-file-picker__grid">
            <span className="cl-sr-only" role="status">{t("files.loading")}</span>
            {Array.from({ length: 8 }, (_, index) => (
              <span className="cl-skeleton cl-file-picker__skeleton" key={index} />
            ))}
          </div>
        ) : files.length === 0 ? (
          <EmptyState
            // 選檔器裡不放上傳 CTA：上傳鈕就在 modal 外面（媒體卡的第一顆），
            // 在這裡再放一顆會讓「我到底在哪個流程」變模糊。
            action={null}
            description={debounced ? t("files.picker.noMatch") : t("files.picker.empty.description")}
            illustration={<ImageOff size={28} strokeWidth={1.7} />}
            title={debounced ? t("files.noMatch.title") : t("files.picker.empty.title")}
          />
        ) : (
          <ul aria-label={t("files.picker.grid")} className="cl-file-picker__grid">
            {files.map((file) => {
              const isSelected = selected.includes(file.id);
              return (
                <li key={file.id}>
                  <button
                    aria-pressed={isSelected}
                    className={isSelected ? "cl-file-tile cl-file-tile--on" : "cl-file-tile"}
                    // 未選且已達上限 ⇒ 禁用（比點了沒反應誠實）
                    disabled={!isSelected && atLimit}
                    onClick={() => toggle(file.id)}
                    type="button"
                  >
                    {file.thumbUrl ? (
                      <img alt={file.alt ?? ""} loading="lazy" src={file.thumbUrl} />
                    ) : (
                      <span className="cl-file-tile__placeholder">
                        <ImageOff aria-hidden="true" size={18} />
                      </span>
                    )}
                    <span className="cl-file-tile__name">{file.filename}</span>
                    <span className="cl-file-tile__meta">{formatBytes(file.byteSize)}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </Modal>
  );
}
