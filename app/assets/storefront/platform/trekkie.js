// trekkie（本尊 `trekkie.storefront.{hash}.min.js`）的對位——我方自寫的最小 analytics 客戶端：
// 重放 head stub 佇列（identify／page／track／trackForm／trackLink／ready），事件以 sendBeacon 送我方收集端 `/api/collect`。
(function (w) {
  "use strict";
  var t = w.trekkie = w.trekkie || [];
  if (t.integrations) return;
  var readyCbs = [];
  var lib = {
    integrations: {},
    config: t.config || {},
    send: function (method, args) {
      var payload = { schema_id: "trekkie_storefront/1.0", payload: { method: method, args: args, url: location.href, at: Date.now() } };
      try {
        var body = JSON.stringify(payload);
        if (navigator.sendBeacon) navigator.sendBeacon("/api/collect", new Blob([body], { type: "text/plain" }));
        else fetch("/api/collect", { method: "POST", body: body, keepalive: true }).catch(function () {});
      } catch (e) {}
    },
    identify: function () { lib.send("identify", Array.prototype.slice.call(arguments)); },
    page: function () { lib.send("page", Array.prototype.slice.call(arguments)); },
    track: function () { lib.send("track", Array.prototype.slice.call(arguments)); },
    trackForm: function () {},
    trackLink: function () {},
    load: function (config) { lib.config = config || {}; },
    ready: function (cb) { if (typeof cb === "function") cb(); }
  };
  var queue = t.splice ? t.splice(0, t.length) : [];
  for (var k in lib) t[k] = lib[k];
  w.ShopifyAnalytics = w.ShopifyAnalytics || {};
  w.ShopifyAnalytics.lib = t;
  queue.forEach(function (call) {
    var method = call[0], args = call.slice(1);
    if (method === "ready") readyCbs.push(args[0]); else if (lib[method]) lib[method].apply(lib, args);
  });
  readyCbs.forEach(function (cb) { try { cb(); } catch (e) { console.error(e); } });
})(window);
