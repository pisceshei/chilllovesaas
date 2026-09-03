#!/usr/bin/env node
// 鐵律 22.1「精確到 CSS 級別」（D83）量測工具：以本機 Chrome（headless、乾淨 profile ⇒ 沒有使用者擴充功能的
// `font-weight:500 !important` 這類注入污染，memory `measurement-env-contamination`）經 CDP 逐元素擷取 computed style
// 與幾何，輸出 JSON；再把兩份 JSON（本尊 vs 我方）逐段、逐元素、逐屬性 diff 成 Markdown 報告（鐵律 22.4 憑證在倉庫）。
// 零新依賴：Node ≥ 22 內建 WebSocket／fetch；Chrome 路徑由 --chrome 或 CHROME_PATH 指定。
//
//   node scripts/computed-parity.mjs capture <url> <out.json> [--width 1280] [--height 900] [--chrome <path>] [--wait 1500]
//   node scripts/computed-parity.mjs diff <ref.json> <cand.json> [--out report.md] [--limit 60]
//   node scripts/computed-parity.mjs selftest
//
// 元素鍵＝所屬 section wrapper id（正規化：`template--{id}__`⇒`template--T__`、`sections--{id}__`⇒`sections--G__`、
// theme block 實例前綴 `A{17}__`⇒`B__`，同 app/services/render_parity/normalizer.rb 的身分規則）＋自 section 根起的
// `tag[:nth-of-type]` 路徑；只抹身分差，語義差全部留下（鐵律 22.2）。
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROPS = [
  "display", "position", "top", "right", "bottom", "left", "z-index", "float", "clear", "box-sizing",
  "width", "height", "min-width", "max-width", "min-height", "max-height",
  "margin-top", "margin-right", "margin-bottom", "margin-left",
  "padding-top", "padding-right", "padding-bottom", "padding-left",
  "border-top-width", "border-right-width", "border-bottom-width", "border-left-width",
  "border-top-style", "border-right-style", "border-bottom-style", "border-left-style",
  "border-top-color", "border-right-color", "border-bottom-color", "border-left-color",
  "border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius", "border-bottom-left-radius",
  "overflow-x", "overflow-y", "visibility", "opacity", "color", "background-color", "background-image",
  "background-size", "background-position", "background-repeat",
  "font-family", "font-size", "font-weight", "font-style", "line-height", "letter-spacing", "text-align",
  "text-transform", "text-decoration-line", "white-space", "word-break", "vertical-align",
  "flex-direction", "flex-wrap", "justify-content", "align-items", "align-content", "align-self",
  "flex-grow", "flex-shrink", "flex-basis", "order", "row-gap", "column-gap",
  "grid-template-columns", "grid-template-rows", "grid-column-start", "grid-column-end", "grid-row-start", "grid-row-end",
  "transform", "transition-property", "box-shadow", "outline-width", "cursor", "pointer-events", "object-fit",
  "aspect-ratio", "text-overflow", "list-style-type", "table-layout", "border-collapse"
];

// 頁內收集器（在瀏覽器裡執行）。以字串傳入 Runtime.evaluate；PROPS 以 JSON 內嵌。
const COLLECTOR = `(() => {
  const PROPS = ${JSON.stringify(PROPS)};
  const SKIP = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "TEMPLATE", "LINK", "META", "TITLE", "HEAD"]);
  const normId = (id) => id
    .replace(/template--(?:\\d+|[a-z0-9.\\-]+)__/, "template--T__")
    .replace(/sections--(?:\\d+|[a-z0-9-]+)__/, "sections--G__")
    .replace(/\\bA[A-Za-z0-9]{17}__/g, "B__");
  const out = [];
  const walk = (el, path, section) => {
    if (SKIP.has(el.tagName)) return;
    if (el.classList.contains("shopify-section") && el.id.startsWith("shopify-section-")) {
      section = normId(el.id.slice("shopify-section-".length));
      path = "";
    }
    let idx = 1;
    for (let s = el.previousElementSibling; s; s = s.previousElementSibling) if (s.tagName === el.tagName) idx++;
    const key = (path ? path + ">" : "") + el.tagName.toLowerCase() + (idx > 1 ? ":" + idx : "");
    const cs = getComputedStyle(el);
    const r = el.getBoundingClientRect();
    const css = {};
    for (const k of PROPS) css[k] = cs.getPropertyValue(k);
    out.push({ section: section || "__root__", key, tag: el.tagName.toLowerCase(),
               rect: [r.x, r.y, r.width, r.height].map((v) => Math.round(v * 2) / 2), css });
    // 內嵌 <svg> 只比 svg 自身的盒（width／height／位置），不進入子節點：佔位插圖本體是鐵律 22.3 唯一例外（HTML 對表同樣以
    // [placeholder] 抹本體；Ella 的 image_url 佔位 svg 沒有 placeholder-svg class），圖示 path 幾何由 svg 盒＋viewBox 決定、
    // 其標記差異由 HTML 對表負責。
    if (el.tagName === "svg" || el.tagName === "SVG") return;
    for (const c of el.children) walk(c, key, section);
  };
  walk(document.body, "", null);
  return { url: location.href, width: innerWidth, height: innerHeight, ua: navigator.userAgent,
           count: out.length, elements: out };
})()`;

function parseArgs(argv) {
  const pos = [];
  const opt = {};
  for (let i = 0; i < argv.length; i++) {
    if (argv[i].startsWith("--")) { opt[argv[i].slice(2)] = argv[i + 1]; i++; } else pos.push(argv[i]);
  }
  return { pos, opt };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function chromePath(opt) {
  return opt.chrome || process.env.CHROME_PATH ||
    (process.platform === "win32" ? "C:/Program Files/Google/Chrome/Application/chrome.exe" : "google-chrome");
}

async function launchChrome(opt, width, height) {
  const port = 9222 + Math.floor(Math.random() * 500);
  const profile = mkdtempSync(join(tmpdir(), "cl-computed-parity-"));
  const child = spawn(chromePath(opt), [
    "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-first-run", "--no-default-browser-check",
    "--disable-extensions", `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
    `--window-size=${width},${height}`, "about:blank"
  ], { stdio: "ignore" });
  const deadline = Date.now() + 20000;
  while (Date.now() < deadline) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`);
      const list = await res.json();
      const page = list.find((t) => t.type === "page");
      if (page) return { child, port, ws: page.webSocketDebuggerUrl };
    } catch { /* not ready */ }
    await sleep(250);
  }
  child.kill();
  throw new Error("Chrome 未在 20 秒內開出 remote-debugging 端口");
}

class Cdp {
  constructor(ws) { this.ws = ws; this.id = 0; this.pending = new Map(); this.events = []; }
  static async connect(url) {
    const ws = new WebSocket(url);
    await new Promise((res, rej) => { ws.onopen = res; ws.onerror = (e) => rej(new Error("CDP 連線失敗: " + (e.message || url))); });
    const c = new Cdp(ws);
    ws.onmessage = (m) => {
      const msg = JSON.parse(m.data);
      if (msg.id && c.pending.has(msg.id)) {
        const { res, rej } = c.pending.get(msg.id); c.pending.delete(msg.id);
        msg.error ? rej(new Error(msg.error.message)) : res(msg.result);
      } else if (msg.method) c.events.push(msg);
    };
    return c;
  }
  send(method, params = {}) {
    const id = ++this.id;
    this.ws.send(JSON.stringify({ id, method, params }));
    return new Promise((res, rej) => this.pending.set(id, { res, rej }));
  }
  async waitEvent(method, timeoutMs) {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const i = this.events.findIndex((e) => e.method === method);
      if (i >= 0) return this.events.splice(i, 1)[0];
      await sleep(50);
    }
    throw new Error(`等 ${method} 逾時 ${timeoutMs}ms`);
  }
  close() { this.ws.close(); }
}

async function capture(pos, opt) {
  const [url, out] = pos;
  if (!url || !out) throw new Error("capture 需要 <url> <out.json>");
  const width = Number(opt.width || 1280);
  const height = Number(opt.height || 900);
  const settle = Number(opt.wait || 1500);
  const { child, ws } = await launchChrome(opt, width, height);
  try {
    const cdp = await Cdp.connect(ws);
    await cdp.send("Page.enable");
    await cdp.send("Runtime.enable");
    await cdp.send("Network.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: width < 768 });
    await cdp.send("Page.navigate", { url });
    await cdp.waitEvent("Page.loadEventFired", 60000);
    await cdp.send("Runtime.evaluate", { expression: "document.fonts.ready.then(() => true)", awaitPromise: true });
    // --open-details 1：把所有 <details> 打開再量（Ella 的搜尋 modal／選單放在 details 裡；關閉狀態下子樹雖有 layout，
    // 但兩邊在該子樹的報告值可能不同——E12 首輪 header 搜尋圖示 25px vs 18px 只出現在關閉的 details 內，開啟後比較才是使用者看得到的形）。
    if (opt["open-details"]) {
      await cdp.send("Runtime.evaluate", { expression: "document.querySelectorAll('details').forEach((d) => { d.open = true; }); true" });
    }
    await sleep(settle); // 主題 JS（animate-image／marquee 等）的初始化
    const r = await cdp.send("Runtime.evaluate", { expression: COLLECTOR, returnByValue: true });
    if (r.exceptionDetails) throw new Error("收集器例外: " + JSON.stringify(r.exceptionDetails).slice(0, 300));
    // 診斷：頁內例外、console error／warn、載入失敗與 4xx／5xx 回應——元素數差異常常是主題 JS 沒跑完（缺資產／例外），
    // 這些是根因證據，不是對表結果本身。
    const diagnostics = { exceptions: [], console: [], failed: [], http: [] };
    for (const e of cdp.events) {
      if (e.method === "Runtime.exceptionThrown") {
        const d = e.params.exceptionDetails;
        diagnostics.exceptions.push(`${d.text || ""} ${d.exception?.description || ""} @${d.url || ""}:${d.lineNumber ?? ""}`.trim().slice(0, 300));
      } else if (e.method === "Runtime.consoleAPICalled" && (e.params.type === "error" || e.params.type === "warning")) {
        diagnostics.console.push(`${e.params.type}: ${e.params.args.map((a) => a.value ?? a.description ?? "").join(" ").slice(0, 200)}`);
      } else if (e.method === "Network.loadingFailed") {
        diagnostics.failed.push(`${e.params.errorText} ${e.params.type} ${e.params.requestId}`);
      } else if (e.method === "Network.responseReceived" && e.params.response.status >= 400) {
        diagnostics.http.push(`${e.params.response.status} ${e.params.response.url.slice(0, 160)}`);
      }
    }
    const data = { capturedAt: new Date().toISOString(), requestedWidth: width, requestedHeight: height, ...r.result.value, diagnostics };
    writeFileSync(out, JSON.stringify(data));
    console.log(`captured ${data.count} elements @${data.width}x${data.height} ${url} => ${out}`);
    console.log(`diagnostics: exceptions=${diagnostics.exceptions.length} console=${diagnostics.console.length} failed=${diagnostics.failed.length} http>=400=${diagnostics.http.length}`);
    for (const line of [...diagnostics.exceptions, ...diagnostics.http].slice(0, 12)) console.log("  " + line);
    cdp.close();
  } finally {
    child.kill();
  }
}

// inspect：列出第一個符合 selector 的元素所命中的 CSS 規則（selector、來源樣式表、宣告），用來找「同標記不同 computed」的根因
// （例：本尊 CDN 對主題 CSS 做過巢狀攤平／前綴／壓縮，我方直出原檔）。--props 逗號清單（預設 width,height,min-width,min-height）；--all 1 列全部宣告。
async function inspect(pos, opt) {
  const [url, selector] = pos;
  if (!url || !selector) throw new Error("inspect 需要 <url> <selector>");
  const width = Number(opt.width || 1280);
  const height = Number(opt.height || 900);
  const { child, ws } = await launchChrome(opt, width, height);
  try {
    const cdp = await Cdp.connect(ws);
    await cdp.send("Page.enable"); await cdp.send("Runtime.enable"); await cdp.send("DOM.enable"); await cdp.send("CSS.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: width < 768 });
    await cdp.send("Page.navigate", { url });
    await cdp.waitEvent("Page.loadEventFired", 60000);
    await sleep(Number(opt.wait || 1500));
    const doc = await cdp.send("DOM.getDocument", { depth: 0 });
    const { nodeId } = await cdp.send("DOM.querySelector", { nodeId: doc.root.nodeId, selector });
    if (!nodeId) throw new Error("selector 無命中: " + selector);
    const sheets = new Map();
    for (const e of cdp.events) if (e.method === "CSS.styleSheetAdded") sheets.set(e.params.header.styleSheetId, e.params.header.sourceURL || `(inline ${e.params.header.origin})`);
    const m = await cdp.send("CSS.getMatchedStylesForNode", { nodeId });
    const computed = await cdp.send("CSS.getComputedStyleForNode", { nodeId });
    const want = new Set((opt.props || "width,height,min-width,min-height").split(","));
    console.log(`# ${url} :: ${selector}`);
    console.log("computed:", computed.computedStyle.filter((p) => want.has(p.name)).map((p) => `${p.name}=${p.value}`).join(" "));
    for (const r of (m.matchedCSSRules || []).slice().reverse()) {
      const rule = r.rule;
      const decls = rule.style.cssProperties.filter((p) => opt.all || want.has(p.name) || p.name.startsWith("--icon")).map((p) => `${p.name}:${p.value}${p.important ? "!important" : ""}`);
      if (!decls.length) continue;
      console.log(`- [${rule.origin}] ${sheets.get(rule.styleSheetId) || rule.styleSheetId || "?"}\n    ${rule.selectorList.text}  { ${decls.join("; ")} }`);
    }
    cdp.close();
  } finally {
    child.kill();
  }
}

// evaljs：在頁面載入（＋settle）後執行一段 JS（--file <path> 或第二個位置參數），印出 JSON 結果——取證用（鐵律 14／19）。
async function evaljs(pos, opt) {
  const [url, inlineJs] = pos;
  const js = opt.file ? readFileSync(opt.file, "utf8") : inlineJs;
  if (!url || !js) throw new Error("evaljs 需要 <url> <js|--file path>");
  const width = Number(opt.width || 1280);
  const height = Number(opt.height || 900);
  const { child, ws } = await launchChrome(opt, width, height);
  try {
    const cdp = await Cdp.connect(ws);
    await cdp.send("Page.enable"); await cdp.send("Runtime.enable");
    await cdp.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: width < 768 });
    await cdp.send("Page.navigate", { url });
    await cdp.waitEvent("Page.loadEventFired", 60000);
    await sleep(Number(opt.wait || 1500));
    const r = await cdp.send("Runtime.evaluate", { expression: js, returnByValue: true, awaitPromise: true });
    if (r.exceptionDetails) throw new Error("evaljs 例外: " + JSON.stringify(r.exceptionDetails).slice(0, 400));
    console.log(JSON.stringify(r.result.value, null, 1));
    cdp.close();
  } finally {
    child.kill();
  }
}

// 值正規化：只抹身分差（主機、CDN 主題資產路徑與版本、data: 內容）。
function normalizeValue(v) {
  return String(v)
    .replace(/https?:\/\/[^/"')\s]+/g, "")
    .replace(/\/cdn\/shop\/t\/\d+\/assets\//g, "/theme-assets/")
    .replace(/\?v=\d+/g, "")
    .replace(/data:[^"')]+/g, "data:[data]");
}

// 純 px 值容許 0.5px（次像素文字量測在不同機器／字型光柵下的噪音，與 rect 同一容差）；其餘字串精確比對。
function withinPx(a, b) {
  const m = /^(-?\d+(?:\.\d+)?)px$/;
  const x = m.exec(a); const y = m.exec(b);
  return !!(x && y && Math.abs(Number(x[1]) - Number(y[1])) <= 0.5);
}

function diffData(ref, cand, limit = 60) {
  const bySection = (d) => {
    const m = new Map();
    for (const e of d.elements) {
      if (!m.has(e.section)) m.set(e.section, new Map());
      m.get(e.section).set(e.key, e);
    }
    return m;
  };
  const R = bySection(ref);
  const C = bySection(cand);
  const sections = [...new Set([...R.keys(), ...C.keys()])];
  const rows = [];
  const details = [];
  for (const s of sections) {
    const r = R.get(s) || new Map();
    const c = C.get(s) || new Map();
    let identical = 0;
    let matched = 0;
    const diffs = [];
    for (const [k, re] of r) {
      const ce = c.get(k);
      if (!ce) { diffs.push({ key: k, prop: "(element)", ref: re.tag, cand: "(missing)" }); continue; }
      matched++;
      let same = true;
      for (let i = 0; i < 4; i++) {
        if (Math.abs(re.rect[i] - ce.rect[i]) > 0.5) { same = false; diffs.push({ key: k, prop: ["rect.x", "rect.y", "rect.w", "rect.h"][i], ref: re.rect[i], cand: ce.rect[i] }); }
      }
      for (const p of PROPS) {
        const a = normalizeValue(re.css[p]);
        const b = normalizeValue(ce.css[p]);
        if (a !== b && !withinPx(a, b)) { same = false; diffs.push({ key: k, prop: p, ref: a, cand: b }); }
      }
      if (same) identical++;
    }
    for (const k of c.keys()) if (!r.has(k)) diffs.push({ key: k, prop: "(element)", ref: "(missing)", cand: c.get(k).tag });
    const denom = Math.max(r.size, c.size, 1);
    const score = identical / denom;
    rows.push({ section: s, ref: r.size, cand: c.size, matched, identical, score, diffCount: diffs.length });
    if (diffs.length) details.push({ section: s, diffs: diffs.slice(0, limit), total: diffs.length });
  }
  rows.sort((a, b) => a.score - b.score);
  const identicalSections = rows.filter((x) => x.diffCount === 0).length;
  return { rows, details, identicalSections, sections: rows.length };
}

function toMarkdown(ref, cand, result) {
  const lines = [];
  lines.push(`# computed parity: ${ref.url} vs ${cand.url}`, "");
  lines.push(`viewport ${ref.width}x${ref.height} vs ${cand.width}x${cand.height}；元素 ${ref.count} vs ${cand.count}；` +
             `段落 ${result.identicalSections}/${result.sections} 逐屬性全同`, "");
  lines.push("| section | ref elems | cand elems | matched | identical | score | diffs |", "|---|---|---|---|---|---|---|");
  for (const r of result.rows) lines.push(`| ${r.section} | ${r.ref} | ${r.cand} | ${r.matched} | ${r.identical} | ${r.score.toFixed(3)} | ${r.diffCount} |`);
  for (const d of result.details) {
    lines.push("", `## ${d.section}（${d.total} 差異，列前 ${d.diffs.length}）`, "", "| key | prop | ref | cand |", "|---|---|---|---|");
    for (const x of d.diffs) lines.push(`| ${x.key} | ${x.prop} | ${String(x.ref).replace(/\|/g, "\\|").slice(0, 80)} | ${String(x.cand).replace(/\|/g, "\\|").slice(0, 80)} |`);
  }
  return lines.join("\n") + "\n";
}

function diff(pos, opt) {
  const [a, b] = pos;
  if (!a || !b) throw new Error("diff 需要 <ref.json> <cand.json>");
  const ref = JSON.parse(readFileSync(a, "utf8"));
  const cand = JSON.parse(readFileSync(b, "utf8"));
  const result = diffData(ref, cand, Number(opt.limit || 60));
  const md = toMarkdown(ref, cand, result);
  if (opt.out) { writeFileSync(opt.out, md); console.log(`report => ${opt.out}`); } else process.stdout.write(md);
  const worst = result.rows[0];
  console.log(`sections: ${result.sections}; identical: ${result.identicalSections}; worst: ${worst ? `${worst.section} ${worst.score.toFixed(3)}` : "-"}`);
}

// 自測：同形 ⇒ 全同；一個屬性差、一個幾何差、缺元素各自被列出；身分差（主機／版本）被抹掉。
function selftest() {
  const el = (section, key, css = {}, rect = [0, 0, 10, 10]) => ({ section, key, tag: "div", rect, css: Object.fromEntries(PROPS.map((p) => [p, css[p] ?? "x"])) });
  const ref = { url: "r", width: 1280, height: 900, count: 3, elements: [
    el("template--T__hero", "div"), el("template--T__hero", "div>p", { "font-size": "16px", "background-image": 'url("https://hoko.vip/cdn/shop/t/2/assets/a.png?v=1")' }),
    el("footer", "div") ] };
  const cand = { url: "c", width: 1280, height: 900, count: 3, elements: [
    el("template--T__hero", "div"), el("template--T__hero", "div>p", { "font-size": "15px", "background-image": 'url("https://mirror.example/theme-assets/a.png")' }, [0, 0, 10, 12]),
    el("footer", "div>span") ] };
  const same = diffData(ref, ref);
  if (same.identicalSections !== 2) throw new Error("selftest: 同形應全同");
  const r = diffData(ref, cand);
  const hero = r.details.find((d) => d.section === "template--T__hero");
  const props = hero.diffs.map((d) => d.prop);
  if (!props.includes("font-size") || !props.includes("rect.h")) throw new Error("selftest: 屬性差／幾何差未列出 " + props);
  if (props.includes("background-image")) throw new Error("selftest: 身分差（主機／CDN／版本）未抹掉");
  const footer = r.details.find((d) => d.section === "footer");
  if (!footer || footer.diffs.filter((d) => d.prop === "(element)").length !== 2) throw new Error("selftest: 缺元素未雙向列出");
  if (r.rows.find((x) => x.section === "template--T__hero").score !== 0.5) throw new Error("selftest: score 應為 identical/max(n)");
  console.log("selftest OK");
}

const { pos, opt } = parseArgs(process.argv.slice(2));
const cmd = pos.shift();
try {
  if (cmd === "capture") await capture(pos, opt);
  else if (cmd === "diff") diff(pos, opt);
  else if (cmd === "inspect") await inspect(pos, opt);
  else if (cmd === "evaljs") await evaljs(pos, opt);
  else if (cmd === "selftest") selftest();
  else { console.error("用法見檔頭：capture | diff | inspect | evaljs | selftest"); process.exit(2); }
} catch (e) {
  console.error(String(e.stack || e));
  process.exit(1);
}
