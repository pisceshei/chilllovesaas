import { LoaderCircle } from "lucide-react";
import type { ButtonHTMLAttributes, ReactNode, Ref } from "react";
import { useT } from "../i18n/I18nContext";

/**
 * Button 的視覺型態，對應 `docs/design/23-interaction-css-spec.md` §3 Button。
 */
export type ButtonVariant = "primary" | "secondary" | "ghost" | "critical";

/**
 * Button 可用屬性。
 *
 * @remarks
 * 高度、圓角、focus ring、disabled 與 loading 狀態皆依
 * `docs/design/23-interaction-css-spec.md` §1、§3。
 */
export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  /** 按鈕內容。 */
  children: ReactNode;
  /** 視覺型態；預設為次要按鈕。 */
  variant?: ButtonVariant;
  /** 是否使用文件定義的 28px 小尺寸。 */
  size?: "default" | "small";
  /** 顯示處理中狀態並阻止重複操作。 */
  loading?: boolean;
  /** loading 時供使用者與輔助科技讀取的文案。 */
  loadingLabel?: string;
  /** 底層 <button> 的 ref（React 19 ref-as-prop；modal 焦點還原用）。 */
  ref?: Ref<HTMLButtonElement>;
}

/**
 * 呈現後台共用按鈕。
 *
 * @param props - 原生 button 屬性與後台互動狀態。
 * @returns 可鍵盤操作且 loading 時自動禁用的按鈕。
 */
export function Button({
  children,
  className = "",
  disabled,
  loading = false,
  loadingLabel,
  size = "default",
  type = "button",
  variant = "secondary",
  ...props
}: ButtonProps) {
  const t = useT();
  const resolvedLoadingLabel = loadingLabel ?? t("common.processing");
  const classes = [
    "cl-button",
    `cl-button--${variant}`,
    size === "small" ? "cl-button--small" : "",
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <button
      {...props}
      aria-busy={loading || undefined}
      className={classes}
      disabled={disabled || loading}
      type={type}
    >
      {loading ? (
        <>
          <LoaderCircle aria-hidden="true" className="cl-button__spinner" size={14} />
          {resolvedLoadingLabel}
        </>
      ) : (
        children
      )}
    </button>
  );
}
