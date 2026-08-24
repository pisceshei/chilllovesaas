/**
 * 選項樹 → 變體列的重建邏輯（第 23 包；63 §B.4/§B.5 的前端側）。
 *
 * ①這是什麼：商品頁變體卡的列模型。列＝**顯式清單**、不是選項值的自動笛卡兒積
 *   ——後端允許稀疏矩陣（DeleteVariant 刪掉一格後其餘照常），自動補全會在下次
 *   儲存把被刪的組合復活（63 §B.4 規則 1：送出＝宣告全量，多送＝多建）。
 * ②重建規則（`rebuildRows`，與後端 VariantSync 階段 A 投影同構）：
 *   - 既有列投影到新選項集合：同名選項保留該列的值（值被刪 ⇒ 整列剔除）、
 *     新選項補**第一值**；投影撞同座標時去重、**帶 id 的列優先**存活。
 *   - 含「新增值」的缺格補為新列（其餘座標須出現在既有列）——加值＝加列，
 *     但既有稀疏格不會被復活。
 *   - 首次啟用（前選項為空）＝純笛卡兒積；首列繼承定價卡的 price／sku
 *     （隱含變體升級語義；id 不帶，後端以投影 digest 對回原變體保 id）。
 * ③上限鏡射（鐵律 6 的前端側；正典＝`config/limits.yml`，同 inventoryLimits.ts
 *   的已知鏡射形態）：`product.max_options`＝3、`catalog_flow.variant_render_batch`
 *   ＝250（超過 ⇒ rebuildRows 回 null，UI 擋下不重建；伺服端 2048 是硬上限，
 *   250 是本表的渲染上限）。
 * ④跨功能影響：ProductDetailPage 變體卡（本包）、第 29 包變體子頁（讀同一
 *   模型）、productSet 的 options／variants input（送出形狀）。
 */

/**
 * 選項草稿（名稱＋值序＝position）。
 * 🔴 `key`＝UI 生命週期內的穩定身分（uuid；改名不變、送出剝除）——rebuild 以 key
 *    diff 而非 name：兩個選項暫時同名（改名途中）時 name-keyed Map 會 last-wins、
 *    把第一個選項的投影讀到第二個的座標，整批殺列（審查 C2 實證）。
 */
export interface OptionDraft {
  key: string;
  name: string;
  values: string[];
}

/**
 * 變體列（coords 依 options 序；金額欄保存原始輸入字串，送出才轉 cents）。
 * 🔴 compare／cost／barcode／taxable 是**回聲欄**：v1 表格不給編、但 productSet
 *    是宣告式覆寫（缺席＝清除）——載入時原值進列、送出時原樣回聲，否則儲存
 *    一次就把既有變體的比較價／成本／條碼靜默抹掉。
 */
export interface VariantRowData {
  /** 既有變體 GID；新列為 null（後端以投影 digest 或新建處置）。 */
  id: string | null;
  coords: string[];
  price: string;
  sku: string;
  /** 建立態的可售數量欄（initialQuantities；空字串＝不送）。 */
  quantity: string;
  compare: string;
  cost: string;
  barcode: string;
  taxable: boolean;
}

/** 新列的繼承來源（定價卡現值；首次啟用時首列全欄繼承＝隱含變體升級）。 */
export interface RowSeed {
  price: string;
  sku: string;
  compare: string;
  cost: string;
  barcode: string;
  taxable: boolean;
}

/** 依 seed 造新列（非首列只繼承 price／taxable）。 */
const freshRow = (coords: string[], seed: RowSeed, first: boolean): VariantRowData => ({
  id: null,
  coords,
  price: seed.price,
  sku: first ? seed.sku : "",
  quantity: "",
  compare: first ? seed.compare : "",
  cost: first ? seed.cost : "",
  barcode: first ? seed.barcode : "",
  taxable: seed.taxable,
});

/** 鏡射 `config/limits.yml` `product.max_options`（正典在 limits，改那邊要同步）。 */
export const MAX_PRODUCT_OPTIONS = 3;

/** 鏡射 `config/limits.yml` `catalog_flow.variant_render_batch`（渲染上限，非業務上限）。 */
export const VARIANT_ROW_CAP = 250;

const COORD_SEP = "\u0000"; // 跳脫字面——裸 NUL 會讓 git 把本檔判成 binary（審查 C3）

const coordKey = (coords: string[]): string => coords.join(COORD_SEP);

/** 墓場鍵：選項 key 序＋座標（呼叫端埋葬／復活共用）。 */
export const graveKey = (options: OptionDraft[], coords: string[]): string =>
  options.map((option) => option.key).join(COORD_SEP) + "::" + coords.join(COORD_SEP);

/** 選項值的笛卡兒積（row-major：第一個選項最外層——與本尊變體序一致）。 */
export function cartesian(options: OptionDraft[]): string[][] {
  return options.reduce<string[][]>(
    (combos, option) => combos.flatMap((combo) => option.values.map((value) => [ ...combo, value ])),
    [ [] ],
  );
}

/**
 * 依選項變更重建變體列。
 *
 * @param prevOptions - 變更前的選項集合。
 * @param nextOptions - 變更後的選項集合。
 * @param prevRows - 變更前的列（coords 依 prevOptions 序）。
 * @param seed - 新列的 price／sku 繼承來源。
 * @param graveyard - 本編輯階段內曾被剔除的列（鍵＝`graveKey`）。補列時座標命中
 *   即**復活原列**（含 id 與回聲欄）——「刪值再加回」若補成空白 freshRow，後端
 *   digest-match 會把既有變體的 sku/compare/cost/barcode 宣告式抹掉（審查 C1 實證）。
 * @returns 重建後的列；超出 VARIANT_ROW_CAP 時回 null（呼叫端擋下、不套用變更）。
 */
export function rebuildRows(
  prevOptions: OptionDraft[],
  nextOptions: OptionDraft[],
  prevRows: VariantRowData[],
  seed: RowSeed,
  graveyard?: Map<string, VariantRowData>,
): VariantRowData[] | null {
  if (nextOptions.length === 0) return [];
  const combos = cartesian(nextOptions);
  if (combos.length > VARIANT_ROW_CAP) return null;

  // 首次啟用：純笛卡兒積；首列繼承 seed.sku（隱含變體升級——id 由後端 digest 保）
  if (prevOptions.length === 0 || prevRows.length === 0) {
    return combos.map((coords, index) => freshRow(coords, seed, index === 0));
  }

  const prevIndexByKey = new Map(prevOptions.map((option, index) => [ option.key, index ]));
  const prevValueSets = new Map(prevOptions.map((option) => [ option.key, new Set(option.values) ]));

  // 投影：同名選項保留列值（值仍存在才保；否則整列剔除）、新選項補第一值
  const projected: VariantRowData[] = [];
  for (const row of prevRows) {
    const coords: string[] = [];
    let alive = true;
    for (const option of nextOptions) {
      const prevIndex = prevIndexByKey.get(option.key);
      if (prevIndex === undefined) {
        coords.push(option.values[0]);
        continue;
      }
      const value = row.coords[prevIndex];
      if (!option.values.includes(value)) {
        alive = false;
        break;
      }
      coords.push(value);
    }
    if (alive) projected.push({ ...row, coords });
  }

  // 去重（移除選項可令座標塌縮）：帶 id 的列優先存活
  const byKey = new Map<string, VariantRowData>();
  for (const row of projected) {
    const key = coordKey(row.coords);
    const existing = byKey.get(key);
    if (!existing || (!existing.id && row.id)) byKey.set(key, row);
  }

  // 新值補列：缺格含至少一個「新增值」且其餘座標出現在既有列 ⇒ 補；
  // 純既有值的缺格＝使用者先前刪過的稀疏格，不復活。
  const newValueKeys = new Set<string>();
  for (const option of nextOptions) {
    const prevValues = prevValueSets.get(option.key);
    for (const value of option.values) {
      if (!prevValues || !prevValues.has(value)) newValueKeys.add(`${option.key}${COORD_SEP}${value}`);
    }
  }
  const usedValues = nextOptions.map((option, index) => {
    const set = new Set<string>();
    for (const row of byKey.values()) set.add(row.coords[index]);
    return { option, set };
  });

  const result: VariantRowData[] = [];
  for (const coords of combos) {
    const key = coordKey(coords);
    const existing = byKey.get(key);
    if (existing) {
      result.push(existing);
      continue;
    }
    const hasNewValue = coords.some((value, index) =>
      newValueKeys.has(`${nextOptions[index].key}${COORD_SEP}${value}`));
    if (!hasNewValue) continue;
    const othersKnown = coords.every((value, index) =>
      newValueKeys.has(`${nextOptions[index].key}${COORD_SEP}${value}`) || usedValues[index].set.has(value));
    if (!othersKnown) continue;
    const buried = graveyard?.get(graveKey(nextOptions, coords));
    result.push(buried ? { ...buried, coords } : freshRow(coords, seed, false));
  }
  return result;
}
