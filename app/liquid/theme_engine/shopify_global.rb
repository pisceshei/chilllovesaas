# frozen_string_literal: true

module ThemeEngine
  # 買家面 window.Shopify 全域（Ella 修復 PR-3）。
  #
  # 為什麼：主題 JS 生態依賴本尊 storefront runtime 注入的 window.Shopify——
  # Ella 實際使用面（grep 取證 2026-09-01）：designMode(23)/formatMoney(18)/
  # CountryProvinceSelector(4)/setSelectorByValue(3)/routes.root(3)/
  # onCartUpdate(3)/removeItem(2)/postLink(2)/loadFeatures(2)/getCart(2)/
  # bind(2)/addListener(2)/PaymentButton(2)/currency.active(1)/ModelViewerUI(1)。
  # 缺它＝「Shopify is not defined」連鎖崩（promotion-popup/before-you-leave/
  # predictive-search…全滅——本地 console 實錘）。
  # 形＝ours（本尊該物件無公開文檔；面向以 Ella 用法收斂）；designMode 是
  # 官方文檔明載的偵測介面（shopify.dev theme editor 章）。
  module ShopifyGlobal
    module_function

    # rubocop:disable Metrics/MethodLength
    def script(shop:, theme:, locale:, currency:, root:, design_mode:)
      <<~HTML
        <script>
        window.Shopify = window.Shopify || {};
        Shopify.shop = #{shop.subdomain.to_s.inspect};
        Shopify.locale = #{locale.to_s.inspect};
        Shopify.currency = { active: #{currency.to_s.inspect}, rate: "1.0" };
        #{design_mode ? "Shopify.designMode = true;" : "/* Shopify.designMode: undefined outside the editor (official) */"}
        Shopify.routes = { root: #{root.to_s.inspect} };
        Shopify.theme = { id: #{theme.id}, name: #{theme.name.to_s.inspect}, role: #{theme.role.to_s.inspect} };
        Shopify.formatMoney = function(cents, format) {
          if (typeof cents === "string") cents = cents.replace(/[^0-9.-]/g, "");
          var value = (parseFloat(cents) / 100).toFixed(2);
          var parts = value.split(".");
          parts[0] = parts[0].replace(/\\B(?=(\\d{3})+(?!\\d))/g, ",");
          var amount = parts.join(".");
          var pattern = (format || "${{amount}}");
          return pattern.replace(/\\{\\{\\s*(\\w+)\\s*\\}\\}/, amount);
        };
        Shopify.postLink = function(path, options) {
          options = options || {}; var method = options.method || "post"; var params = options.parameters || {};
          var form = document.createElement("form"); form.method = method; form.action = path;
          for (var key in params) { var input = document.createElement("input");
            input.type = "hidden"; input.name = key; input.value = params[key]; form.appendChild(input); }
          document.body.appendChild(form); form.submit(); document.body.removeChild(form);
        };
        Shopify.bind = function(fn, scope) { return function() { return fn.apply(scope, arguments); }; };
        Shopify.addListener = function(target, eventName, callback) {
          target.addEventListener ? target.addEventListener(eventName, callback, false)
                                  : target.attachEvent("on" + eventName, callback);
        };
        Shopify.setSelectorByValue = function(selector, value) {
          for (var i = 0, count = selector.options.length; i < count; i++) {
            if (value === selector.options[i].value || value === selector.options[i].innerHTML) {
              selector.selectedIndex = i; return i; } }
        };
        Shopify.getCart = function(callback) {
          fetch(Shopify.routes.root + "cart.js").then(function(r) { return r.json(); })
            .then(function(cart) { if (callback) callback(cart); });
        };
        Shopify.onCartUpdate = function(cart) {};
        Shopify.removeItem = function(variantId, callback) {
          fetch(Shopify.routes.root + "cart/change.js", { method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ id: variantId, quantity: 0 }) })
            .then(function(r) { return r.json(); })
            .then(function(cart) { (callback || Shopify.onCartUpdate)(cart); });
        };
        Shopify.loadFeatures = function(features, callback) { if (callback) callback(null); };
        Shopify.PaymentButton = { init: function() {} };
        Shopify.ModelViewerUI = function() {};
        Shopify.CountryProvinceSelector = function(countryDomId, provinceDomId, options) {
          this.countryEl = document.getElementById(countryDomId);
          this.provinceEl = document.getElementById(provinceDomId);
          this.provinceContainer = document.getElementById(options ? options.hideElement : provinceDomId);
          if (!this.countryEl) return;
          Shopify.addListener(this.countryEl, "change", Shopify.bind(this.countryHandler, this));
          this.initCountry();
        };
        Shopify.CountryProvinceSelector.prototype = {
          initCountry: function() {
            var value = this.countryEl.getAttribute("data-default");
            if (value) Shopify.setSelectorByValue(this.countryEl, value);
            this.countryHandler();
          },
          countryHandler: function() {
            var opt = this.countryEl.options[this.countryEl.selectedIndex];
            if (!opt) return;
            var raw = opt.getAttribute("data-provinces");
            var provinces = raw ? JSON.parse(raw) : [];
            if (this.provinceEl) {
              this.provinceEl.innerHTML = "";
              for (var i = 0; i < provinces.length; i++) {
                var option = document.createElement("option");
                option.value = provinces[i][0]; option.innerHTML = provinces[i][1];
                this.provinceEl.appendChild(option);
              }
            }
            if (this.provinceContainer) {
              this.provinceContainer.style.display = provinces.length ? "" : "none";
            }
          }
        };
        </script>
      HTML
    end
    # rubocop:enable Metrics/MethodLength
  end
end
