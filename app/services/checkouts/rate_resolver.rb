# frozen_string_literal: true

module Checkouts
  # 運送費率解析（15 §F2.1／F2.2；實測正典 85 §5.2–§5.3）。
  #
  # ①這是什麼：destination 國家＋結帳行 → per-participant 運送選項。
  #   participant＝(shipping_profile, location_group)（limits
  #   shipping.rate_merge_participant_unit）；🔴 v1 單地點 ⇒ 分組鍵退化為 profile
  #   （location_groups 表未建，隨多地點包升級——本檔只需改 group_key）。
  # ②兩種輸出形（85 §5.3 實測）：
  #   - shipments：split shipping（預設 On）＝每個 participant 一個 shipment、
  #     選項獨立選（「More shipping options」modal 的形）；聚合預設＝各取最便宜
  #     （「Lowest price」卡）。
  #   - merged_options：split Off／46c 合併規則（官方 combined-rates 頁 2026-08-31
  #     現值，85 §6）：同名相加；無共同名 ⇒ 各取最便宜相加、掛 fallback 名。
  #     合併鍵＝NFC＋trim、大小寫敏感（limits rate_merge_key_normalization，V-15）。
  # ③🔴 條件基數＝participant 自己那批行的小計／總重（spec 15 F2.1(b) 規範層裁定；
  #   官方句「apply to the total price of the cart」與之相衝、實測未判別——85 §5.3 V。
  #   重量制每個 participant 各加一次店預設包裹重量——46c「可能更貴」的成因）。
  # ④🔴 Rates(p)=∅ ⇒ **整車擋**（:undeliverable，不是靜默跳過該組——85 §4 零費率
  #   zone 警示的執行面）；國家不在 active market ⇒ :not_sellable（F2.2 雙向 guard
  #   的另一半；85 §6 官方交集句）。
  # ⑤幣別：v1 只考慮 currency＝結帳幣的費率（🔴 條件門檻以**費率自身幣別**比較
  #   ——85 §5.2 實錘；換匯未接前，異幣費率不產出選項而不是錯誤換算）。
  # ⑥金額全 integer cents（鐵律 3）；本服務唯讀，不寫任何表。
  module RateResolver
    Option = Data.define(:rate_id, :name, :price_cents, :min_transit_seconds, :max_transit_seconds)
    Shipment = Data.define(:shipping_profile_id, :profile_name, :line_keys, :options)
    Result = Data.define(:status, :shipments, :merged_options) do
      def ok? = status == :ok
    end

    module_function

    # @param shop [Shop]
    # @param country_code [String] 大寫 ISO alpha-2（destination）
    # @param lines [Array<Hash>] {key:, quantity:, unit_price_cents:, weight_grams:,
    #   requires_shipping:, shipping_profile_id:}——snapshot 行（CreateFromCart 快照欄）
    # @return [Result] status ∈ :ok／:not_sellable／:undeliverable
    def call(shop:, country_code:, lines:, currency: shop.store_currency)
      lines.each { |l| money!(l[:unit_price_cents]) && grams!(l[:weight_grams]) }

      return Result.new(status: :not_sellable, shipments: [], merged_options: []) unless
        sellable_country?(shop:, country_code:)

      shippable = lines.select { |l| l[:requires_shipping] }
      return Result.new(status: :ok, shipments: [], merged_options: []) if shippable.empty?

      shipments = build_shipments(shop:, country_code:, lines: shippable, currency:)
      return Result.new(status: :undeliverable, shipments: [], merged_options: []) if shipments.nil?

      Result.new(status: :ok, shipments:, merged_options: merge(shipments))
    end

    # 前台國家白名單（85 §6 官方逐字：「included in both an active market and a
    # shipping zone with available shipping rates」——兩集合交集，checkout 下拉的值域）。
    # @return [Array<String>] 大寫國碼，排序穩定
    def sellable_countries(shop:)
      market_countries = MarketRegion.where(shop_id: shop.id)
                                     .joins(:market).merge(Market.active)
                                     .distinct.pluck(:country_code)
      zone_countries = ShippingZone.where(shop_id: shop.id)
                                   .joins(:shipping_rates).merge(ShippingRate.active)
                                   .distinct.pluck(:country_codes).flatten.uniq
      (market_countries & zone_countries).sort
    end

    def sellable_country?(shop:, country_code:)
      MarketRegion.where(shop_id: shop.id, country_code:)
                  .joins(:market).merge(Market.active).exists?
    end

    # @return [Array<Shipment>, nil] nil＝某 participant Rates(p)=∅（整車擋，見④）
    def build_shipments(shop:, country_code:, lines:, currency:)
      general_id = ShippingProfile.where(shop_id: shop.id).general.pick(:id)
      package_grams = Limits.fetch(:shipping, :default_package_weight_grams)

      groups = lines.group_by { |l| l[:shipping_profile_id] || general_id }
      profiles = ShippingProfile.where(shop_id: shop.id, id: groups.keys)
                                .includes(shipping_zones: :shipping_rates).index_by(&:id)

      groups.sort_by { |profile_id, _| profile_id.to_i }.map do |profile_id, group|
        profile = profiles[profile_id]
        return nil if profile.nil? # 快照指向已刪 profile：FK 已把商品 nullify，快照過期 ⇒ 擋下重選

        subtotal = group.sum { |l| l[:unit_price_cents] * l[:quantity] }
        weight = group.sum { |l| l[:weight_grams] * l[:quantity] } + package_grams

        rates = profile.shipping_zones
                       .select { |z| z.covers?(country_code) }
                       .flat_map(&:shipping_rates)
                       .select do |r|
          r.active && r.currency == currency &&
            r.condition_holds?(order_subtotal_cents: subtotal, weight_grams: weight)
        end
        options = dedupe_cheapest_per_name(rates)
        return nil if options.empty?

        Shipment.new(shipping_profile_id: profile_id, profile_name: profile.name,
                     line_keys: group.map { |l| l[:key] }, options:)
      end
    end

    # participant 內同名取最便宜（order_amount 級距列共用名稱——85 §3 的資料形，
    # 一個名字對顧客只能是一個價），再按價升冪、同價按名穩定排序。
    def dedupe_cheapest_per_name(rates)
      rates.group_by { |r| normalize_name(r.name) }
           .map { |_, same| same.min_by { |r| [ r.price_cents, r.id ] } }
           .sort_by { |r| [ r.price_cents, normalize_name(r.name), r.id ] }
           .map do |r|
        Option.new(rate_id: r.id, name: r.name.unicode_normalize(:nfc).strip,
                   price_cents: r.price_cents,
                   min_transit_seconds: r.min_transit_seconds, max_transit_seconds: r.max_transit_seconds)
      end
    end

    # 46c 合併（split Off 的單列形；85 §6 官方現值＋limits shipping.rate_merge_*）。
    # 單 participant ⇒ 原樣（不進合併分支——合併是跨檔才有的事）。
    def merge(shipments)
      return shipments.first.options if shipments.size == 1

      per_name = shipments.map { |s| s.options.index_by { |o| normalize_name(o.name) } }
      common = per_name.map { |h| h.keys.to_set }.reduce(:&)

      if common.any?
        common.sort.map do |name_key|
          picks = per_name.map { |h| h.fetch(name_key) }
          Option.new(rate_id: nil, name: picks.first.name,
                     price_cents: picks.sum(&:price_cents),
                     min_transit_seconds: transit_bound(picks, :min_transit_seconds, :max),
                     max_transit_seconds: transit_bound(picks, :max_transit_seconds, :max))
        end.sort_by { |o| [ o.price_cents, o.name ] }
      else
        cheapest = shipments.map { |s| s.options.first } # options 已按價升冪
        [ Option.new(rate_id: nil, name: Limits.fetch(:shipping, :merged_option_fallback_label),
                    price_cents: cheapest.sum(&:price_cents),
                    min_transit_seconds: transit_bound(cheapest, :min_transit_seconds, :max),
                    max_transit_seconds: transit_bound(cheapest, :max_transit_seconds, :max)) ]
      end
    end

    # 合併選項的 transit＝各參與者的**最慢**（整單一起到才算到；任一參與者 None ⇒ None）。
    # ⚠ 本尊合併形的 transit 呈現未實測（split Off 未觀測到——85 §5.3 V）⇒ ours 決策。
    def transit_bound(options, field, _agg)
      values = options.map { |o| o.public_send(field) }
      return nil if values.any?(&:nil?)

      values.max
    end

    def normalize_name(name)
      # limits shipping.rate_merge_key_normalization: nfc_trim_case_sensitive（V-15）
      name.unicode_normalize(:nfc).strip
    end

    def money!(value)
      raise TypeError, "金額必須是 integer cents，收到 #{value.class}" unless value.is_a?(Integer)

      true
    end

    def grams!(value)
      raise TypeError, "重量必須是 integer grams，收到 #{value.class}" unless value.is_a?(Integer)

      true
    end
  end
end
