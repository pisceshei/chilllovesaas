# frozen_string_literal: true

module ThemeEngine
  # `placeholder_svg_tag` 的插圖庫（D79 預覽對位；官方名稱表＝
  # https://shopify.dev/docs/api/liquid/filters/placeholder_svg_tag，取證 2026-09-03：
  # outline＝product-1..6／collection-1..6／lifestyle-1..2／image；
  # color＝product-apparel-1..4／collection-apparel-1..4／hero-apparel-1..3／blog-apparel-1..3／detailed-apparel-1）。
  #
  # ①這是什麼：主題在 image_picker 空值時呼叫 `'hero-apparel-2' | placeholder_svg_tag` 取得一張佔位插圖，
  #   本尊會輸出整張 SVG 插圖（hoko.vip 實測形：`<svg class="placeholder-svg"
  #   preserveAspectRatio="xMidYMin slice" viewBox="0 0 1300 731" fill="none">…`）。舊實作只回一塊色塊，
  #   slideshow／collection card 因此變成一格空底（使用者 2026-09-03 對照截圖點名）。
  # ②形態：class 未給時＝`placeholder-svg`（hoko.vip 實測：background-image snippet 不帶 class 也得到
  #   `class="placeholder-svg"`）；給了就逐字用（不再附加）。方形名稱 viewBox `0 0 525.5 525.5`
  #   （官方文檔範例值）、寬幅名稱 `0 0 1300 731`（hoko.vip 實測）；`preserveAspectRatio` 一律
  #   `xMidYMid slice`（本尊逐名各異：xMidYMin／xMaxYMid——逐名值未取得，取置中裁切）。
  # ③🔴 插圖是**我方自繪**（鐵律 9：不抄本尊圖片資產）；構圖與配色向本尊靠攏（沙色底、藍色上衣、
  #   綠色丘陵、白色太陽；outline 系＝淺灰線稿），但每一條路徑都是這裡的程式生成。
  # ④跨功能影響：`Filters#placeholder_svg_tag`／`payment_type_svg_tag`（後者仍走舊色塊）；storefront 與
  #   編輯器預覽共用；未知名稱回 `image` 的線稿（本尊行為未取得，fail-open 顯示通用圖）。
  module PlaceholderSvg
    SQUARE = "0 0 525.5 525.5"
    WIDE   = "0 0 1300 731"

    SAND   = "#F2E6CF"
    SAND_2 = "#E9D8BA"
    BLUE   = "#3E8BD0"
    BLUE_2 = "#2F6FB0"
    GREEN  = "#78B36B"
    GREEN_2 = "#5C9A54"
    WHITE  = "#FFFFFF"
    GREY_BG = "#F5F5F5"
    GREY_LINE = "#C9C9C9"

    module_function

    # @return [String] 完整 `<svg …>…</svg>`
    def tag(name, css_class = nil)
      key = name.to_s
      body, view_box = illustration(key)
      cls = css_class.to_s.strip.empty? ? "placeholder-svg" : css_class.to_s
      %(<svg class="#{CGI.escapeHTML(cls)}" preserveAspectRatio="xMidYMid slice" viewBox="#{view_box}" ) \
        "fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\">#{body}</svg>"
    end

    def illustration(key)
      case key
      when /\Ahero-apparel-(\d)\z/ then [ hero_apparel(Regexp.last_match(1).to_i), WIDE ]
      when /\Ablog-apparel-(\d)\z/ then [ blog_apparel(Regexp.last_match(1).to_i), WIDE ]
      when /\Aproduct-apparel-(\d)\z/ then [ product_apparel(Regexp.last_match(1).to_i), SQUARE ]
      when /\Acollection-apparel-(\d)\z/ then [ collection_apparel(Regexp.last_match(1).to_i), SQUARE ]
      when "detailed-apparel-1" then [ product_apparel(5), SQUARE ]
      when /\Alifestyle-(\d)\z/ then [ lifestyle(Regexp.last_match(1).to_i), WIDE ]
      when /\Aproduct-(\d)\z/ then [ product_outline(Regexp.last_match(1).to_i), SQUARE ]
      when /\Acollection-(\d)\z/ then [ collection_outline(Regexp.last_match(1).to_i), SQUARE ]
      else [ image_outline, SQUARE ]
      end
    end

    # ── 彩色系（apparel）────────────────────────────────────────────────────
    def hero_apparel(variant)
      cx = { 1 => 420, 2 => 650, 3 => 880 }.fetch(variant, 650)
      <<~SVG.gsub(/\s+/, " ").strip
        <rect width="1300" height="731" fill="#{SAND}"/>
        <circle cx="#{cx - 380}" cy="240" r="95" fill="#{WHITE}"/>
        <path d="M0 731V560C140 500 260 470 420 520S700 600 900 540 1170 470 1300 520V731Z" fill="#{GREEN}"/>
        <path d="M0 731V640C170 600 320 610 470 650S760 690 950 630 1170 600 1300 640V731Z" fill="#{GREEN_2}"/>
        #{figure(cx, 120, 1.0)}
      SVG
    end

    def blog_apparel(variant)
      items = case variant
      when 1 then hanger_row(1300)
      when 2 then [ shoe(300, 380, 1.4), shoe(760, 380, 1.4) ].join
      else [ hat(330, 300, 1.3), hat(680, 300, 1.3), hat(1030, 300, 1.3) ].join
      end
      <<~SVG.gsub(/\s+/, " ").strip
        <rect width="1300" height="731" fill="#{SAND}"/>
        <rect y="560" width="1300" height="171" fill="#{SAND_2}"/>
        #{items}
      SVG
    end

    def product_apparel(variant)
      item = case variant
      when 1 then tee(262, 150, 1.0, BLUE)
      when 2 then jacket(262, 140, 1.0)
      when 3 then dress(262, 120, 1.0)
      when 4 then hoodie(262, 140, 1.0)
      else tee(262, 60, 1.5, BLUE_2)
      end
      %(<rect width="525.5" height="525.5" fill="#{SAND}"/>#{item})
    end

    def collection_apparel(variant)
      items = case variant
      when 1 then [ tee(170, 190, 0.6, BLUE), tee(355, 190, 0.6, BLUE_2) ].join
      when 2 then [ hoodie(170, 190, 0.6), dress(355, 170, 0.6) ].join
      when 3 then hanger_row(525.5, 0.5)
      else [ shoe(150, 300, 0.8), shoe(380, 300, 0.8) ].join
      end
      %(<rect width="525.5" height="525.5" fill="#{SAND}"/><rect y="400" width="525.5" height="125.5" fill="#{SAND_2}"/>#{items})
    end

    # 無臉人形（本尊佔位圖的共同慣例：不畫五官）：白 T ＋ 藍襯衫 ＋ 淺膚色頸部
    def figure(cx, top, scale)
      s = scale
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{s})">
          <rect x="-34" y="0" width="68" height="70" rx="30" fill="#F1C7A6"/>
          <path d="M-190 610V250C-190 150 -120 90 -40 70L0 110L40 70C120 90 190 150 190 250V610Z" fill="#{BLUE}"/>
          <path d="M-40 70L0 110L40 70L20 130L0 610L-20 130Z" fill="#{WHITE}"/>
          <path d="M-190 610V300C-250 330 -290 420 -300 520L-190 610Z" fill="#{BLUE_2}"/>
          <path d="M190 610V300C250 330 290 420 300 520L190 610Z" fill="#{BLUE_2}"/>
          <circle cx="0" cy="240" r="7" fill="#{WHITE}"/><circle cx="0" cy="360" r="7" fill="#{WHITE}"/>
        </g>
      SVG
    end

    def tee(cx, top, scale, color)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-70 0L-30 -20C-20 5 20 5 30 -20L70 0L110 60L70 90L60 70V230H-60V70L-70 90L-110 60Z" fill="#{color}"/>
          <path d="M-30 -20C-20 5 20 5 30 -20L22 20H-22Z" fill="#{WHITE}" opacity=".35"/>
        </g>
      SVG
    end

    def jacket(cx, top, scale)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-80 0L-30 -25L0 30L30 -25L80 0L120 70L80 100L70 80V250H-70V80L-80 100L-120 70Z" fill="#{BLUE_2}"/>
          <path d="M-30 -25L0 30L-12 250H-40Z" fill="#{WHITE}"/><path d="M30 -25L0 30L12 250H40Z" fill="#{WHITE}"/>
          <path d="M-8 30H8V250H-8Z" fill="#{SAND}"/>
        </g>
      SVG
    end

    def dress(cx, top, scale)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-45 0H45L60 60L35 80L60 290H-60L-35 80L-60 60Z" fill="#{GREEN}"/>
          <path d="M-45 0H45L35 80H-35Z" fill="#{GREEN_2}"/>
        </g>
      SVG
    end

    def hoodie(cx, top, scale)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-75 10L-30 -15C-40 -60 40 -60 30 -15L75 10L115 70L75 100L65 80V240H-65V80L-75 100L-115 70Z" fill="#{BLUE}"/>
          <path d="M-30 -15C-40 -60 40 -60 30 -15C20 10 -20 10 -30 -15Z" fill="#{BLUE_2}"/>
          <rect x="-40" y="150" width="80" height="55" rx="8" fill="#{BLUE_2}"/>
          <path d="M-8 20V90M8 20V90" stroke="#{WHITE}" stroke-width="6"/>
        </g>
      SVG
    end

    def shoe(cx, top, scale)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-120 60C-110 20 -60 -30 0 -30C40 -30 60 0 100 20C140 40 170 50 170 80V100H-120Z" fill="#{BLUE}"/>
          <path d="M-120 80H170V110H-120Z" fill="#{WHITE}"/>
          <path d="M-40 -20L-20 20M-10 -25L10 15M20 -22L40 10" stroke="#{WHITE}" stroke-width="6"/>
        </g>
      SVG
    end

    def hat(cx, top, scale)
      <<~SVG
        <g transform="translate(#{cx} #{top}) scale(#{scale})">
          <path d="M-80 60C-80 0 -40 -50 0 -50S80 0 80 60Z" fill="#{BLUE_2}"/>
          <path d="M-140 60H80C120 60 150 70 150 90H-140Z" fill="#{BLUE}"/>
          <circle cx="0" cy="-50" r="10" fill="#{WHITE}"/>
        </g>
      SVG
    end

    def hanger_row(width, scale = 1.0)
      count = width > 900 ? 4 : 2
      gap = width / (count + 1)
      (1..count).map do |i|
        color = i.odd? ? BLUE : GREEN
        <<~SVG
          <g transform="translate(#{gap * i} #{width > 900 ? 120 : 110}) scale(#{scale})">
            <path d="M0 -40C-20 -40 -20 -10 0 -10V0" stroke="#{GREY_LINE}" stroke-width="6" fill="none"/>
            <path d="M-120 60L0 0L120 60Z" fill="none" stroke="#{GREY_LINE}" stroke-width="6"/>
            #{tee(0, 40, 0.9, color)}
          </g>
        SVG
      end.join
    end

    # ── 線稿系（outline）──────────────────────────────────────────────────
    def image_outline
      <<~SVG.gsub(/\s+/, " ").strip
        <rect width="525.5" height="525.5" fill="#{GREY_BG}"/>
        <rect x="120" y="140" width="285" height="245" rx="12" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/>
        <circle cx="200" cy="215" r="26" fill="#{GREY_LINE}"/>
        <path d="M145 360L235 270L300 335L335 300L380 360Z" fill="#{GREY_LINE}"/>
      SVG
    end

    def lifestyle(variant)
      sun = variant == 1 ? 330 : 900
      <<~SVG.gsub(/\s+/, " ").strip
        <rect width="1300" height="731" fill="#{GREY_BG}"/>
        <circle cx="#{sun}" cy="230" r="90" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/>
        <path d="M0 731V520L260 300L520 520L700 380L900 540L1100 400L1300 520V731Z" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/>
        <path d="M0 731V620C220 560 420 600 650 640S1050 620 1300 600V731Z" fill="#{GREY_LINE}" opacity=".5"/>
      SVG
    end

    def product_outline(variant)
      inner = case variant
      when 1 then tee(262, 150, 1.0, WHITE).gsub("fill=\"#{WHITE}\"", "fill=\"#{WHITE}\" stroke=\"#{GREY_LINE}\" stroke-width=\"10\"")
      when 2 then %(<rect x="170" y="150" width="185" height="230" rx="18" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/><path d="M355 200H395C420 200 420 300 395 300H355" fill="none" stroke="#{GREY_LINE}" stroke-width="10"/>)
      when 3 then %(<path d="M232 120H293V170C330 190 340 230 340 280V400C340 430 320 440 262 440S185 430 185 400V280C185 230 195 190 232 170Z" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/>)
      when 4 then %(<path d="M150 200H375L400 400H125Z" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/><path d="M205 200C205 120 320 120 320 200" fill="none" stroke="#{GREY_LINE}" stroke-width="10"/>)
      when 5 then shoe(262, 260, 1.0).gsub(BLUE, WHITE).gsub("fill=\"#{WHITE}\"", "fill=\"#{WHITE}\" stroke=\"#{GREY_LINE}\" stroke-width=\"8\"")
      else %(<rect x="140" y="180" width="245" height="200" rx="14" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/><path d="M140 240H385M262 180V380" stroke="#{GREY_LINE}" stroke-width="10"/>)
      end
      %(<rect width="525.5" height="525.5" fill="#{GREY_BG}"/>#{inner})
    end

    def collection_outline(variant)
      cells = case variant
      when 1 then [ [ 130, 130 ], [ 275, 130 ], [ 130, 275 ], [ 275, 275 ] ]
      when 2 then [ [ 130, 130 ], [ 275, 130 ], [ 200, 275 ] ]
      when 3 then [ [ 200, 130 ], [ 130, 275 ], [ 275, 275 ] ]
      when 4 then [ [ 110, 200 ], [ 205, 200 ], [ 300, 200 ] ]
      when 5 then [ [ 200, 110 ], [ 200, 205 ], [ 200, 300 ] ]
      else [ [ 165, 165 ], [ 240, 240 ] ]
      end
      boxes = cells.map { |x, y| %(<rect x="#{x}" y="#{y}" width="120" height="120" rx="12" fill="#{WHITE}" stroke="#{GREY_LINE}" stroke-width="10"/>) }.join
      %(<rect width="525.5" height="525.5" fill="#{GREY_BG}"/>#{boxes})
    end
  end
end
