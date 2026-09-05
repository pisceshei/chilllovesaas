// 本尊 `shopify-perf-kit-{ver}.min.js` 的對位（我方自寫）：送 navigation timing 到 script 標籤上宣告的 `data-shs-beacon-endpoint`。
(function () {
  "use strict";
  var me = document.currentScript;
  if (!me || !me.dataset.shsBeaconEndpoint) return;
  window.addEventListener("load", function () {
    try {
      var nav = performance.getEntriesByType("navigation")[0];
      var payload = { schema_id: "storefront_perf_kit/1.0", payload: {
        page_type: me.dataset.pageType, shop_id: me.dataset.shopId, theme_instance_id: me.dataset.themeInstanceId,
        dom_content_loaded: nav ? Math.round(nav.domContentLoadedEventEnd) : null, load: nav ? Math.round(nav.loadEventEnd) : null, url: location.href } };
      var body = JSON.stringify(payload);
      if (navigator.sendBeacon) navigator.sendBeacon(me.dataset.shsBeaconEndpoint, new Blob([body], { type: "text/plain" }));
    } catch (e) {}
  });
})();
