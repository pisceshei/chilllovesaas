import type { HTMLAttributes, ReactNode } from "react";

/**
 * Card 可用屬性，視覺值對應 `docs/design/23-interaction-css-spec.md` §1。
 */
export interface CardProps extends HTMLAttributes<HTMLElement> {
  /** 卡片內容。 */
  children: ReactNode;
  /** 是否套用文件規定的 16px 卡片內距。 */
  padded?: boolean;
}

/**
 * 呈現後台內容卡片。
 *
 * @param props - section 屬性、內容與 padding 選項。
 * @returns 使用 `--surface`、`--r-card` 與 `--sh` 的語意 section。
 */
export function Card({ children, className = "", padded = false, ...props }: CardProps) {
  const classes = ["cl-card", padded ? "cl-card--padded" : "", className]
    .filter(Boolean)
    .join(" ");

  return (
    <section {...props} className={classes}>
      {children}
    </section>
  );
}
