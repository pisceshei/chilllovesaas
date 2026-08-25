import { ChevronRight } from "lucide-react";
import { Link } from "react-router-dom";

/**
 * 麵包屑（第 29 包新增；本尊變體子頁頁首＝`商品名 › S`，93 §2 實測）。
 *
 * ①這是什麼：一列「上層連結 › 目前位置」。最後一段是**純文字不是連結**——
 *   指向自己的連結對鍵盤與螢幕閱讀器都是雜訊。
 * ②a11y：整體 `<nav aria-label>`，目前段帶 `aria-current="page"`；
 *   分隔符是裝飾性（`aria-hidden`），不進無障礙樹。
 * ③跨功能影響：目前只有變體子頁用；商品／系列詳情頁之後要加也接這一支
 *   （不要各自寫一份 `<span>›</span>`）。
 */
export interface BreadcrumbItem {
  label: string;
  /** 省略＝目前位置（純文字）。 */
  to?: string;
}

export interface BreadcrumbProps {
  items: readonly BreadcrumbItem[];
  /** nav 的 accessible name。 */
  label: string;
}

export function Breadcrumb({ items, label }: BreadcrumbProps) {
  return (
    <nav aria-label={label} className="cl-breadcrumb">
      <ol>
        {items.map((item, index) => {
          const last = index === items.length - 1;
          return (
            <li key={`${item.label}-${index}`}>
              {item.to && !last ? (
                <Link to={item.to}>{item.label}</Link>
              ) : (
                <span aria-current={last ? "page" : undefined}>{item.label}</span>
              )}
              {last ? null : <ChevronRight aria-hidden="true" size={13} />}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
