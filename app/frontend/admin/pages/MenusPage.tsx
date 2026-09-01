import { Plus, Trash2 } from "lucide-react";
import { useCallback, useEffect, useState } from "react";
import { AdminGraphQLError, requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";

/**
 * 內容 › 選單（步 14b；98 §4 admin 實測形——列表（Menu/Menu items 欄）＋選單
 * 編輯（項目列＋inline 新增）。
 *
 * 🔴 儲存語義＝menuUpdate **整棵替換**（98 §3 官方）：本地樹是唯一真相，Save
 * 一次送出。巢狀 ≤3 層（官方 linklist.levels 上限）；資源型項目 v1 以 GID 直填
 * （picker 隨後續包——91 §3.64）。
 */
const MENUS_QUERY = `
  query menuList {
    menus {
      id title handle isDefault
      items { id title type url resourceId items { id title type url resourceId items { id title type url resourceId } } }
    }
  }
`;

const MENU_UPDATE = `
  mutation menuUpdate($id: ID!, $items: [MenuItemInput!]!) {
    menuUpdate(id: $id, items: $items) {
      menu { id }
      userErrors { field message code }
    }
  }
`;

const MENU_CREATE = `
  mutation menuCreate($title: String!, $handle: String!, $items: [MenuItemInput!]!) {
    menuCreate(title: $title, handle: $handle, items: $items) {
      menu { id }
      userErrors { field message code }
    }
  }
`;

const MENU_DELETE = `
  mutation menuDelete($id: ID!) {
    menuDelete(id: $id) { deletedMenuId userErrors { field message code } }
  }
`;

const ITEM_KINDS = [
  "HTTP", "FRONTPAGE", "SEARCH", "CATALOG", "COLLECTIONS",
  "COLLECTION", "PRODUCT", "PAGE", "BLOG", "ARTICLE",
] as const;
type ItemKind = (typeof ITEM_KINDS)[number];
const RESOURCE_KINDS: readonly ItemKind[] = [ "COLLECTION", "PRODUCT", "PAGE", "BLOG", "ARTICLE" ];

interface EditItem {
  title: string;
  type: ItemKind;
  url: string;
  resourceId: string;
  items: EditItem[];
}

interface MenuRow {
  id: string;
  title: string;
  handle: string;
  isDefault: boolean;
  items: ServerItem[];
}

interface ServerItem {
  id: string;
  title: string;
  type: ItemKind;
  url: string | null;
  resourceId: string | null;
  items?: ServerItem[];
}

interface MenusData {
  menus: MenuRow[];
}

interface MutationErrors {
  userErrors: { field: string[] | null; message: string; code: string }[];
}

function toEdit(items: ServerItem[] | undefined): EditItem[] {
  return (items ?? []).map((item) => ({
    title: item.title,
    type: item.type,
    url: item.url ?? "",
    resourceId: item.resourceId ?? "",
    items: toEdit(item.items),
  }));
}

function toInput(items: EditItem[]): Record<string, unknown>[] {
  return items.map((item) => ({
    title: item.title,
    type: item.type,
    url: item.type === "HTTP" ? item.url : null,
    resourceId: RESOURCE_KINDS.includes(item.type) ? item.resourceId : null,
    items: toInput(item.items),
  }));
}

export function MenusPage() {
  const t = useT();
  const { showToast } = useToast();
  const [data, setData] = useState<MenusData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [tree, setTree] = useState<EditItem[]>([]);
  const [newMenuTitle, setNewMenuTitle] = useState("");

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      setData(await requestAdminGraphQL<MenusData, Record<string, never>>(MENUS_QUERY, {}, signal));
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("common.loading"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const run = useCallback(
    async (query: string, variables: Record<string, unknown>, successMessage: string) => {
      if (busy) return false;
      setBusy(true);
      try {
        const result = await requestAdminGraphQL<Record<string, MutationErrors>, Record<string, unknown>>(query, variables);
        const payload = Object.values(result)[0];
        if (payload.userErrors.length > 0) {
          showToast(payload.userErrors[0].message);
          return false;
        }
        showToast(successMessage);
        await load();
        return true;
      } catch (reason: unknown) {
        showToast(reason instanceof AdminGraphQLError || reason instanceof Error ? reason.message : t("menus.actionFailed"));
        return false;
      } finally {
        setBusy(false);
      }
    },
    [busy, load, showToast, t],
  );

  const select = (row: MenuRow) => {
    setSelectedId(row.id);
    setTree(toEdit(row.items));
  };

  /** path＝索引鏈（[]＝頂層）；不可變更新整棵樹。 */
  const mutateTree = (updater: (draft: EditItem[]) => EditItem[]) => {
    setTree((current) => updater(structuredClone(current)));
  };

  const addAt = (path: number[]) => {
    mutateTree((draft) => {
      let target = draft;
      for (const index of path) target = target[index].items;
      target.push({ title: "", type: "HTTP", url: "", resourceId: "", items: [] });
      return draft;
    });
  };

  const removeAt = (path: number[]) => {
    mutateTree((draft) => {
      let target = draft;
      for (const index of path.slice(0, -1)) target = target[index].items;
      target.splice(path[path.length - 1], 1);
      return draft;
    });
  };

  const patchAt = (path: number[], patch: Partial<EditItem>) => {
    mutateTree((draft) => {
      let target = draft;
      for (const index of path.slice(0, -1)) target = target[index].items;
      Object.assign(target[path[path.length - 1]], patch);
      return draft;
    });
  };

  const renderItems = (items: EditItem[], path: number[], depth: number) => (
    <ul className="cl-locale-list" style={{ marginInlineStart: depth * 16 }}>
      {items.map((item, index) => {
        const itemPath = [ ...path, index ];
        const key = itemPath.join("-");
        return (
          <li key={key}>
            <div className="cl-locale-row">
              <input
                aria-label={t("menus.itemTitle")}
                className="cl-field__input"
                onChange={(event) => patchAt(itemPath, { title: event.target.value })}
                value={item.title}
              />
              <select
                aria-label={t("menus.itemType")}
                className="cl-field__input"
                onChange={(event) => patchAt(itemPath, { type: event.target.value as ItemKind })}
                value={item.type}
              >
                {ITEM_KINDS.map((kind) => (
                  <option key={kind} value={kind}>{t(`menus.kind.${kind}`)}</option>
                ))}
              </select>
              {item.type === "HTTP" && (
                <input
                  aria-label={t("menus.itemUrl")}
                  className="cl-field__input"
                  onChange={(event) => patchAt(itemPath, { url: event.target.value })}
                  placeholder="https://"
                  value={item.url}
                />
              )}
              {RESOURCE_KINDS.includes(item.type) && (
                <input
                  aria-label={t("menus.itemResource")}
                  className="cl-field__input"
                  onChange={(event) => patchAt(itemPath, { resourceId: event.target.value })}
                  placeholder="gid://chilllove/…"
                  value={item.resourceId}
                />
              )}
              {depth < 2 && (
                <Button onClick={() => addAt(itemPath)} size="small" variant="ghost">
                  <Plus aria-hidden="true" size={13} /> {t("menus.addChild")}
                </Button>
              )}
              <Button onClick={() => removeAt(itemPath)} size="small" variant="ghost">
                <Trash2 aria-hidden="true" size={13} /> {t("common.delete")}
              </Button>
            </div>
            {item.items.length > 0 && renderItems(item.items, itemPath, depth + 1)}
          </li>
        );
      })}
    </ul>
  );

  if (error) {
    return (
      <Page title={t("menus.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (!data) {
    return (
      <Page title={t("menus.title")}>
        <Card padded>
          <p className="cl-card-note">{t("common.loading")}</p>
        </Card>
      </Page>
    );
  }

  const selected = data.menus.find((menu) => menu.id === selectedId) ?? null;

  return (
    <Page title={t("menus.title")}>
      <Card padded>
        <h3>{t("menus.listTitle")}</h3>
        <div className="cl-locale-add">
          <input
            aria-label={t("menus.newTitle")}
            className="cl-field__input"
            onChange={(event) => setNewMenuTitle(event.target.value)}
            value={newMenuTitle}
          />
          <Button
            disabled={busy || !newMenuTitle}
            onClick={() => {
              const handle = newMenuTitle.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
              void run(MENU_CREATE, { title: newMenuTitle, handle, items: [] }, t("menus.createDone")).then((ok) => {
                if (ok) setNewMenuTitle("");
              });
            }}
            variant="primary"
          >
            <Plus aria-hidden="true" size={14} /> {t("menus.add")}
          </Button>
        </div>
        <ul className="cl-locale-list">
          {data.menus.map((row) => (
            <li className="cl-locale-row" key={row.id}>
              <button className="cl-locale-row__name" onClick={() => select(row)} type="button">
                {row.title} <code>{row.handle}</code>
              </button>
              {/* 98 §4：三個預設選單不可刪（官方 default menu 語義） */}
              {row.isDefault ? (
                <Badge progress="full" tone="info">{t("menus.default")}</Badge>
              ) : (
                <span className="cl-locale-row__actions">
                  <Button
                    disabled={busy}
                    onClick={() => void run(MENU_DELETE, { id: row.id }, t("menus.deleteDone"))}
                    size="small"
                    variant="ghost"
                  >
                    <Trash2 aria-hidden="true" size={13} /> {t("common.delete")}
                  </Button>
                </span>
              )}
            </li>
          ))}
        </ul>
      </Card>

      {selected && (
        <Card padded>
          <h3>{t("menus.editTitle", { title: selected.title })}</h3>
          <p className="cl-card-note">{t("menus.replaceHint")}</p>
          {renderItems(tree, [], 0)}
          <Button onClick={() => addAt([])} size="small">
            <Plus aria-hidden="true" size={13} /> {t("menus.addItem")}
          </Button>{" "}
          <Button
            disabled={busy}
            onClick={() => void run(MENU_UPDATE, { id: selected.id, items: toInput(tree) }, t("menus.saveDone"))}
            variant="primary"
          >
            {t("common.save")}
          </Button>
        </Card>
      )}
    </Page>
  );
}
