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
    # 頭段逐字對齊本尊（hoko.vip 2026-09-03 原始位元組）：
    #   `var Shopify = Shopify || {};` → shop（本尊＝myshopify 永久網域；我方＝平台子網域）→ locale → currency（JSON 形）
    #   → country → theme（name／id／schema_name／schema_version／theme_store_id／role）→ theme.handle="null"
    #   → theme.style={"id":null,"handle":null} → cdnHost → routes.root。designMode 於編輯器預覽的位置＝未取得（置於其後）。
    #   其後的 formatMoney／postLink 等是本尊另行載入的 shopify_common 面（ours，Ella 用法收斂）。
    # @param country [String, nil] localization 國別（本尊 `Shopify.country = "TW"`）
    # @param schema_name／schema_version [String, nil] settings_schema theme_info
    # @param host [String, nil] 本店主機（cdnHost 形 `{host}/theme-assets`；本尊 `hoko.vip/cdn`，路徑為 ours）
    def script(shop:, theme:, locale:, currency:, root:, design_mode:, country: nil, schema_name: nil,
               schema_version: nil, host: nil)
      theme_json = JSON.generate(name: theme.name.to_s, id: theme.id, schema_name: schema_name,
                                 schema_version: schema_version, theme_store_id: nil,
                                 role: theme.role.to_s == "published" ? "main" : "unpublished")
      <<~HTML
        <script>var Shopify = Shopify || {};
        Shopify.shop = #{"#{shop.subdomain}.#{Chilllove::TenantResolver.base_host}".inspect};
        Shopify.locale = #{locale.to_s.inspect};
        Shopify.currency = #{JSON.generate(active: currency.to_s, rate: "1.0")};
        Shopify.country = #{country.to_s.inspect};
        Shopify.theme = #{theme_json};
        Shopify.theme.handle = "null";
        Shopify.theme.style = {"id":null,"handle":null};
        Shopify.cdnHost = #{"#{host}/theme-assets".inspect};
        Shopify.routes = Shopify.routes || {};
        Shopify.routes.root = #{root.to_s.inspect};
        #{design_mode ? "Shopify.designMode = true;" : "/* Shopify.designMode: undefined outside the editor (official) */"}
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
