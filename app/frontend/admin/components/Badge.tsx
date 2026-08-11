import type { HTMLAttributes, ReactNode } from "react";

/**
 * Badge 語意色，對應 `docs/design/23-interaction-css-spec.md` §1、§3。
 */
export type BadgeTone =
  | "default"
  | "success"
  | "warning"
  | "critical"
  | "attention"
  | "info"
  | "ai";

/**
 * Badge 進度 pip：空圈、半圈與實圈分別代表未開始、進行中、完成。
 */
export type BadgeProgress = "empty" | "half" | "full";

/**
 * Badge 可用屬性。
 */
export interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  /** 狀態文案，依規格優先使用過去式單詞。 */
  children: ReactNode;
  /** 語意色。 */
  tone?: BadgeTone;
  /** 可選的進度 pip。 */
  progress?: BadgeProgress;
}

/**
 * 呈現後台狀態徽章。
 *
 * @param props - 文案、語意色與 pip 進度。
 * @returns 使用 §3 語意配色與 20px 高度的狀態徽章。
 */
export function Badge({
  children,
  className = "",
  progress,
  tone = "default",
  ...props
}: BadgeProps) {
  const classes = ["cl-badge", `cl-badge--${tone}`, className].filter(Boolean).join(" ");

  return (
    <span {...props} className={classes}>
      {progress ? (
        <span aria-hidden="true" className={`cl-badge__pip cl-badge__pip--${progress}`} />
      ) : null}
      {children}
    </span>
  );
}
