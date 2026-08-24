import { ImageOff, Search } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { RefObject } from "react";
import { Button } from "./Button";
import { EmptyState } from "./EmptyState";
import { Modal } from "./Modal";
import { useT } from "../i18n/I18nContext";
import { fetchFiles, formatBytes } from "../lib/filesApi";
import type { FileNode } from "../lib/filesApi";

/**
 * 「選取現有檔案」modal（第 28 包；整合規格 §1.7 的第三個 Modal 消費者）。
 *
 * ①這是什麼：從檔案庫挑既有檔案掛到商品上。挑完回傳 **file GID 陣列**給呼叫端，
 *   由呼叫端送 `productCreateMedia` 的 `fileId` 分支——那條分支第 27 包就做好了，
 *   本元件是它的第一個使用者。
 * ②**多選**：本尊的選檔器支援批次（Files 頁「Select up to 20 files」同一批次上限），
 *   我方沿用 `content.files_upload_batch_max`。選了幾個顯示在動作鈕上。
 * ③🔴 **只列 READY 的圖**：處理中的檔沒有衍生尺寸（縮圖是 null），掛上去商品頁
 *   會出現一格永久占位；失敗的檔更是連原圖都不保證能解。⇒ 篩掉是刻意的，
 *   不是漏了 `status` 篩選。使用者要看全部狀態請去檔案庫頁。
 * ④跨功能影響：`MediaCard`（商品頁）是目前唯一呼叫者；第 29 包變體子頁的圖格
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
  const [files, setFiles] = useState<FileNode[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<string[]>([]);
  const [search, setSearch] = useState("");
  const [debounced, setDebounced] = useState("");

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

  const toggle = useCallback((id: string) => {
    setSelected((current) => {
      if (current.includes(id)) return current.filter((item) => item !== id);
      // 已達上限就不再加（動作鈕旁的提示會說明還能選幾個）
      if (current.length >= maxSelectable) return current;
      return [ ...current, id ];
    });
  }, [maxSelectable]);

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
      <Button onClick={onClose} variant="secondary">{t("common.cancel")}</Button>
      <Button disabled={selected.length === 0} onClick={confirm} variant="primary">
        {t("files.picker.confirm", { count: selected.length })}
      </Button>
    </>
  ), [atLimit, confirm, maxSelectable, onClose, selected.length, t]);

  return (
    <Modal
      footer={footer}
      onClose={onClose}
      open={open}
      restoreFocusTo={restoreFocusTo}
      title={t("files.picker.title")}
    >
      <div className="cl-file-picker">
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
