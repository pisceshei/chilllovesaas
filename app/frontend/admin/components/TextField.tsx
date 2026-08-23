import { useId } from "react";
import type { InputHTMLAttributes, Ref } from "react";

/**
 * TextField 可用屬性，對應 `docs/design/23-interaction-css-spec.md` §3 輸入框。
 */
export interface TextFieldProps
  extends Omit<InputHTMLAttributes<HTMLInputElement>, "aria-invalid" | "size"> {
  /** 可見或僅供螢幕閱讀器使用的標籤。 */
  label: string;
  /** 隱藏視覺標籤但保留 accessible name。 */
  labelHidden?: boolean;
  /** 輔助說明；無錯誤時與 input 關聯。 */
  hint?: string;
  /** 驗證錯誤；出現時自動套用紅框及 aria-invalid。 */
  error?: string;
  /** 轉發給原生 input（React 19 ref-as-prop；驗證失敗 focus 首個壞欄位用）。 */
  ref?: Ref<HTMLInputElement>;
}

/**
 * 呈現含標籤、提示與可存取錯誤訊息的文字欄位。
 *
 * @param props - 原生 input 屬性與欄位說明。
 * @returns 符合 §3 focus/error 狀態的表單控制項。
 */
export function TextField({
  error,
  hint,
  id,
  label,
  labelHidden = false,
  className = "",
  ref,
  ...props
}: TextFieldProps) {
  const generatedId = useId();
  const inputId = id ?? generatedId;
  const hintId = hint ? `${inputId}-hint` : undefined;
  const errorId = error ? `${inputId}-error` : undefined;
  const describedBy = [errorId, error ? undefined : hintId].filter(Boolean).join(" ") || undefined;

  return (
    <div className={`cl-field ${className}`.trim()}>
      <label className={labelHidden ? "cl-sr-only" : "cl-field__label"} htmlFor={inputId}>
        {label}
      </label>
      <input
        {...props}
        ref={ref}
        aria-describedby={describedBy}
        aria-invalid={error ? true : undefined}
        className={`cl-field__input ${error ? "cl-field__input--error" : ""}`.trim()}
        id={inputId}
      />
      {error ? (
        <p className="cl-field__error" id={errorId}>
          {error}
        </p>
      ) : hint ? (
        <p className="cl-field__hint" id={hintId}>
          {hint}
        </p>
      ) : null}
    </div>
  );
}
