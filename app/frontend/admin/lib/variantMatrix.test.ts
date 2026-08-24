import { describe, expect, it } from "vitest";
import { cartesian, graveKey, rebuildRows, VARIANT_ROW_CAP } from "./variantMatrix";
import type { OptionDraft, VariantRowData } from "./variantMatrix";

/**
 * 變體列重建（第 23 包）的值域測試。
 * 🔴 核心不變量：稀疏格不復活（63 §B.4 規則 1——多送＝多建）＋帶 id 列在
 *    座標塌縮時優先存活（id 斷了＝ledger 斷鏈的 UI 側前奏）。
 */
const SEED = { price: "128.00", sku: "TEE-1", compare: "168.00", cost: "60.00", barcode: "4710000000000", taxable: true };

const row = (coords: string[], overrides: Partial<VariantRowData> = {}): VariantRowData => ({
  id: null,
  coords,
  price: "10.00",
  sku: "",
  quantity: "",
  compare: "",
  cost: "",
  barcode: "",
  taxable: true,
  ...overrides,
});

describe("cartesian", () => {
  it("row-major：第一個選項最外層", () => {
    expect(cartesian([
      { key: "k-尺寸", name: "尺寸", values: [ "S", "M" ] },
      { key: "k-色", name: "色", values: [ "黑", "白" ] },
    ])).toEqual([ [ "S", "黑" ], [ "S", "白" ], [ "M", "黑" ], [ "M", "白" ] ]);
  });
});

describe("rebuildRows", () => {
  it("首次啟用＝笛卡兒積；首列繼承定價卡 price/sku（隱含變體升級）", () => {
    const rows = rebuildRows([], [ { key: "k-容量", name: "容量", values: [ "230ml", "250ml", "330ml" ] } ], [], SEED);
    expect(rows).toHaveLength(3);
    expect(rows?.map((r) => r.coords)).toEqual([ [ "230ml" ], [ "250ml" ], [ "330ml" ] ]);
    // 首列全欄繼承（隱含變體升級＝回聲欄不丟）；其餘列只繼承 price/taxable
    expect(rows?.[0]).toMatchObject({ id: null, price: "128.00", sku: "TEE-1",
      compare: "168.00", cost: "60.00", barcode: "4710000000000", taxable: true });
    expect(rows?.[1]).toMatchObject({ price: "128.00", sku: "", compare: "", barcode: "" });
  });

  it("加值＝補列（既有列與其資料原位保留）；🔴 稀疏格不復活", () => {
    const options: OptionDraft[] = [
      { key: "k-尺寸", name: "尺寸", values: [ "S", "M" ] },
      { key: "k-色", name: "色", values: [ "黑", "白" ] },
    ];
    // 稀疏：M×白 先前被刪
    const prev = [
      row([ "S", "黑" ], { id: "gid://chilllove/ProductVariant/1", price: "11.00" }),
      row([ "S", "白" ]),
      row([ "M", "黑" ]),
    ];
    const next: OptionDraft[] = [
      { key: "k-尺寸", name: "尺寸", values: [ "S", "M", "L" ] },
      { key: "k-色", name: "色", values: [ "黑", "白" ] },
    ];
    const rows = rebuildRows(options, next, prev, SEED);
    expect(rows?.map((r) => r.coords)).toEqual([
      [ "S", "黑" ], [ "S", "白" ], [ "M", "黑" ],
      [ "L", "黑" ], [ "L", "白" ],
    ]);
    // 既有列資料保留；新列繼承 seed price
    expect(rows?.[0]).toMatchObject({ id: "gid://chilllove/ProductVariant/1", price: "11.00" });
    expect(rows?.[3]).toMatchObject({ id: null, price: "128.00" });
    // 🔴 M×白 沒有回來
    expect(rows?.some((r) => r.coords.join() === "M,白")).toBe(false);
  });

  it("新增選項維度：既有列補第一值（階段 A 同構）、其餘值展開為新列", () => {
    const prev = [ row([ "S" ], { id: "gid://chilllove/ProductVariant/7", sku: "S-1" }) ];
    const rows = rebuildRows(
      [ { key: "k-尺寸", name: "尺寸", values: [ "S" ] } ],
      [ { key: "k-尺寸", name: "尺寸", values: [ "S" ] }, { key: "k-色", name: "色", values: [ "黑", "白" ] } ],
      prev, SEED,
    );
    expect(rows?.map((r) => r.coords)).toEqual([ [ "S", "黑" ], [ "S", "白" ] ]);
    expect(rows?.[0]).toMatchObject({ id: "gid://chilllove/ProductVariant/7", sku: "S-1" });
    expect(rows?.[1]).toMatchObject({ id: null });
  });

  it("刪值＝整列剔除；刪選項＝座標塌縮去重且 🔴 帶 id 列優先存活", () => {
    const options: OptionDraft[] = [
      { key: "k-尺寸", name: "尺寸", values: [ "S" ] },
      { key: "k-色", name: "色", values: [ "黑", "白" ] },
    ];
    const prev = [
      row([ "S", "黑" ]),
      row([ "S", "白" ], { id: "gid://chilllove/ProductVariant/9", price: "99.00" }),
    ];
    // 刪值：白 → 只剩 S×黑
    expect(rebuildRows(options, [
      { key: "k-尺寸", name: "尺寸", values: [ "S" ] },
      { key: "k-色", name: "色", values: [ "黑" ] },
    ], prev, SEED)?.map((r) => r.coords)).toEqual([ [ "S", "黑" ] ]);
    // 刪選項：色 → 兩列塌縮成一列，id 列勝
    const collapsed = rebuildRows(options, [ { key: "k-尺寸", name: "尺寸", values: [ "S" ] } ], prev, SEED);
    expect(collapsed).toHaveLength(1);
    expect(collapsed?.[0]).toMatchObject({ id: "gid://chilllove/ProductVariant/9", coords: [ "S" ] });
  });

  it("純重排（值序調換）：列資料不動、coords 依新選項序重寫", () => {
    const prev = [
      row([ "S", "黑" ], { id: "gid://chilllove/ProductVariant/3" }),
      row([ "M", "白" ]),
    ];
    const rows = rebuildRows(
      [ { key: "k-尺寸", name: "尺寸", values: [ "S", "M" ] }, { key: "k-色", name: "色", values: [ "黑", "白" ] } ],
      [ { key: "k-色", name: "色", values: [ "白", "黑" ] }, { key: "k-尺寸", name: "尺寸", values: [ "M", "S" ] } ],
      prev, SEED,
    );
    // 沒有新值 ⇒ 零補列；座標依新序（色在前）
    expect(rows?.map((r) => r.coords).sort()).toEqual([ [ "白", "M" ], [ "黑", "S" ] ].sort());
    expect(rows?.find((r) => r.id)?.coords).toEqual([ "黑", "S" ]);
  });

  it("🔴 墓場復活：刪值再加回 ⇒ 原列（id＋回聲欄）回歸，不是空白 freshRow（審查 C1）", () => {
    const options: OptionDraft[] = [
      { key: "k-尺寸", name: "尺寸", values: [ "S" ] },
      { key: "k-色", name: "色", values: [ "黑", "白" ] },
    ];
    const white = row([ "S", "白" ], { id: "gid://chilllove/ProductVariant/9",
      sku: "W-1", compare: "150.00", barcode: "471", price: "99.00" });
    const prev = [ row([ "S", "黑" ] ), white ];
    const removed: OptionDraft[] = [
      { key: "k-尺寸", name: "尺寸", values: [ "S" ] },
      { key: "k-色", name: "色", values: [ "黑" ] },
    ];
    const graveyard = new Map([ [ graveKey(removed.length === 2 ? options : options, white.coords), white ] ]);
    const afterRemove = rebuildRows(options, removed, prev, SEED);
    expect(afterRemove?.map((r) => r.coords)).toEqual([ [ "S", "黑" ] ]);
    const back = rebuildRows(removed, options, afterRemove ?? [], SEED, graveyard);
    const revived = back?.find((r) => r.coords.join() === "S,白");
    expect(revived).toMatchObject({ id: "gid://chilllove/ProductVariant/9",
      sku: "W-1", compare: "150.00", barcode: "471", price: "99.00" });
  });

  it("🔴 兩選項暫時同名（改名途中）：以 key diff，值編輯不毀列（審查 C2）", () => {
    // 尺寸(S,M) 與「款式」被改名成「尺寸」——name 撞、key 不撞
    const prev: OptionDraft[] = [
      { key: "k-A", name: "尺寸", values: [ "S", "M" ] },
      { key: "k-B", name: "尺寸", values: [ "X" ] },
    ];
    const rows = [
      row([ "S", "X" ], { id: "gid://chilllove/ProductVariant/1" }),
      row([ "M", "X" ], { id: "gid://chilllove/ProductVariant/2" }),
    ];
    const next: OptionDraft[] = [
      { key: "k-A", name: "尺寸", values: [ "S", "M", "L" ] },
      { key: "k-B", name: "尺寸", values: [ "X" ] },
    ];
    const rebuilt = rebuildRows(prev, next, rows, SEED);
    expect(rebuilt?.map((r) => r.coords)).toEqual([ [ "S", "X" ], [ "M", "X" ], [ "L", "X" ] ]);
    expect(rebuilt?.[0].id).toBe("gid://chilllove/ProductVariant/1");
    expect(rebuilt?.[1].id).toBe("gid://chilllove/ProductVariant/2");
  });

  it("選項清空＝零列；超出渲染上限回 null（呼叫端擋下）", () => {
    expect(rebuildRows([ { key: "k-尺寸", name: "尺寸", values: [ "S" ] } ], [], [ row([ "S" ]) ], SEED)).toEqual([]);
    const wide: OptionDraft = { key: "k-碼", name: "碼", values: Array.from({ length: VARIANT_ROW_CAP + 1 }, (_, i) => `v${i}`) };
    expect(rebuildRows([], [ wide ], [], SEED)).toBeNull();
  });
});
