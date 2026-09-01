# frozen_string_literal: true

module ThemeEngine
  # 平台字型庫（步 13a；97 §1）：handle → FontDrop 的唯一解析點。
  #
  # ①registry＝`config/storefront_fonts.yml`（載入時凍結；跨租戶共用平台字典，
  #   與 platform_locales 同類——鐵律 2 的平台字典表判準，只是這份隨版本部署
  #   不落 DB）。
  # ②handle 解析（觀察形 `{family}_{n|i}{weight/100}`——97 §4-2 標 V）：
  #   已註冊家族查 variants；system 家族回 system drop；未知 handle 回
  #   fallback system drop＋miss 遙測（fail-quiet——主題不因字型缺席炸頁）。
  # ③font_modify 的變體查找走 `variant(family, style, weight)`——不存在回 nil
  #   （官方逐字："it returns `nil`"）。
  module FontLibrary
    module_function

    HANDLE_RE = /\A([a-z0-9_]+)_([ni])(\d)\z/

    def registry
      @registry ||= YAML.safe_load_file(
        Rails.root.join("config/storefront_fonts.yml")
      ).freeze
    end

    # @param handle [String] font_picker 儲存值（如 "jost_n4"）
    # @return [FontDrop] 永不 nil（未知 handle 走 system fallback）
    def drop(handle)
      h = handle.to_s
      if (m = h.match(HANDLE_RE))
        family_key, style_char, weight_digit = m[1], m[2], m[3].to_i
        family = registry["families"][family_key]
        if family
          style = style_char == "i" ? "italic" : "normal"
          weight = weight_digit * 100
          variant = find_variant(family, style, weight)
          return build(family_key, family, variant) if variant
        end
        return system_drop(family_key) # 家族已知但變體缺 ⇒ 同未知處置
      end
      system_drop(h)
    end

    # font_modify 的目標變體：同家族 × style × weight 精確查；缺 ⇒ nil。
    # @param base [FontDrop]
    def variant(base, style:, weight:)
      family = registry["families"][base.family_key]
      return nil if family.nil?

      found = find_variant(family, style, weight)
      found && build(base.family_key, family, found)
    end

    # 同家族全部變體 drop（font.variants——官方 array of font）。
    def variants_for(family_key)
      family = registry["families"][family_key]
      return [] if family.nil?

      family["variants"].map { |_h, v| build(family_key, family, v) }
    end

    def find_variant(family, style, weight)
      family["variants"].values.find { |v| v["style"] == style && v["weight"] == weight }
    end

    def build(family_key, family, variant)
      FontDrop.new(
        family_key:, family: family["display_name"],
        fallback_families: family["fallback"],
        weight: variant["weight"], style: variant["style"],
        file: variant["file"], system: false
      )
    end

    def system_drop(name)
      sys = registry["system"][name]
      ThemeEngine.count_miss("font_library.#{name}") if sys.nil?
      display = sys ? sys["display_name"] : name.split("_").first.to_s.capitalize
      fallback = sys ? sys["fallback"] : "sans-serif"
      FontDrop.new(family_key: name, family: display, fallback_families: fallback,
                   weight: 400, style: "normal", file: nil, system: true)
    end
  end
end
