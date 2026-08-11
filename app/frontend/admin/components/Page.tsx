import type { ReactNode } from "react";

/**
 * Page 版型屬性，對應 `docs/design/23-interaction-css-spec.md` §1–§2。
 */
export interface PageProps {
  /** 頁面唯一主標題。 */
  title: string;
  /** 主標題右側操作。 */
  actions?: ReactNode;
  /** 頁面主內容。 */
  children: ReactNode;
  /** Index 使用 1200px；Detail 使用 998px。 */
  width?: "index" | "detail";
}

/**
 * 呈現後台 Index 或 Detail 頁面骨架。
 *
 * @param props - 標題、操作列、內容與文件定義的版寬。
 * @returns 含單一 h1 與內容區的 page frame。
 */
export function Page({ actions, children, title, width = "index" }: PageProps) {
  return (
    <div className={`cl-page cl-page--${width}`}>
      <header className="cl-page__header">
        <h1>{title}</h1>
        {actions ? <div className="cl-page__actions">{actions}</div> : null}
      </header>
      {children}
    </div>
  );
}
