/** 唯一允許 Admin SPA 使用的首版 GraphQL 端點（docs/research/28 §0.1）。 */
export const ADMIN_GRAPHQL_ENDPOINT = "/admin/api/2026-08/graphql.json";

/** GraphQL top-level error；業務驗證錯誤另由 mutation payload 的 userErrors 承載。 */
export interface GraphQLTopLevelError {
  /** 可安全顯示的錯誤訊息。 */
  message: string;
  /** 規格定義的錯誤資訊，例如 THROTTLED 或 requestId。 */
  extensions?: Record<string, unknown>;
}

interface GraphQLResponse<Data> {
  data?: Data;
  errors?: GraphQLTopLevelError[];
}

/**
 * top-level GraphQL error 的型別化例外——保留 extensions.code 供呼叫端分支。
 *
 * 鐵律 4 的三層錯誤裡，第 ② 層（THROTTLED／MAX_COST_EXCEEDED）與部分第 ③ 層
 * 語義（ACCESS_DENIED、IDEMPOTENCY_KEY_REQUIRED）都走 top-level errors；
 * 只丟 join 過的字串會讓呼叫端拿不到 code、無法機器分支。
 */
export class AdminGraphQLError extends Error {
  /** 原始 top-level errors。 */
  readonly errors: GraphQLTopLevelError[];

  constructor(errors: GraphQLTopLevelError[]) {
    super(errors.map((error) => error.message).join("；"));
    this.name = "AdminGraphQLError";
    this.errors = errors;
  }

  /** 第一個 error 的 extensions.code（無則 undefined）。 */
  get code(): string | undefined {
    const raw = this.errors[0]?.extensions?.["code"];
    return typeof raw === "string" ? raw : undefined;
  }
}

/**
 * 讀取 Rails 產生的 CSRF token。
 *
 * @returns token；測試或非 Rails 文件缺少 meta 時回傳 undefined。
 */
export function readCsrfToken(): string | undefined {
  return document.querySelector<HTMLMetaElement>('meta[name="csrf-token"]')?.content;
}

/**
 * 以同源 session + CSRF 對 Admin GraphQL 送出 POST。
 *
 * @remarks
 * 固定端點與 HTTP 200 的 top-level/userErrors 分工見 `docs/research/28` §0、§18。
 * 此函式不提供任意 URL 參數，避免 admin 功能旁路至 REST。
 *
 * @typeParam Data - operation 的 data 結構。
 * @typeParam Variables - operation variables 結構。
 * @param query - GraphQL operation 文件。
 * @param variables - operation variables。
 * @param signal - 可選 AbortSignal；頁面卸載時取消請求。
 * @returns GraphQL data。
 * @throws HTTP 失敗、top-level GraphQL error 或缺少 data 時拋出 Error。
 */
export async function requestAdminGraphQL<
  Data,
  Variables extends Record<string, unknown> = Record<string, never>,
>(query: string, variables: Variables, signal?: AbortSignal): Promise<Data> {
  const csrfToken = readCsrfToken();
  const headers: Record<string, string> = {
    Accept: "application/json",
    "Content-Type": "application/json",
  };

  if (csrfToken) headers["X-CSRF-Token"] = csrfToken;

  const response = await fetch(ADMIN_GRAPHQL_ENDPOINT, {
    body: JSON.stringify({ query, variables }),
    credentials: "same-origin",
    headers,
    method: "POST",
    signal,
  });

  if (!response.ok) {
    throw new Error(`伺服器回應異常（${response.status}）`);
  }

  const payload = (await response.json()) as GraphQLResponse<Data>;
  if (payload.errors?.length) {
    throw new AdminGraphQLError(payload.errors);
  }
  if (!payload.data) {
    throw new Error("伺服器沒有回傳商品資料。");
  }

  return payload.data;
}
