// 平台功能載入器（本尊 `load_feature-{hash}.js` 的對位；E19，我方自寫）。
// 介面：`Shopify.loadFeatures([{name, version, onLoad}], callback)`／`Shopify.autoloadFeatures(...)`——head 的佇列 stub 先收呼叫，
// 本檔載入後重放。已知功能名（主題用法：Ella product-model.js 的 shopify-xr／model-viewer-ui；consent-tracking-api）給最小可用實作，
// 其餘視為已載入（callback(null)）。真正的 3D／影片／同意 API＝後續包（91 §3.88）。
(function (w) {
  "use strict";
  var S = w.Shopify = w.Shopify || {};
  var features = {
    "shopify-xr": function () {
      w.ShopifyXR = w.ShopifyXR || { setupXRElements: function () {}, addModels: function () {}, launchXR: function () {} };
    },
    "model-viewer-ui": function () {
      S.ModelViewerUI = S.ModelViewerUI || function (el) { this.el = el; };
      S.ModelViewerUI.prototype.play = S.ModelViewerUI.prototype.play || function () {};
      S.ModelViewerUI.prototype.pause = S.ModelViewerUI.prototype.pause || function () {};
      S.ModelViewerUI.prototype.destroy = S.ModelViewerUI.prototype.destroy || function () {};
    },
    "video-ui": function () {
      S.Video = S.Video || { init: function () {}, loadVideos: function () {} };
    },
    "consent-tracking-api": function () {
      if (S.customerPrivacy) return;
      var consent = { marketing: "yes", analytics: "yes", preferences: "yes", sale_of_data: "no" };
      S.customerPrivacy = {
        currentVisitorConsent: function () { return consent; },
        shouldShowBanner: function () { return false; },
        userCanBeTracked: function () { return true; },
        getTrackingConsent: function () { return "yes"; },
        setTrackingConsent: function (value, cb) {
          if (typeof value === "object") { for (var k in value) consent[k] = value[k] ? "yes" : "no"; }
          if (typeof cb === "function") cb();
        },
        saleOfDataRegion: function () { return false; },
        analyticsProcessingAllowed: function () { return true; },
        marketingAllowed: function () { return true; },
        preferencesProcessingAllowed: function () { return true; },
        saleOfDataAllowed: function () { return true; }
      };
      S.trackingConsent = S.customerPrivacy;
    }
  };
  function load(list, callback) {
    var items = Array.isArray(list) ? list : [];
    for (var i = 0; i < items.length; i++) {
      var f = items[i] || {};
      var init = features[f.name];
      if (init) init();
      if (typeof f.onLoad === "function") { try { f.onLoad(null); } catch (e) { console.error(e); } }
    }
    if (typeof callback === "function") { try { callback(null); } catch (e) { console.error(e); } }
  }
  var queued = (S.loadFeatures && S.loadFeatures.q) || [];
  var autoQueued = (S.autoloadFeatures && S.autoloadFeatures.q) || [];
  S.loadFeatures = load;
  S.autoloadFeatures = load;
  for (var j = 0; j < queued.length; j++) load.apply(null, queued[j]);
  for (var k = 0; k < autoQueued.length; k++) load.apply(null, autoQueued[k]);
})(window);
