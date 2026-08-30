# frozen_string_literal: true

module ThemeEngine
  # `| json` 濾鏡的 drop 感知序列化（資料出口包）。
  #
  # 真引擎契約（83 §12.2／§12.4 逐格實測，2026-08-30/31）：
  #   - `product | json` ≈ `/products/{h}.js`，但 **有 `content` 無 `url`**、
  #     variant 面 **無 `quantity_price_breaks`**、無 media 鍵。
  #   - `options_with_values | json`＝{name, position, values:[字串]}（值壓平）。
  #   - 🔴 json 黑名單：metafields root 與單一 metafield ⇒
  #     `{"error":"json not allowed for this object"}`；namespace ⇒ 扁平 {key: value}。
  #   - 其他 drop 的兜底＝to_s（gem 無 json 濾鏡，行為全由我方定義）。
  module JsonSerializer
    REFUSAL = { "error" => "json not allowed for this object" }.freeze

    module_function

    def dump(input)
      JSON.generate(coerce(input))
    rescue StandardError
      JSON.generate(REFUSAL)
    end

    def coerce(value)
      case value
      when nil, true, false, Numeric, String then value
      when Time, DateTime, ActiveSupport::TimeWithZone then value.iso8601
      when Date then value.iso8601
      when Hash then value.each_with_object({}) { |(k, v), h| h[k.to_s] = coerce(v) }
      when Array then value.map { |v| coerce(v) }
      else coerce_object(value)
      end
    end

    def coerce_object(value)
      return REFUSAL.dup if value.respond_to?(:json_refused?) && value.json_refused?
      return coerce(value.as_storefront_json) if value.respond_to?(:as_storefront_json)
      return value.to_s if value.is_a?(Liquid::Drop)

      value.respond_to?(:as_json) ? coerce(value.as_json) : value.to_s
    end
  end
end
