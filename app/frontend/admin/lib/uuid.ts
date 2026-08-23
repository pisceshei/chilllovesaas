/**
 * UUID v4 產生器——冪等鍵用（`limits.idempotency.key_format_interactive`）。
 *
 * 🔴 不直接用 `crypto.randomUUID()`：它是 **secure context 限定** API，
 * 明文 HTTP（TLS 前的 28080 過渡入口）下是 undefined ⇒ 建立頁一掛載就
 * `TypeError: crypto.randomUUID is not a function`（2026-08-23 實機抓到；
 * jsdom 與 localhost 都測不出——兩者都算 secure context）。
 * `crypto.getRandomValues` 沒有這個限制，手組 v4 與其等價。
 */
export function uuidV4(): string {
  if (typeof crypto.randomUUID === "function") return crypto.randomUUID();

  const bytes = crypto.getRandomValues(new Uint8Array(16));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}
