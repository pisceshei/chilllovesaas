// 本尊 `shop_events_listener-{hash}.js` 的對位（我方自寫）：把主題派發的 `shopify:*` 自訂事件轉給 web pixels 佇列。
(function (w) {
  "use strict";
  var names = ["shopify:cart:updated", "shopify:section:load", "shopify:section:unload", "shopify:block:select"];
  names.forEach(function (n) {
    document.addEventListener(n, function (e) {
      try { if (w.Shopify && w.Shopify.analytics && w.Shopify.analytics.publish) w.Shopify.analytics.publish(n, e.detail || {}); } catch (err) {}
    });
  });
})(window);
