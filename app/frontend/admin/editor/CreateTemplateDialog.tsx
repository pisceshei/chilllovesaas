import { useEffect, useId, useRef, useState } from "react";
import { Button } from "../components/Button";
import { Modal } from "../components/Modal";
import { useT } from "../i18n/I18nContext";

/**
 * 建立模板對話框（E2；本尊 "Create a template" modal，`docs/research/100` §1.1）。
 *
 * ①這是什麼：說明句＋Name（右側 "n/25" 計數）＋Based on（select）＋Cancel／Create template。
 * ②值域：名稱 1–25 字、只允許字母／數字／連字號／底線（成為 `templates/{type}.{name}.json`
 *   的檔名段；本尊的合法字元集未取得，我方取檔名安全集並登記）；同名擋（`existing`）。
 * ③行為：Create ⇒ `onCreate(name, baseKey)`（呼叫端讀 base 模板 JSON → themeTemplateUpsert
 *   → 切到新模板）；`busy` 期間鎖鈕與關閉。
 * ④跨功能影響：`TemplateSwitcher`（入口）、`ThemeEditorPage`（mutation 與導航）。
 */
export interface CreateTemplateDialogProps {
  open: boolean;
  type: string | null;
  /** 可作為基礎的模板 key（預設模板＋同型替代模板）。 */
  baseKeys: string[];
  /** 已存在的模板 key（同名擋）。 */
  existing: string[];
  busy?: boolean;
  onCancel: () => void;
  onCreate: (name: string, baseKey: string) => void;
}

const NAME_RE = /^[A-Za-z0-9_-]{1,25}$/;

export function CreateTemplateDialog({ open, type, baseKeys, existing, busy = false, onCancel, onCreate }: CreateTemplateDialogProps) {
  const t = useT();
  const nameId = useId();
  const baseId = useId();
  const [ name, setName ] = useState("");
  const [ base, setBase ] = useState("");

  // 🔴 只在「開啟」那一刻重設（依 `open` 不依 `baseKeys`）：呼叫端每次 render 都可能給新陣列，
  //   若把它列進依賴，使用者每打一個字表單就被清空（實測抓到的第一個回歸）。
  const baseKeysRef = useRef(baseKeys);
  baseKeysRef.current = baseKeys;
  useEffect(() => {
    if (open) {
      setName("");
      setBase(baseKeysRef.current[0] ?? "");
    }
  }, [ open ]);

  const duplicate = type ? existing.includes(`${type}.${name}`) : false;
  const valid = NAME_RE.test(name) && !duplicate && base !== "";
  const baseLabel = (key: string) => {
    const dot = key.indexOf(".");
    return dot < 0 ? t(`editor.tplDefault.${key}`) : key.slice(dot + 1);
  };

  return (
    <Modal
      dismissable={!busy}
      footer={
        <>
          <Button disabled={busy} onClick={onCancel}>{t("common.cancel")}</Button>
          <Button disabled={!valid} loading={busy} onClick={() => onCreate(name, base)} variant="primary">
            {t("editor.createTemplate")}
          </Button>
        </>
      }
      onClose={onCancel}
      open={open}
      title={t("editor.createTemplateTitle")}
    >
      <p className="cl-card-note">{t("editor.createTemplateHelp")}</p>
      <div className="cl-field">
        <label className="cl-field__label" htmlFor={nameId}>{t("editor.templateName")}</label>
        <div className="cl-editor__namefield">
          <input
            className="cl-field__input"
            id={nameId}
            maxLength={25}
            onChange={(event) => setName(event.target.value)}
            value={name}
          />
          <span aria-hidden="true" className="cl-editor__namecount">{t("editor.templateNameCount", { used: name.length })}</span>
        </div>
        {duplicate ? <p className="cl-field__error" role="alert">{t("editor.templateExists")}</p> : null}
      </div>
      <div className="cl-field">
        <label className="cl-field__label" htmlFor={baseId}>{t("editor.templateBasedOn")}</label>
        <select className="cl-field__input" id={baseId} onChange={(event) => setBase(event.target.value)} value={base}>
          {baseKeys.map((key) => <option key={key} value={key}>{baseLabel(key)}</option>)}
        </select>
      </div>
    </Modal>
  );
}
