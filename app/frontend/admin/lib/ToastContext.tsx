import { createContext, useCallback, useContext, useMemo, useRef, useState } from "react";
import type { ReactNode } from "react";

/**
 * 全域 toast（原型 `.toast`：深色浮層、右下進場、自動消退）。
 *
 * 只承載短通知；錯誤細節仍落在欄位級 `error`——toast 是「發生了什麼」，
 * 欄位訊息才是「哪裡要改」。
 */
interface ToastEntry {
  id: number;
  message: string;
}

interface ToastContextValue {
  /** 顯示一則 toast，自動於 3.2 秒後消退（原型時長）。 */
  showToast: (message: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

/** 取得 toast 發送器；Provider 外使用即丟錯（fail fast，不靜默吞通知）。 */
export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) throw new Error("useToast 必須在 ToastProvider 內使用。");
  return context;
}

/**
 * Toast Provider ＋渲染宿主。
 *
 * @param props.children - 應用內容。
 */
export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastEntry[]>([]);
  const nextId = useRef(1);

  const showToast = useCallback((message: string) => {
    const id = nextId.current;
    nextId.current += 1;
    setToasts((current) => [...current, { id, message }]);
    window.setTimeout(() => {
      setToasts((current) => current.filter((toast) => toast.id !== id));
    }, 3200);
  }, []);

  const value = useMemo(() => ({ showToast }), [showToast]);

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div aria-live="polite" className="cl-toast-host">
        {toasts.map((toast) => (
          <div className="cl-toast" key={toast.id} role="status">
            {toast.message}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}
