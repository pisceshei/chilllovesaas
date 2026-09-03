import { ChevronsUpDown, Search, SquarePen } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";

/**
 * 左欄「Preview 資源列」（E3；本尊 100 §2.1：資源模板時標題下多一列 "Preview / Acme Tee ⌃⌄ ✎"）。
 *
 * ①這是什麼：小灰字 "Preview"＋當前預覽資源標題＋stepper icon；點列 ⇒ popover（搜尋＋資源清單）；
 *   右端鉛筆 ⇒ 開該資源的後台編輯頁（本尊是 modal 內嵌整個產品表單；我方先連到編輯頁，登記差異）。
 * ②資料：依模板型打既有 connection（products／collections／pages／articles 帶 `query`；blogs 全列），
 *   取 title＋handle；選取 ⇒ `onPick(path)` 由呼叫端寫 `previewPath`。
 * ③跨功能影響：`ThemeEditorPage`（`previewPath` 狀態）、E5 picker（同一 popover 形態）。
 */
export interface PreviewResourceRowProps {
  templateType: "product" | "collection" | "page" | "blog" | "article";
  themeId: string;
  currentPath: string;
  onPick: (path: string) => void;
}

interface Resource { id: string; title: string; handle: string; path: string; editHref: string | null }

const QUERIES: Record<PreviewResourceRowProps["templateType"], string> = {
  product: `query editorPreviewProducts($q: String) { products(first: 25, query: $q) { nodes { id title handle } } }`,
  collection: `query editorPreviewCollections { collections(first: 25) { nodes { id title handle } } }`,
  page: `query editorPreviewPages($q: String) { pages(first: 25, query: $q) { nodes { id title handle } } }`,
  blog: `query editorPreviewBlogs { blogs { id title handle } }`,
  // ArticleType 只有 blogId（無 blog 物件）⇒ 同一查詢帶 blogs，前端以 blogId 對 handle
  article: `query editorPreviewArticles($q: String) { articles(first: 25, query: $q) { nodes { id title handle blogId } } blogs { id handle } }`,
};

function legacyId(gid: string): string {
  return gid.split("/").pop() ?? "";
}

export function PreviewResourceRow({ templateType, currentPath, onPick }: PreviewResourceRowProps) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  const [ query, setQuery ] = useState("");
  const [ items, setItems ] = useState<Resource[]>([]);

  useEffect(() => {
    if (!open) return;
    const controller = new AbortController();
    void (async () => {
      try {
        const result = await requestAdminGraphQL<Record<string, unknown>, { q?: string }>(
          QUERIES[templateType], query.trim() ? { q: query.trim() } : {}, controller.signal);
        type Node = { id: string; title: string; handle: string; blogId?: string };
        const raw: Node[] = (templateType === "blog"
          ? (result.blogs as Node[] | undefined)
          : (result[`${templateType}s`] as { nodes: Node[] } | undefined)?.nodes) ?? [];
        const blogHandles = new Map(((result.blogs as { id: string; handle: string }[] | undefined) ?? [])
          .map((blog) => [ blog.id, blog.handle ]));
        setItems(raw.map((node) => {
          const path = templateType === "product" ? `/products/${node.handle}`
            : templateType === "collection" ? `/collections/${node.handle}`
              : templateType === "page" ? `/pages/${node.handle}`
                : templateType === "blog" ? `/blogs/${node.handle}`
                  : `/blogs/${blogHandles.get(node.blogId ?? "") ?? ""}/${node.handle}`;
          const editHref = templateType === "product" ? `/admin/products/${legacyId(node.id)}`
            : templateType === "collection" ? `/admin/collections/${legacyId(node.id)}` : null;
          return { id: node.id, title: node.title, handle: node.handle, path, editHref };
        }));
      } catch {
        if (!controller.signal.aborted) setItems([]);
      }
    })();
    return () => controller.abort();
  }, [ open, query, templateType ]);

  const current = items.find((item) => item.path === currentPath);
  const currentTitle = current?.title ?? currentPath.split("/").filter(Boolean).pop() ?? "";

  return (
    <div className="cl-tree__previewrow">
      <button
        aria-expanded={open}
        aria-haspopup="listbox"
        aria-label={t("editor.previewLabel")}
        className="cl-tree__previewbtn"
        onClick={() => setOpen((on) => !on)}
        ref={anchorRef}
        type="button"
      >
        <span className="cl-tree__previewlabel">{t("editor.previewLabel")}</span>
        <span className="cl-tree__previewtitle">{currentTitle}</span>
        <ChevronsUpDown aria-hidden="true" className="cl-tree__previewstep" size={12} />
      </button>
      {current?.editHref ? (
        <a aria-label={t("editor.editResource")} className="cl-tree__op is-persistent" href={current.editHref} rel="noreferrer" target="_blank">
          <SquarePen aria-hidden="true" size={14} />
        </a>
      ) : null}
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={t("editor.previewLabel")} onClose={() => setOpen(false)} open={open}>
        <div className="cl-editor__menu">
          <div className="cl-editor__menusearch">
            <Search aria-hidden="true" size={14} />
            <input
              aria-label={t("editor.searchResources")}
              data-autofocus
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("editor.searchResources")}
              value={query}
            />
          </div>
          <ul className="cl-editor__menulist" role="listbox">
            {items.map((item) => (
              <li key={item.id}>
                <button
                  aria-selected={item.path === currentPath}
                  className={`cl-editor__menuitem${item.path === currentPath ? " is-current" : ""}`}
                  onClick={() => { onPick(item.path); setOpen(false); }}
                  role="option"
                  type="button"
                >
                  <span className="cl-editor__menutext">{item.title}</span>
                </button>
              </li>
            ))}
          </ul>
        </div>
      </Popover>
    </div>
  );
}
