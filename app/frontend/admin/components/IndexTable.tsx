import { useEffect, useRef, useState } from "react";
import type { KeyboardEvent, ReactNode } from "react";

/**
 * IndexTable 欄位定義，對應 `docs/design/23-interaction-css-spec.md` §3 IndexTable。
 */
export interface IndexTableColumn<Row> {
  /** 欄位穩定識別碼。 */
  key: string;
  /** 表頭文案。 */
  header: string;
  /** 數字欄位可靠右並使用 tabular-nums。 */
  align?: "left" | "right";
  /** 將一筆資料轉為 cell 內容。 */
  render: (row: Row) => ReactNode;
}

/**
 * IndexTable 可用屬性。
 */
export interface IndexTableProps<Row> {
  /** 螢幕閱讀器可讀的表格名稱。 */
  caption: string;
  /** 欄位設定。 */
  columns: readonly IndexTableColumn<Row>[];
  /** 列資料。 */
  rows: readonly Row[];
  /** 取得每列的穩定 key。 */
  getRowKey: (row: Row) => string;
  /** 取得 checkbox accessible name。 */
  getRowLabel: (row: Row) => string;
  /** 點擊或按 Enter/Space 開啟資料列。 */
  onRowActivate?: (row: Row) => void;
  /** 選取集合改變時回傳目前資料列。 */
  onSelectionChange?: (rows: Row[]) => void;
  /** 指定取消列；文字加刪除線但 Badge 不受影響。 */
  isCancelled?: (row: Row) => boolean;
}

/**
 * 呈現含全選三態、鍵盤列操作及 row hover 的資料表。
 *
 * @param props - 欄位、資料列、選取與啟用行為。
 * @returns 符合 §3 IndexTable 狀態與可存取規格的 table。
 */
export function IndexTable<Row>({
  caption,
  columns,
  getRowKey,
  getRowLabel,
  isCancelled,
  onRowActivate,
  onSelectionChange,
  rows,
}: IndexTableProps<Row>) {
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(() => new Set());
  const selectAllRef = useRef<HTMLInputElement>(null);
  const rowKeys = rows.map(getRowKey);
  const allSelected = rowKeys.length > 0 && rowKeys.every((key) => selectedKeys.has(key));
  const someSelected = rowKeys.some((key) => selectedKeys.has(key)) && !allSelected;

  useEffect(() => {
    if (selectAllRef.current) {
      selectAllRef.current.indeterminate = someSelected;
    }
  }, [someSelected]);

  useEffect(() => {
    const availableKeys = new Set(rowKeys);
    setSelectedKeys((current) => {
      const next = new Set([...current].filter((key) => availableKeys.has(key)));
      return next.size === current.size ? current : next;
    });
  }, [rows]);

  const commitSelection = (next: Set<string>) => {
    setSelectedKeys(next);
    onSelectionChange?.(rows.filter((row) => next.has(getRowKey(row))));
  };

  const toggleAll = () => {
    commitSelection(allSelected ? new Set() : new Set(rowKeys));
  };

  const toggleRow = (row: Row) => {
    const key = getRowKey(row);
    const next = new Set(selectedKeys);
    if (next.has(key)) {
      next.delete(key);
    } else {
      next.add(key);
    }
    commitSelection(next);
  };

  const activateFromKeyboard = (event: KeyboardEvent<HTMLTableRowElement>, row: Row) => {
    if (!onRowActivate || (event.key !== "Enter" && event.key !== " ")) return;
    event.preventDefault();
    onRowActivate(row);
  };

  return (
    <div className="cl-index-table-wrap">
      <table className="cl-index-table">
        <caption className="cl-sr-only">{caption}</caption>
        <thead>
          <tr>
            <th className="cl-index-table__select" scope="col">
              <input
                aria-label="全選"
                checked={allSelected}
                className="cl-checkbox"
                onChange={toggleAll}
                ref={selectAllRef}
                type="checkbox"
              />
            </th>
            {columns.map((column) => (
              <th
                className={column.align === "right" ? "cl-index-table__number" : undefined}
                key={column.key}
                scope="col"
              >
                {column.header}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => {
            const key = getRowKey(row);
            const selected = selectedKeys.has(key);
            const interactive = Boolean(onRowActivate);
            const rowClasses = [
              interactive ? "cl-index-table__row--interactive" : "",
              selected ? "cl-index-table__row--selected" : "",
              isCancelled?.(row) ? "cl-index-table__row--cancelled" : "",
            ]
              .filter(Boolean)
              .join(" ");

            return (
              <tr
                className={rowClasses || undefined}
                key={key}
                onClick={interactive ? () => onRowActivate?.(row) : undefined}
                onKeyDown={interactive ? (event) => activateFromKeyboard(event, row) : undefined}
                tabIndex={interactive ? 0 : undefined}
              >
                <td className="cl-index-table__select" onClick={(event) => event.stopPropagation()}>
                  <input
                    aria-label={`選取 ${getRowLabel(row)}`}
                    checked={selected}
                    className="cl-checkbox"
                    onChange={() => toggleRow(row)}
                    type="checkbox"
                  />
                </td>
                {columns.map((column) => (
                  <td
                    className={column.align === "right" ? "cl-index-table__number" : undefined}
                    key={column.key}
                  >
                    {column.render(row)}
                  </td>
                ))}
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
