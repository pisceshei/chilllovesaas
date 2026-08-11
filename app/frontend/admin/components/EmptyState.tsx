import type { ReactNode } from "react";

/**
 * EmptyState 可用屬性，對應 `docs/design/23-interaction-css-spec.md` §3 EmptyState。
 */
export interface EmptyStateProps {
  /** 裝飾性 Lucide 圖示。 */
  illustration: ReactNode;
  /** 粗體空狀態標題。 */
  title: string;
  /** 一句可採取行動的說明。 */
  description: string;
  /** 主要 CTA。 */
  action: ReactNode;
}

/**
 * 呈現置中的列表空狀態。
 *
 * @param props - 圖示、標題、說明與 CTA。
 * @returns 符合 §3 的空狀態內容。
 */
export function EmptyState({ action, description, illustration, title }: EmptyStateProps) {
  return (
    <div className="cl-empty-state">
      <div aria-hidden="true" className="cl-empty-state__illustration">
        {illustration}
      </div>
      <h2>{title}</h2>
      <p>{description}</p>
      <div className="cl-empty-state__action">{action}</div>
    </div>
  );
}
