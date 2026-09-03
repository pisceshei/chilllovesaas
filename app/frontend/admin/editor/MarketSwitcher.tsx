import { Check, ChevronDown, Search, Store } from "lucide-react";
import { useRef, useState } from "react";
import { Popover } from "../components/Popover";
import { useT } from "../i18n/I18nContext";

/**
 * 頂欄市場選擇器（E2；本尊 "Store default ⌄"，`docs/research/100` §1 中 2）。
 *
 * ①這是什麼：店 icon＋"Store default"＋⌄；popover＝搜尋框 "Search markets"＋"Store default ✓"，
 *   之後接 "Customizable market" 小標與市場列。
 * ②本包射程：只做 "Store default" 一項（結構對齊）。市場清單與「切到某市場預覽」需要
 *   Markets 的 GraphQL 面（`markets`／web presence → 前綴解析，`docs/specs/67` §F）——
 *   倉庫尚無該 query，E2 不越權開 API；`markets` prop 預留、傳入即列出（選取只回呼）。
 * ③跨功能影響：`ThemeEditorPage`（`?market=` 狀態預留）、Markets 包（供資料）。
 */
export interface MarketSwitcherProps {
  markets?: { handle: string; name: string }[];
  current?: string | null;
  onSelect?: (handle: string | null) => void;
}

export function MarketSwitcher({ markets = [], current = null, onSelect }: MarketSwitcherProps) {
  const t = useT();
  const anchorRef = useRef<HTMLButtonElement | null>(null);
  const [ open, setOpen ] = useState(false);
  const [ query, setQuery ] = useState("");
  const q = query.trim().toLowerCase();
  const visible = markets.filter((market) => !q || market.name.toLowerCase().includes(q));
  const currentName = markets.find((market) => market.handle === current)?.name ?? t("editor.storeDefault");

  const choose = (handle: string | null) => {
    onSelect?.(handle);
    setOpen(false);
  };

  return (
    <>
      <button
        aria-expanded={open}
        aria-haspopup="menu"
        aria-label={t("editor.marketSwitcher")}
        className="cl-editor__chipbtn"
        onClick={() => setOpen((on) => !on)}
        ref={anchorRef}
        type="button"
      >
        <Store aria-hidden="true" size={14} />
        <span className="cl-editor__chiptext">{currentName}</span>
        <ChevronDown aria-hidden="true" size={12} />
      </button>
      <Popover anchorRef={anchorRef} dismissOnOutsideClick label={t("editor.marketSwitcher")} onClose={() => setOpen(false)} open={open}>
        <div className="cl-editor__menu" role="menu">
          <div className="cl-editor__menusearch">
            <Search aria-hidden="true" size={14} />
            <input
              aria-label={t("editor.searchMarkets")}
              data-autofocus
              onChange={(event) => setQuery(event.target.value)}
              placeholder={t("editor.searchMarkets")}
              value={query}
            />
          </div>
          <ul className="cl-editor__menulist">
            {!q || t("editor.storeDefault").toLowerCase().includes(q) ? (
              <li>
                <button className={`cl-editor__menuitem${current === null ? " is-current" : ""}`} onClick={() => choose(null)} role="menuitemradio" aria-checked={current === null} type="button">
                  <Store aria-hidden="true" size={14} />
                  <span className="cl-editor__menutext">{t("editor.storeDefault")}</span>
                  {current === null ? <Check aria-hidden="true" size={14} /> : null}
                </button>
              </li>
            ) : null}
            {visible.length > 0 ? <li className="cl-editor__menuheading">{t("editor.customizableMarkets")}</li> : null}
            {visible.map((market) => (
              <li key={market.handle}>
                <button className={`cl-editor__menuitem${current === market.handle ? " is-current" : ""}`} onClick={() => choose(market.handle)} role="menuitemradio" aria-checked={current === market.handle} type="button">
                  <span className="cl-editor__menutext">{market.name}</span>
                  {current === market.handle ? <Check aria-hidden="true" size={14} /> : null}
                </button>
              </li>
            ))}
          </ul>
        </div>
      </Popover>
    </>
  );
}
