import { useCallback, useEffect, useState } from "react";
import { requestAdminGraphQL } from "../api/graphql";
import { Button } from "../components/Button";
import { Card } from "../components/Card";
import { Page } from "../components/Page";
import { useT } from "../i18n/I18nContext";

/**
 * admin 首頁 KPI（G6 步 10；19-F2.3 單次往返全卡片）。
 * 卡片：Total sales／Orders／AOV／Net sales＋逐日走勢（簡表）。
 * 🔴 80 §3：AOV 獨立分子——不從 total/orders 反推；total 可為負照顯。
 * ⚪ 72 號 16 指標挑選器／recharts 走勢圖隨分析頁完整版。
 */
const OVERVIEW_QUERY = `
  query analyticsOverview($from: ISO8601Date!, $to: ISO8601Date!) {
    analyticsOverview(from: $from, to: $to) {
      totalSalesCents netSalesCents ordersCount aovCents returnsCents
      series { date totalSalesCents }
    }
  }
`;

interface Overview {
  totalSalesCents: number;
  netSalesCents: number;
  ordersCount: number;
  aovCents: number;
  returnsCents: number;
  series: { date: string; totalSalesCents: number }[];
}

type RangeKey = "today" | "7d" | "30d";

function rangeFor(key: RangeKey): { from: string; to: string } {
  const to = new Date();
  const from = new Date();
  if (key === "7d") from.setDate(to.getDate() - 6);
  if (key === "30d") from.setDate(to.getDate() - 29);
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  return { from: iso(from), to: iso(to) };
}

function money(cents: number): string {
  const sign = cents < 0 ? "−" : "";
  return `${sign}HK$${(Math.abs(cents) / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

export function HomePage() {
  const t = useT();
  const [range, setRange] = useState<RangeKey>("7d");
  const [data, setData] = useState<Overview | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async (signal?: AbortSignal) => {
    try {
      const result = await requestAdminGraphQL<{ analyticsOverview: Overview }, { from: string; to: string }>(
        OVERVIEW_QUERY, rangeFor(range), signal
      );
      setData(result.analyticsOverview);
      setError(null);
    } catch (reason: unknown) {
      if (signal?.aborted) return;
      setError(reason instanceof Error ? reason.message : t("home.loadFailed"));
    }
  }, [range, t]);

  useEffect(() => {
    const controller = new AbortController();
    void load(controller.signal);
    return () => controller.abort();
  }, [load]);

  return (
    <Page title={t("home.title")}>
      <div className="cl-section-title-row">
        <span />
        <span>
          {([ [ "today", t("home.range.today") ], [ "7d", t("home.range.7d") ],
              [ "30d", t("home.range.30d") ] ] as const).map(([ key, label ]) => (
            <Button key={key} onClick={() => setRange(key)}
              variant={range === key ? "primary" : "ghost"}>
              {label}
            </Button>
          ))}
        </span>
      </div>

      {error ? (
        <Card padded>
          <p className="cl-card-note">{error}</p>
          <Button onClick={() => void load()}>{t("common.retry")}</Button>
        </Card>
      ) : !data ? (
        <Card padded><p className="cl-card-note">{t("common.loading")}</p></Card>
      ) : (
        <>
          <Card padded>
            <div className="cl-kpi-row">
              <div className="cl-kpi-cell">
                <small>{t("home.kpi.totalSales")}</small>
                <strong>{money(data.totalSalesCents)}</strong>
              </div>
              <div className="cl-kpi-cell">
                <small>{t("home.kpi.orders")}</small>
                <strong>{data.ordersCount}</strong>
              </div>
              <div className="cl-kpi-cell">
                <small>{t("home.kpi.aov")}</small>
                <strong>{money(data.aovCents)}</strong>
              </div>
              <div className="cl-kpi-cell">
                <small>{t("home.kpi.netSales")}</small>
                <strong>{money(data.netSalesCents)}</strong>
              </div>
            </div>
            <p className="cl-card-note">{t("home.freshness")}</p>
          </Card>

          <Card padded>
            <h3 className="cl-section-title">{t("home.seriesTitle")}</h3>
            {data.series.length === 0 ? (
              <p className="cl-card-note">{t("home.seriesEmpty")}</p>
            ) : (
              <ul className="cl-config-list">
                {data.series.map((point) => (
                  <li className="cl-config-list__row" key={point.date}>
                    <span>{point.date}</span>
                    <span className="cl-order-total">{money(point.totalSalesCents)}</span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </>
      )}
    </Page>
  );
}
