import { useId } from "react";
import type { ReactNode } from "react";
import { useT } from "../i18n/I18nContext";
import { Button } from "./Button";
import { Modal } from "./Modal";

/**
 * 破壞性／不可逆動作的確認框（第 4 包；三消費者議定接口＝
 * `title`／`danger`／`onConfirm`，整合規格 §4-4）。
 *
 * ①這是什麼：Modal 原語上的雙鈕確認層——取消（次要）＋確認（primary／critical）。
 * ②行為契約：
 *   - `busy` 時雙鈕鎖定、確認鈕轉 loading、Escape／scrim／× 全鎖（Modal
 *     `dismissable=false`）——防雙擊與進行中逃逸。
 *   - 初始焦點在面板本體（Modal 預設）：Enter 不會誤觸確認——破壞性動作
 *     必須是一次明確的點擊或 Tab 後的 Enter。
 *   - `message` 要寫具體後果（刪什麼、影響誰），不寫空泛的「確定嗎？」。
 * ③怎麼做出來：Modal 原語＋footer 雙鈕；`message` 段落以 `describedById`
 *   掛進 dialog 的 aria-describedby（SR 開框即讀出後果）。
 * ④跨功能影響：捨棄變更＋封存商品（本包接線）；第 27 包媒體刪除、第 28 包
 *   檔案刪除（引用計數說明放 `message`）。觸發鈕會隨開框 unmount 的呼叫端
 *   必須傳 `restoreFocusTo`（Modal 契約）。
 */
export interface ConfirmDialogProps {
  /** 是否顯示。 */
  open: boolean;
  /** 標題（問句形態，如「封存商品？」）。 */
  title: string;
  /** 內文——具體後果說明。 */
  message: ReactNode;
  /** 確認鈕文案（動詞，如「封存」「捨棄變更」）。 */
  confirmLabel: string;
  /** 取消鈕文案；預設 `common.cancel`。 */
  cancelLabel?: string;
  /** true＝確認鈕 critical（紅）；預設 primary。 */
  danger?: boolean;
  /** 進行中：雙鈕鎖定＋確認鈕 loading＋關閉途徑全鎖。 */
  busy?: boolean;
  /** 確認 handler（busy 轉場由呼叫端管理）。 */
  onConfirm: () => void;
  /** 取消／關閉 handler。 */
  onCancel: () => void;
  /** 焦點還原目標（觸發鈕會隨開框 unmount 時必傳；直通 Modal）。 */
  restoreFocusTo?: Parameters<typeof Modal>[0]["restoreFocusTo"];
}

/**
 * 呈現確認對話框。
 *
 * @param props - 文案、危險層級與雙鈕 handler。
 * @returns 以 Modal 為底的確認框。
 */
export function ConfirmDialog({
  open,
  title,
  message,
  confirmLabel,
  cancelLabel,
  danger = false,
  busy = false,
  onConfirm,
  onCancel,
  restoreFocusTo,
}: ConfirmDialogProps) {
  const t = useT();
  const messageId = useId();
  return (
    <Modal
      describedById={messageId}
      dismissable={!busy}
      restoreFocusTo={restoreFocusTo}
      footer={
        <>
          <Button disabled={busy} onClick={onCancel}>
            {cancelLabel ?? t("common.cancel")}
          </Button>
          <Button loading={busy} onClick={onConfirm} variant={danger ? "critical" : "primary"}>
            {confirmLabel}
          </Button>
        </>
      }
      onClose={onCancel}
      open={open}
      title={title}
    >
      <p className="cl-modal__message" id={messageId}>
        {message}
      </p>
    </Modal>
  );
}
