/*
 * 主題編輯器預覽橋（E6；design_mode 專屬，由引擎於 </body> 前注入；`docs/research/100` §5／§9.5）。
 *
 * ①這是什麼：跑在預覽 iframe 裡的腳本，與父頁（ThemeEditorPage）以 postMessage 同源通訊（origin 嚴格比對）。
 * ②父 → 子：`cl:highlight {id, blockId}`（選中：藍框＋捲到＋浮動工具列＋派 shopify:section/block:select）、
 *   `cl:replace {id, html}`（換段後派 shopify:section:load）、`cl:inspector {active}`（關 ⇒ 不畫 hover 覆疊；派
 *   shopify:inspector:activate/deactivate）、`cl:names {sections:{id:label}, blocks:{sectionId:{blockId:label}}}`（chip 文字）。
 * ③子 → 父：`cl:select {id, blockId}`（點選）、`cl:op {op, id, blockId}`（工具列：duplicate／hide／remove）、
 *   `cl:insert {id, position}`（section 上下邊界「+」⇒ 父頁開區段 picker）、`cl:contextmenu {id, blockId, x, y}`（右鍵 ⇒
 *   父頁開同款選單）、`cl:navigate {path}`（站內連結攔截）。
 * ④本尊形態（100 §5）：hover＝藍框＋左上 chip（type icon＋名稱，藍底白字）；section 上下邊界各一顆藍色圓形「+」；點選 ⇒
 *   左樹展開、右欄開面板、預覽捲到；浮動工具列（選中元素下方置中）＝Sidekick｜Duplicate｜Hide｜Remove（Sidekick 我方無，
 *   登記）；右鍵 block ⇒ 選單；inspector 關 ⇒ 無覆疊。視覺自有（鐵律 9）：藍＝我方 `--link` #005bd3。
 * ⑤官方事件（§9.5 逐字）：`shopify:section:load`／`unload`／`select`／`deselect`／`reorder`、`shopify:block:select`／`deselect`、
 *   `shopify:inspector:activate`／`deactivate`（bubble，target＝section／block 元素）。
 */
(function () {
  "use strict";
  var ORIGIN = window.location.origin;
  var state = { inspector: true, names: { sections: {}, blocks: {} }, labels: {}, selected: null, hover: null };

  function sectionKey(domId) {
    var raw = String(domId).replace("shopify-section-", "");
    var i = raw.lastIndexOf("__");
    return i >= 0 ? raw.slice(i + 2) : raw;
  }
  function findSection(key) {
    return document.getElementById("shopify-section-" + key)
      || document.querySelector("[id^='shopify-section-'][id$='__" + key + "']");
  }
  function blockData(el) {
    try { return JSON.parse(el.getAttribute("data-shopify-editor-block")); } catch (e) { return null; }
  }
  function findBlock(sectionEl, blockId) {
    var hit = null;
    sectionEl.querySelectorAll("[data-shopify-editor-block]").forEach(function (b) {
      var d = blockData(b);
      if (d && d.id === blockId && !hit) hit = b;
    });
    return hit;
  }
  function labelFor(id, blockId) {
    if (blockId) return (state.names.blocks[id] || {})[blockId] || blockId;
    return state.names.sections[id] || id;
  }
  function post(msg) { window.parent.postMessage(msg, ORIGIN); }
  function dispatch(el, name, detail) {
    if (!el) return;
    el.dispatchEvent(new CustomEvent(name, { bubbles: true, detail: detail || {} }));
  }

  // ── 覆疊層（自有視覺；全部 pointer-events 由各件自訂） ──
  var style = document.createElement("style");
  style.textContent = [
    ".cl-ov-box{position:absolute;pointer-events:none;border:2px solid #005bd3;box-sizing:border-box;z-index:2147483645;display:none}",
    ".cl-ov-box.is-selected{border-color:#005bd3}",
    ".cl-ov-chip{position:absolute;display:none;align-items:center;gap:4px;background:#005bd3;color:#fff;font:12px/16px system-ui,sans-serif;padding:2px 6px;border-radius:4px 4px 4px 0;z-index:2147483646;pointer-events:none;white-space:nowrap}",
    ".cl-ov-insert{position:absolute;display:none;width:20px;height:20px;margin:-10px 0 0 -10px;border:0;border-radius:50%;background:#005bd3;color:#fff;font:16px/20px system-ui,sans-serif;text-align:center;cursor:pointer;z-index:2147483646;box-shadow:0 1px 2px rgba(0,0,0,.3)}",
    ".cl-ov-bar{position:absolute;display:none;gap:2px;background:#303030;border-radius:8px;padding:4px;z-index:2147483646;box-shadow:0 4px 6px -2px rgba(26,26,26,.2)}",
    ".cl-ov-bar button{all:unset;color:#fff;font:12px/16px system-ui,sans-serif;padding:4px 8px;border-radius:4px;cursor:pointer}",
    ".cl-ov-bar button:hover{background:rgba(255,255,255,.12)}",
  ].join("");
  var hoverBox = el("div", "cl-ov-box"), chip = el("div", "cl-ov-chip"), selBox = el("div", "cl-ov-box is-selected");
  var insertTop = el("button", "cl-ov-insert"), insertBottom = el("button", "cl-ov-insert"), bar = el("div", "cl-ov-bar");
  insertTop.type = insertBottom.type = "button";
  insertTop.textContent = insertBottom.textContent = "+";
  insertTop.title = insertBottom.title = "Add section";
  insertTop.setAttribute("data-cl-insert", "before");
  insertBottom.setAttribute("data-cl-insert", "after");
  [["duplicate", "Duplicate"], ["hide", "Hide"], ["remove", "Remove"]].forEach(function (pair) {
    var b = document.createElement("button");
    b.type = "button"; b.textContent = pair[1]; b.setAttribute("data-cl-op", pair[0]);
    bar.appendChild(b);
  });
  function el(tag, cls) { var n = document.createElement(tag); n.className = cls; return n; }
  function mount() {
    document.head.appendChild(style);
    [hoverBox, chip, selBox, insertTop, insertBottom, bar].forEach(function (n) { document.body.appendChild(n); });
    hideAll(false); // inline display:none（不靠樣式表；jsdom 也一致）
  }
  if (document.body) mount(); else document.addEventListener("DOMContentLoaded", mount);

  function rectOf(target) {
    var r = target.getBoundingClientRect();
    return { top: window.scrollY + r.top, left: window.scrollX + r.left, width: r.width, height: r.height, bottom: window.scrollY + r.bottom };
  }
  function placeBox(box, target) {
    var r = rectOf(target);
    box.style.display = "block";
    box.style.top = r.top + "px"; box.style.left = r.left + "px";
    box.style.width = r.width + "px"; box.style.height = r.height + "px";
  }
  function hideAll(keepSelection) {
    hoverBox.style.display = "none"; chip.style.display = "none";
    insertTop.style.display = "none"; insertBottom.style.display = "none";
    if (!keepSelection) { selBox.style.display = "none"; bar.style.display = "none"; }
  }

  // ── hover：藍框＋chip；section 邊界「+」 ──
  document.addEventListener("mouseover", function (ev) {
    if (!state.inspector) return;
    var target = ev.target && ev.target.closest ? ev.target : null;
    if (!target) return;
    if (target.closest(".cl-ov-bar, .cl-ov-insert")) return; // 覆疊件自己不算 hover
    var blockEl = target.closest("[data-shopify-editor-block]");
    var host = target.closest("[id^='shopify-section-']");
    if (!host) { hideAll(true); state.hover = null; return; }
    var id = sectionKey(host.id);
    var bd = blockEl && host.contains(blockEl) ? blockData(blockEl) : null;
    var focus = bd ? blockEl : host;
    state.hover = { id: id, blockId: bd ? bd.id : null };
    placeBox(hoverBox, focus);
    var r = rectOf(focus);
    chip.textContent = labelFor(id, bd ? bd.id : null);
    chip.style.display = "flex";
    chip.style.top = Math.max(0, r.top - 20) + "px"; chip.style.left = r.left + "px";
    // section 上下邊界「+」（Add section）——只在 hover section 本體時（block 上不出）
    var hr = rectOf(host);
    var cx = hr.left + hr.width / 2;
    insertTop.style.display = "block"; insertTop.style.top = hr.top + "px"; insertTop.style.left = cx + "px";
    insertBottom.style.display = "block"; insertBottom.style.top = hr.bottom + "px"; insertBottom.style.left = cx + "px";
    insertTop.setAttribute("data-cl-section", id); insertBottom.setAttribute("data-cl-section", id);
  });
  [insertTop, insertBottom].forEach(function (b) {
    b.addEventListener("click", function (ev) {
      ev.preventDefault(); ev.stopPropagation();
      post({ type: "cl:insert", id: b.getAttribute("data-cl-section"), position: b.getAttribute("data-cl-insert") });
    });
  });

  // ── 浮動工具列（選中元素下方置中） ──
  bar.addEventListener("click", function (ev) {
    var op = ev.target && ev.target.getAttribute && ev.target.getAttribute("data-cl-op");
    if (!op || !state.selected) return;
    ev.preventDefault(); ev.stopPropagation();
    post({ type: "cl:op", op: op, id: state.selected.id, blockId: state.selected.blockId || null });
  });
  function showBar(target) {
    var r = rectOf(target);
    bar.style.display = "flex";
    bar.style.top = (r.bottom + 6) + "px";
    var w = bar.offsetWidth || 180;
    bar.style.left = Math.max(0, r.left + r.width / 2 - w / 2) + "px";
  }

  // ── 點選 ⇒ 父頁；右鍵 ⇒ 父頁開選單；站內連結攔截 ──
  document.addEventListener("click", function (ev) {
    if (ev.target.closest && ev.target.closest(".cl-ov-bar, .cl-ov-insert")) return;
    var link = ev.target.closest ? ev.target.closest("a[href]") : null;
    if (link) {
      var href = link.getAttribute("href") || "";
      if (href.charAt(0) === "/" && href.indexOf("/admin/") !== 0) {
        ev.preventDefault();
        post({ type: "cl:navigate", path: href });
      }
    }
    var host = ev.target.closest ? ev.target.closest("[id^='shopify-section-']") : null;
    if (!host) return;
    var msg = { type: "cl:select", id: sectionKey(host.id) };
    var blockEl = ev.target.closest("[data-shopify-editor-block]");
    if (blockEl && host.contains(blockEl)) { var bd = blockData(blockEl); if (bd) msg.blockId = bd.id; }
    post(msg);
  }, true);
  document.addEventListener("contextmenu", function (ev) {
    if (!state.inspector) return;
    var host = ev.target.closest ? ev.target.closest("[id^='shopify-section-']") : null;
    if (!host) return;
    ev.preventDefault();
    var msg = { type: "cl:contextmenu", id: sectionKey(host.id), blockId: null, x: ev.clientX, y: ev.clientY };
    var blockEl = ev.target.closest("[data-shopify-editor-block]");
    if (blockEl && host.contains(blockEl)) { var bd = blockData(blockEl); if (bd) msg.blockId = bd.id; }
    post(msg);
  });

  // ── 父 → 子 ──
  window.addEventListener("message", function (ev) {
    if (ev.origin !== ORIGIN) return;
    var d = ev.data || {};
    if (d.type === "cl:names" && d.sections) {
      state.names = { sections: d.sections || {}, blocks: d.blocks || {} };
      // 工具列／插入點文字跟 admin 語系（父頁 t()），不寫死英文
      if (d.labels) {
        state.labels = d.labels;
        insertTop.title = insertBottom.title = d.labels.addSection || insertTop.title;
        bar.querySelectorAll("button").forEach(function (btn) {
          var key = btn.getAttribute("data-cl-op");
          if (d.labels[key]) btn.textContent = d.labels[key];
        });
      }
      return;
    }
    if (d.type === "cl:inspector") {
      state.inspector = !!d.active;
      if (!state.inspector) hideAll(false);
      dispatch(document, state.inspector ? "shopify:inspector:activate" : "shopify:inspector:deactivate");
      return;
    }
    if (d.type === "cl:highlight") {
      var sectionEl = d.id ? findSection(d.id) : null;
      var target = sectionEl;
      var blockEl = sectionEl && d.blockId ? findBlock(sectionEl, d.blockId) : null;
      if (blockEl) target = blockEl;
      var prev = state.selected;
      if (prev && prev.el && prev.el !== target) {
        dispatch(prev.el, prev.blockId ? "shopify:block:deselect" : "shopify:section:deselect", prev.blockId ? { blockId: prev.blockId, sectionId: prev.id } : { sectionId: prev.id });
      }
      if (!target) { state.selected = null; hideAll(false); return; }
      state.selected = { id: d.id, blockId: blockEl ? d.blockId : null, el: target };
      placeBox(selBox, target);
      if (state.inspector) showBar(target); else bar.style.display = "none";
      if (typeof target.scrollIntoView === "function") target.scrollIntoView({ behavior: "smooth", block: "center" });
      dispatch(target, blockEl ? "shopify:block:select" : "shopify:section:select", blockEl ? { blockId: d.blockId, sectionId: d.id, load: false } : { sectionId: d.id, load: false });
      return;
    }
    if (d.type === "cl:replace") {
      var old = d.id ? findSection(d.id) : null;
      if (old && typeof d.html === "string") {
        var tpl = document.createElement("template");
        tpl.innerHTML = d.html;
        var next = tpl.content.querySelector("[id^='shopify-section-']") || tpl.content.firstElementChild;
        if (next) {
          dispatch(old, "shopify:section:unload", { sectionId: d.id });
          old.replaceWith(next);
          if (state.selected && state.selected.id === d.id) {
            var again = state.selected.blockId ? findBlock(next, state.selected.blockId) : next;
            state.selected.el = again || next;
            placeBox(selBox, state.selected.el);
            if (state.inspector) showBar(state.selected.el);
          }
          dispatch(next, "shopify:section:load", { sectionId: d.id });
        }
      }
    }
  });

  window.addEventListener("scroll", function () {
    if (state.selected && state.selected.el && document.contains(state.selected.el)) {
      placeBox(selBox, state.selected.el);
      if (state.inspector && bar.style.display !== "none") showBar(state.selected.el);
    }
  }, true);
})();
