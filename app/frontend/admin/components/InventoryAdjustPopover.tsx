import { useState } from "react";
import { Check } from "lucide-react";
import { Button } from "./Button";
import { TextField } from "./TextField";
import { useT } from "../i18n/I18nContext";

/**
 * 行內庫存調整器（排程第 18 包；**A 塊與 B 塊共用，第 29 包變體子頁也複用**）。
 *
 * ①這是什麼：點庫存數量儲存格後展開的就地編輯器。實測形態（`docs/research/94` §2.3）：
 *   `[Set to｜Adjust by ⌄] [數量] [地點名] [Add reason ⌄] [✓]`。
 * ②值域：
 *   - 模式二值：`set`（絕對值）／`adjust`（差額）——實測下拉只有這兩項。
 *   - 數量名二值：`available`／`on_hand`（本尊列表只有這兩欄可點）。
 *   - reason＝UI 7 值子集，由呼叫端傳入（來源＝`limits.inventory.adjustment_reasons_manual_ui`，
 *     鐵律 6：元件不自己列清單）；預設 `correction`（help 明文「The default option」）。
 * ③怎麼做：✓ **只回報 pending**（`onStage`），不打網路——送出由 SaveBar 統一做（兩段式，
 *   help 明文「click the icon to set the adjustment as pending, and then click Save」）。
 *   `compareAgainst` 是載入時的現值，由呼叫端帶入並原樣回傳給 mutation
 *   （set→`compareQuantity`／adjust→`changeFromQuantity`）——
 *   🔴 CAS 交伺服器判定，**前端不做第二套「值變了就擋」檢查**（兩處實作遲早漂移）。
 * ④跨功能影響：pending 的形狀就是 mutation 的輸入形狀（呼叫端只補 idempotencyKey 與 GID），
 *   所以本檔的 `StagedAdjustment` 是 A/B/第 29 包三處共用的契約；改它要同時改三處消費端。
 */
export interface StagedAdjustment {
  /** 目標數量名。 */
  readonly name: "available" | "on_hand";
  /** 模式：絕對值或差額。 */
  readonly mode: "set" | "adjust";
  /** set＝目標值；adjust＝差額。 */
  readonly value: number;
  /** 載入時的現值（CAS 基準，原樣送伺服器）。 */
  readonly compareAgainst: number;
  /** reason 識別字（API 值，非顯示標籤）。 */
  readonly reason: string;
  /** 套用後的預期值（僅供儲存格預覽 `9 → 10`；真相仍由伺服器回報）。 */
  readonly projected: number;
}

interface InventoryAdjustPopoverProps {
  /** 目標數量名。 */
  readonly name: "available" | "on_hand";
  /** 該儲存格的現值（CAS 基準與 Set to 的初始值）。 */
  readonly current: number;
  /** 地點顯示名（唯讀——移動語義屬 Move，本包不做）。 */
  readonly locationName: string;
  /** reason 值域（API 識別字），由呼叫端從 limits 取得。 */
  readonly reasons: readonly string[];
  /** ✓ 時回報 pending。 */
  readonly onStage: (staged: StagedAdjustment) => void;
  /** 取消（Escape 或失焦）。 */
  readonly onCancel: () => void;
}

export function InventoryAdjustPopover({
  current,
  locationName,
  name,
  onCancel,
  onStage,
  reasons,
}: InventoryAdjustPopoverProps) {
  const t = useT();
  const [mode, setMode] = useState<"set" | "adjust">("set");
  // Set to 的初始值＝現值（實測：點開就帶現值）；Adjust by 從 0 起。
  const [raw, setRaw] = useState(String(current));
  const [reason, setReason] = useState(reasons[0] ?? "correction");

  function switchMode(next: "set" | "adjust") {
    setMode(next);
    setRaw(next === "set" ? String(current) : "0");
  }

  const parsed = Number.parseInt(raw, 10);
  const valid = Number.isFinite(parsed);
  const projected = !valid ? current : mode === "set" ? parsed : current + parsed;

  return (
    <div
      className="cl-inventory-adjust"
      onKeyDown={(event) => {
        if (event.key === "Escape") onCancel();
      }}
      role="group"
      aria-label={t("inventory.adjust.label")}
    >
      <label className="cl-inventory-adjust__mode">
        <span className="cl-sr-only">{t("inventory.adjust.mode")}</span>
        <select
          aria-label={t("inventory.adjust.mode")}
          onChange={(event) => switchMode(event.currentTarget.value as "set" | "adjust")}
          value={mode}
        >
          <option value="set">{t("inventory.adjust.mode.set")}</option>
          <option value="adjust">{t("inventory.adjust.mode.adjust")}</option>
        </select>
      </label>

      <TextField
        inputMode="numeric"
        label={t("inventory.adjust.quantity")}
        labelHidden
        onChange={(event) => setRaw(event.currentTarget.value)}
        value={raw}
      />

      {/* 地點唯讀：本尊此處是選擇器（origin→destination 的移動語義），我方 v1 不做 Move。 */}
      <span className="cl-inventory-adjust__location">{locationName}</span>

      <label className="cl-inventory-adjust__reason">
        <span className="cl-sr-only">{t("inventory.adjust.reason")}</span>
        <select
          aria-label={t("inventory.adjust.reason")}
          onChange={(event) => setReason(event.currentTarget.value)}
          value={reason}
        >
          {reasons.map((value) => (
            <option key={value} value={value}>
              {t(`inventory.reason.${value}`)}
            </option>
          ))}
        </select>
      </label>

      <Button
        aria-label={t("inventory.adjust.stage")}
        disabled={!valid}
        onClick={() => onStage({ compareAgainst: current, mode, name, projected, reason, value: parsed })}
        size="small"
        variant="secondary"
      >
        <Check aria-hidden="true" size={14} />
      </Button>
    </div>
  );
}
