import { useCallback, useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { Modal } from "../components/Modal";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";

/**
 * 折扣列表（G6 步 9b；實測 2026-09-01 對位）：空態逐字＋Create discount →
 * 型別選擇 modal 恰四值（Amount off products／Buy X get Y〔⚪ coming soon〕／
 * Amount off order／Free shipping）。列欄：Title/Method/Type/Used/Status。
 */
const DISCOUNTS_QUERY = `
  query discountList($after: String) {
    discounts(first: 50, after: $after) {
      nodes { id title code method discountClass valueType basisPoints valueCents usageLimit timesUsed status }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

interface DiscountRow {
  id: string;
  title: string;
  code: string | null;
  method: string;
  discountClass: string;
  valueType: string;
  basisPoints: number | null;
  valueCents: number | null;
  usageLimit: number | null;
  timesUsed: number;
  status: string;
}

export function DiscountsPage() {
  const t = useT();
  const navigate = useNavigate();
  const [rows, setRows] = useState<DiscountRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pickerOpen, setPickerOpen] = useState(false);
  const createRef = useRef<HTMLButtonElement | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const data = await requestAdminGraphQL<{ discounts: { nodes: DiscountRow[] } }, { after: string | null }>(
        DISCOUNTS_QUERY, { after: null }, signal
      );
      setRows(data.discounts.nodes);
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("discounts.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const statusBadge = (status: string) =>
    status === "active" ? <Badge progress="full" tone="success">{t("discounts.status.active")}</Badge>
      : status === "scheduled" ? <Badge progress="half" tone="attention">{t("discounts.status.scheduled")}</Badge>
        : status === "expired" ? <Badge progress="empty" tone="default">{t("discounts.status.expired")}</Badge>
          : status === "archived" ? <Badge progress="empty" tone="default">{t("discounts.status.archived")}</Badge>
            : <Badge progress="empty" tone="default">{t("discounts.status.draft")}</Badge>;

  const valueLabel = (row: DiscountRow) =>
    row.valueType === "percentage" && row.basisPoints !== null
      ? `${row.basisPoints / 100}%`
      : row.valueCents !== null ? `$${(row.valueCents / 100).toFixed(2)}` : "—";

  const columns: readonly IndexTableColumn<DiscountRow>[] = [
    { key: "title", header: t("discounts.col.title"),
      render: (row) => <span><strong>{row.code ?? row.title}</strong>{row.code ? <small> · {row.title}</small> : null}</span> },
    { key: "method", header: t("discounts.col.method"),
      render: (row) => row.method === "code" ? t("discounts.method.code") : t("discounts.method.automatic") },
    { key: "type", header: t("discounts.col.type"),
      render: (row) => `${t(`discounts.class.${row.discountClass}`)} · ${valueLabel(row)}` },
    { key: "used", header: t("discounts.col.used"), align: "right",
      render: (row) => `${row.timesUsed}${row.usageLimit ? `/${row.usageLimit}` : ""}` },
    { key: "status", header: t("discounts.col.status"), render: (row) => statusBadge(row.status) },
  ];

  const TYPES = [
    { key: "product", title: t("discounts.type.products"), desc: t("discounts.type.productsDesc"), enabled: true },
    { key: "bxgy", title: t("discounts.type.bxgy"), desc: t("discounts.type.productsDesc"), enabled: false },
    { key: "order", title: t("discounts.type.order"), desc: t("discounts.type.orderDesc"), enabled: true },
    { key: "shipping", title: t("discounts.type.shipping"), desc: t("discounts.type.shippingDesc"), enabled: true },
  ];

  if (error) {
    return (
      <Page title={t("discounts.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  return (
    <Page title={t("discounts.title")}>
      <div className="cl-section-title-row">
        <span />
        <Button onClick={() => setPickerOpen(true)} ref={createRef} variant="primary">
          {t("discounts.create")}
        </Button>
      </div>

      {rows === null ? (
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      ) : rows.length === 0 ? (
        <Card padded>
          <EmptyState
            action={<Button onClick={() => setPickerOpen(true)} variant="primary">{t("discounts.create")}</Button>}
            description={t("discounts.emptyBody")}
            illustration={null}
            title={t("discounts.emptyTitle")}
          />
        </Card>
      ) : (
        <Card>
          <IndexTable
            caption={t("discounts.title")}
            columns={columns}
            getRowKey={(row) => row.id}
            getRowLabel={(row) => row.title}
            onRowActivate={(row) => navigate(`/admin/discounts/${row.id.replace("gid://chilllove/Discount/", "")}`)}
            rows={rows}
          />
        </Card>
      )}

      {pickerOpen ? (
        <Modal
          footer={<Button onClick={() => setPickerOpen(false)}>{t("common.cancel")}</Button>}
          onClose={() => setPickerOpen(false)}
          open
          restoreFocusTo={createRef}
          title={t("discounts.selectType")}
        >
          <ul className="cl-menu-list">
            {TYPES.map((type) => (
              <li key={type.key}>
                <button
                  className="cl-menu-list__item"
                  disabled={!type.enabled}
                  onClick={() => { setPickerOpen(false); navigate(`/admin/discounts/new/${type.key}`); }}
                  type="button"
                >
                  <strong>{type.title}</strong>
                  <small> — {type.enabled ? type.desc : t("discounts.comingSoon")}</small>
                </button>
              </li>
            ))}
          </ul>
        </Modal>
      ) : null}
    </Page>
  );
}
