// `sizes="auto"` polyfill（本尊 `autosizes-{hash}.js` 的對位；我方自寫）：舊瀏覽器不支援 auto-sizes 時，
// 以圖片版面寬度填 sizes；新瀏覽器由 UA 偵測 script 判定不載本檔。
(function () {
  "use strict";
  function apply(img) {
    if (!img || img.getAttribute("sizes") !== "auto") return;
    var w = img.getBoundingClientRect().width || img.clientWidth;
    if (w > 0) img.setAttribute("sizes", Math.round(w) + "px");
  }
  function run() { document.querySelectorAll('img[sizes="auto"]').forEach(apply); }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run, { once: true }); else run();
  window.addEventListener("resize", run);
})();
