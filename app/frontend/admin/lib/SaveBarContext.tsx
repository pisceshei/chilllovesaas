import { createContext, useContext, useMemo, useState } from "react";
import type { ReactNode } from "react";

/**
 * SaveBar 狀態橋——頁面（表單持有者）與 AdminShell topbar（渲染位置）之間的契約。
 *
 * 原型行為（DOCS `savebar`）：dirty 時 SaveBar **取代整條 topbar 搜尋列**
 * （不疊加）；組成＝「未儲存的變更」＋捨棄＋儲存；儲存中 disabled。
 * 頁面透過 `register` 提供 save/discard handler，離開頁面時 `register(null)` 清除。
 */
export interface SaveBarState {
  /** 是否有未儲存變更（決定 SaveBar 是否取代搜尋列）。 */
  dirty: boolean;
  /** 儲存進行中（雙按鈕 disabled、儲存鈕顯示「儲存中…」）。 */
  saving: boolean;
  /** 觸發儲存（與頁首「儲存」同一入口——雙提交入口，DOCS savebar）。 */
  onSave: () => void;
  /** 捨棄變更（還原快照，無二次確認 modal）。 */
  onDiscard: () => void;
  /** shake 動畫的觸發序號（guardNav 攔截時遞增，SaveBar 播 cl-shake）。 */
  shakeSignal: number;
}

interface SaveBarContextValue {
  state: SaveBarState | null;
  register: (state: SaveBarState | null) => void;
}

const SaveBarContext = createContext<SaveBarContextValue | null>(null);

/** AdminShell 讀取現行 SaveBar 狀態（無表單頁為 null）。 */
export function useSaveBarState(): SaveBarState | null {
  const context = useContext(SaveBarContext);
  if (!context) throw new Error("useSaveBarState 必須在 SaveBarProvider 內使用。");
  return context.state;
}

/** 表單頁註冊／清除 SaveBar。 */
export function useSaveBarRegister(): (state: SaveBarState | null) => void {
  const context = useContext(SaveBarContext);
  if (!context) throw new Error("useSaveBarRegister 必須在 SaveBarProvider 內使用。");
  return context.register;
}

/** SaveBar Provider（包在 AdminShell 外層）。 */
export function SaveBarProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<SaveBarState | null>(null);
  const value = useMemo(() => ({ state, register: setState }), [state]);
  return <SaveBarContext.Provider value={value}>{children}</SaveBarContext.Provider>;
}
