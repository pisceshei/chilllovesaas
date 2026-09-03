# frozen_string_literal: true

module RenderParity
  # 逐段 diff 報告（渲染 1:1 對表）。輸入兩份**已正規化**的 HTML（本尊＝reference、我方＝candidate），輸出：
  #   ①section 集合差（只在一邊出現的 key）②每段相似度與前 N 個差異片段③head 資產（stylesheet／script src）集合差
  #   ④inline script 開頭指紋集合差。報告是 Markdown，供 worklog／91 登記與逐缺口修復；不做任何「自動判為可接受」。
  class Report
    Fragment = Struct.new(:kind, :reference, :candidate)
    SectionResult = Struct.new(:key, :similarity, :reference_length, :candidate_length, :fragments)

    def initialize(reference:, candidate:, normalizer:, max_fragments: 6)
      @reference = normalizer.call(reference)
      @candidate = normalizer.call(candidate)
      @normalizer = normalizer
      @max_fragments = max_fragments
    end

    def sections
      ref = @normalizer.sections(@reference)
      cand = @normalizer.sections(@candidate)
      keys = ref.keys | cand.keys
      keys.map do |key|
        a, b = ref[key].to_s, cand[key].to_s
        SectionResult.new(key, similarity(a, b), a.length, b.length, a.empty? || b.empty? ? [] : fragments(a, b))
      end
    end

    def head_assets
      {
        stylesheets: set_diff(links(@reference), links(@candidate)),
        scripts: set_diff(script_srcs(@reference), script_srcs(@candidate)),
        inline_scripts: set_diff(inline_fingerprints(@reference), inline_fingerprints(@candidate))
      }
    end

    def to_markdown(title: "render parity")
      lines = [ "# #{title}", "" ]
      lines << "## Sections"
      lines << "| key | similarity | ref len | cand len |"
      lines << "|---|---|---|---|"
      sections.sort_by { |s| s.similarity }.each do |s|
        lines << "| #{s.key} | #{format('%.3f', s.similarity)} | #{s.reference_length} | #{s.candidate_length} |"
      end
      lines << ""
      sections.reject { |s| s.similarity >= 0.999 && s.reference_length == s.candidate_length }.each do |s|
        lines << "### #{s.key} (#{format('%.3f', s.similarity)})"
        s.fragments.each do |f|
          lines << "- #{f.kind}: ref `#{escape(f.reference)}` / cand `#{escape(f.candidate)}`"
        end
        lines << ""
      end
      head = head_assets
      lines << "## Head assets"
      head.each do |name, (only_ref, only_cand)|
        lines << "- #{name}: only reference #{only_ref.inspect}; only candidate #{only_cand.inspect}"
      end
      lines.join("\n") + "\n"
    end

    private

    def similarity(a, b)
      return 0.0 if a.empty? || b.empty?

      # token（標籤／文字詞）多重集合的 Jaccard：與位置無關，單一插入不會把後面全部判成不同
      chunks = ->(s) { s.scan(/<[^>]+>|[^<\s]+/).tally }
      ca, cb = chunks.call(a), chunks.call(b)
      inter = ca.sum { |k, v| [ v, cb[k] || 0 ].min }
      union = (ca.keys | cb.keys).sum { |k| [ ca[k] || 0, cb[k] || 0 ].max }
      union.zero? ? 1.0 : inter.to_f / union
    end

    # 首個差異點附近的片段（左 40／右 80 字），最多 max_fragments 個（逐個「跳過共同前綴」找）
    def fragments(a, b)
      out = []
      ia = ib = 0
      while out.size < @max_fragments && ia < a.length && ib < b.length
        while ia < a.length && ib < b.length && a[ia] == b[ib]
          ia += 1
          ib += 1
        end
        break if ia >= a.length || ib >= b.length

        out << Fragment.new("differ", a[[ ia - 40, 0 ].max, 120], b[[ ib - 40, 0 ].max, 120])
        # 重新同步：往前找下一個共同的 `<` 標籤起點
        na = a.index("<", ia + 1) || a.length
        nb = b.index("<", ib + 1) || b.length
        ia, ib = na, nb
      end
      # 一邊是另一邊的前綴（差異只在尾端）⇒ 補一個 tail 片段，否則報告會顯示「相似度 <1 卻無片段」
      out << Fragment.new("tail", a[-120..] || a, b[-120..] || b) if out.empty? && a != b
      out
    end

    def links(html) = html.scan(/<link[^>]*rel="stylesheet"[^>]*href="([^"]+)"/).flatten | html.scan(/<link[^>]*href="([^"]+)"[^>]*rel="stylesheet"/).flatten
    def script_srcs(html) = html.scan(/<script[^>]*\ssrc="([^"]+)"/).flatten.uniq
    def inline_fingerprints(html) = html.scan(/<script(?![^>]*\ssrc=)[^>]*>(.{0,40})/).flatten.map { |x| x.strip }.uniq
    def set_diff(a, b) = [ a - b, b - a ]
    def escape(text) = text.to_s.gsub("`", "'").gsub("|", "\\|")
  end
end
