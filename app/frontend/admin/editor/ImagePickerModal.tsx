import { Search } from "lucide-react";
import { useEffect, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Modal } from "../components/Modal";
import { useT } from "../i18n/I18nContext";

/**
 * image_picker 的檔案庫 modal（E4；100 §3.9：標題＝設定標籤、搜尋 "Search files"、格狀縮圖、空態句、底部 Cancel／Done）。
 *
 * ①資料：既有 `files(first, query, contentType)` connection（thumb／preview URL 由後端衍生）。
 * ②值：選定後寫 `shopify://shopify/files/{filename}`（引擎 `resolve_settings_file` 以檔名對 StoredFile；PR-2 契約）。
 * ③未做（登記）：篩選 chip（File size／Used in／Product）、Sort 與檢視切換、"Upload image"／"Generate image"、
 *   焦點（focal point）——E4b。
 */
export interface ImagePickerModalProps {
  open: boolean;
  title: string;
  onClose: () => void;
  onPick: (value: string) => void;
}

interface FileNode { id: string; filename: string; thumbUrl: string | null; previewUrl: string | null; width: number | null; height: number | null }

const FILES_QUERY = `
  query editorImagePicker($q: String) {
    files(first: 60, query: $q) { edges { node { id filename thumbUrl previewUrl width height } } }
  }
`;

export function ImagePickerModal({ open, title, onClose, onPick }: ImagePickerModalProps) {
  const t = useT();
  const [ query, setQuery ] = useState("");
  const [ items, setItems ] = useState<FileNode[]>([]);
  const [ selected, setSelected ] = useState<string | null>(null);
  const [ loading, setLoading ] = useState(false);

  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    setLoading(true);
    void (async () => {
      try {
        const result = await requestAdminGraphQL<{ files: { edges: { node: FileNode }[] } }, { q?: string }>(
          FILES_QUERY, query.trim() ? { q: query.trim() } : {}, controller.signal);
        setItems(result.files.edges.map((edge) => edge.node).filter((node) => node.width !== null || /\.(png|jpe?g|gif|webp|svg|avif)$/i.test(node.filename)));
      } catch {
        if (!controller.signal.aborted) setItems([]);
      } finally {
        if (!controller.signal.aborted) setLoading(false);
      }
    })();
    return () => controller.abort();
  }, [ open, query ]);

  if (!open) return null;
  const chosen = items.find((item) => item.id === selected);
  return (
    <Modal
      footer={
        <>
          <Button onClick={onClose} size="small" variant="secondary">{t("common.cancel")}</Button>
          <Button disabled={!chosen} onClick={() => chosen && onPick(`shopify://shopify/files/${chosen.filename}`)} size="small" variant="primary">{t("common.done")}</Button>
        </>
      }
      onClose={onClose}
      open={open}
      title={title}
    >
      <div className="cl-imagepicker">
        <div className="cl-editor__menusearch">
          <Search aria-hidden="true" size={14} />
          <input aria-label={t("editor.searchFiles")} data-autofocus onChange={(event) => setQuery(event.target.value)} placeholder={t("editor.searchFiles")} value={query} />
        </div>
        {items.length === 0 && !loading ? (
          <div className="cl-imagepicker__empty">
            <p className="cl-panel__header">{t("editor.noResults")}</p>
            <p className="cl-panel__info">{t("editor.noResultsHint")}</p>
          </div>
        ) : (
          <ul aria-label={t("editor.files")} className="cl-imagepicker__grid" role="listbox">
            {items.map((item) => (
              <li key={item.id}>
                <button
                  aria-selected={item.id === selected}
                  className={`cl-imagepicker__cell${item.id === selected ? " is-selected" : ""}`}
                  onClick={() => setSelected(item.id)}
                  role="option"
                  title={item.filename}
                  type="button"
                >
                  {item.thumbUrl || item.previewUrl ? <img alt="" src={item.thumbUrl ?? item.previewUrl ?? ""} /> : <span className="cl-imagepicker__placeholder" />}
                  <span className="cl-imagepicker__name">{item.filename}</span>
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </Modal>
  );
}
