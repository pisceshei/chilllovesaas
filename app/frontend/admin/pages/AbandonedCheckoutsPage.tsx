import { useCallback, useEffect, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Badge } from "../components/Badge";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { EmptyState } from "../components/EmptyState";
import { IndexTable } from "../components/IndexTable";
import type { IndexTableColumn } from "../components/IndexTable";
import { LoadMore } from "../components/LoadMore";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";
import { useToast } from "../lib/ToastContext";
import { formatMoney } from "./OrdersPage";

/**
 * 未完成結帳（G6 步 7；docs/research/89 §8 本尊列表七欄對位）：
 * Checkout／Created／Customer name／Email status（Sent/Not sent）／Region／
 * Recovery status（Recovered/Not recovered）／Total price＋每列 Send recovery 動作。
 * ⚪ 詳情頁（89 §8 有 recovery URL 拷貝框／Notes 卡）後置；自動排程寄送同 ⚪。
 */
const ABANDONED_QUERY = `
  query abandonedCheckoutList($after: String) {
    abandonedCheckouts(first: 50, after: $after) {
      nodes {
        id email customerName region createdAt abandonedAt
        totalPriceSet { shopMoney { amount currencyCode } }
        lineItemsCount recoveryEmailSentAt recovered
      }
      pageInfo { hasNextPage endCursor }
    }
  }
`;

const SEND_MUTATION = `
  mutation abandonedCheckoutSendRecovery($id: ID!) {
    abandonedCheckoutSendRecovery(id: $id) {
      abandonedCheckout { id recoveryEmailSentAt }
      userErrors { field message code }
    }
  }
`;

interface AbandonedRow {
  id: string;
  email: string | null;
  customerName: string | null;
  region: string | null;
  createdAt: string;
  abandonedAt: string;
  totalPriceSet: { shopMoney: { amount: string; currencyCode: string } };
  lineItemsCount: number;
  recoveryEmailSentAt: string | null;
  recovered: boolean;
}

interface ListData {
  abandonedCheckouts: {
    nodes: AbandonedRow[];
    pageInfo: { hasNextPage: boolean; endCursor: string | null };
  };
}

export function AbandonedCheckoutsPage() {
  const t = useT();
  const { showToast } = useToast();
  const [rows, setRows] = useState<AbandonedRow[] | null>(null);
  const [pageInfo, setPageInfo] = useState<{ hasNextPage: boolean; endCursor: string | null }>({ hasNextPage: false, endCursor: null });
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const data = await requestAdminGraphQL<ListData, { after: string | null }>(ABANDONED_QUERY, { after: null }, signal);
      setRows(data.abandonedCheckouts.nodes);
      setPageInfo(data.abandonedCheckouts.pageInfo);
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("abandoned.loadFailed"));
    }
  }, [t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  const loadMore = async () => {
    setLoadingMore(true);
    try {
      const data = await requestAdminGraphQL<ListData, { after: string | null }>(ABANDONED_QUERY, { after: pageInfo.endCursor });
      setRows((current) => [ ...(current ?? []), ...data.abandonedCheckouts.nodes ]);
      setPageInfo(data.abandonedCheckouts.pageInfo);
    } catch {
      showToast(t("abandoned.loadFailed"));
    } finally {
      setLoadingMore(false);
    }
  };

  const sendRecovery = async (row: AbandonedRow) => {
    setBusyId(row.id);
    try {
      const data = await requestAdminGraphQL<{ abandonedCheckoutSendRecovery: {
        abandonedCheckout: { id: string } | null;
        userErrors: { field: string[] | null; message: string; code: string }[];
      } }, { id: string }>(SEND_MUTATION, { id: row.id });
      const payload = data.abandonedCheckoutSendRecovery;
      if (payload.userErrors.length > 0) {
        showToast(payload.userErrors[0].message);
        return;
      }
      showToast(t("abandoned.sendQueued"));
      await load();
    } catch {
      showToast(t("settings.payments.actionFailed"));
    } finally {
      setBusyId(null);
    }
  };

  const checkoutNumber = (id: string) => `#${id.replace("gid://chilllove/AbandonedCheckout/", "")}`;

  const columns: readonly IndexTableColumn<AbandonedRow>[] = [
    { key: "checkout", header: t("abandoned.col.checkout"), render: (row) => <strong>{checkoutNumber(row.id)}</strong> },
    { key: "created", header: t("abandoned.col.created"), render: (row) => new Date(row.createdAt).toLocaleString() },
    { key: "customer", header: t("abandoned.col.customer"),
      render: (row) => row.customerName || row.email || t("abandoned.noCustomer") },
    { key: "emailStatus", header: t("abandoned.col.emailStatus"),
      render: (row) => row.recoveryEmailSentAt
        ? <Badge progress="full" tone="success">{t("abandoned.emailSent")}</Badge>
        : <Badge progress="empty" tone="default">{t("abandoned.emailNotSent")}</Badge> },
    { key: "region", header: t("abandoned.col.region"), render: (row) => row.region ?? "—" },
    { key: "recovery", header: t("abandoned.col.recoveryStatus"),
      render: (row) => row.recovered
        ? <Badge progress="full" tone="success">{t("abandoned.recovered")}</Badge>
        : <Badge progress="half" tone="attention">{t("abandoned.notRecovered")}</Badge> },
    { key: "total", header: t("abandoned.col.total"), align: "right",
      render: (row) => formatMoney(row.totalPriceSet.shopMoney) },
    { key: "actions", header: "", align: "right",
      render: (row) => (
        <Button
          disabled={busyId === row.id || row.recovered || !row.email}
          onClick={() => void sendRecovery(row)}
          variant="secondary"
        >
          {row.recoveryEmailSentAt ? t("abandoned.resend") : t("abandoned.send")}
        </Button>
      ) },
  ];

  if (error) {
    return (
      <Page title={t("abandoned.title")}>
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      </Page>
    );
  }

  if (rows === null) {
    return (
      <Page title={t("abandoned.title")}>
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      </Page>
    );
  }

  return (
    <Page title={t("abandoned.title")}>
      {rows.length === 0 ? (
        <Card padded>
          <EmptyState
            action={null}
            description={t("abandoned.emptyBody")}
            illustration={null}
            title={t("abandoned.emptyTitle")}
          />
        </Card>
      ) : (
        <Card>
          <IndexTable
            caption={t("abandoned.title")}
            columns={columns}
            getRowKey={(row) => row.id}
            getRowLabel={(row) => checkoutNumber(row.id)}
            rows={rows}
          />
          <LoadMore
            error={null}
            hasNextPage={pageInfo.hasNextPage}
            loading={loadingMore}
            onLoadMore={() => void loadMore()}
          />
        </Card>
      )}
    </Page>
  );
}
