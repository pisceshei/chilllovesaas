# frozen_string_literal: true

module Storefront
  # `{% javascript %}` 編譯資產（E19；本尊 `compiled_assets/scripts.js`／`snippet-scripts.js`，external-facts §G27）。
  #
  # 官方（best-practices/javascript-and-stylesheet-tags，取證 2026-09-05）："Shopify concatenates the content from {% javascript %} tags
  # across all section, block and snippet files into one file per file type. These files are then injected into the theme through the
  # content_for_header Liquid object and asynchronously loaded through a <script> tag with the defer attribute."、
  # "wrapped in a self-executing anonymous function"、"Bundled assets are only injected once for each section, block or snippet file".
  # 本尊實檔（hoko `scripts.js`）：
  #   `(function(){var __sections__={};(function(){for(var i=0,s=document.getElementById("sections-script").getAttribute("data-sections").split(",");i<s.length;i++)__sections__[s[i]]=!0})(),`
  #   `(function(){if(!(!__sections__["section-product-tabs"]&&!Shopify.designMode))try{ …JS… }catch(e){console.error(e)}})()})();`
  #   ——每個 section 一個以 `data-sections` 門控的函式（設計模式全開），theme block 的 JS **併入所屬 section 的函式**（無 `__blocks__`）；
  #   `snippet-scripts.js` 同形（`__snippets__`、`snippets-script`、`data-snippets`，元素缺時 attribute 為空字串）。本尊輸出經壓縮；我方原文（V）。
  # block 歸屬：section schema `blocks` 列出的 block 型別（`@theme` ⇒ 全部公開 theme block）遞迴含其 schema 的 blocks（91 V：本尊歸屬規則未公開）。
  module CompiledAssets
    JS_RE = /\{%-?\s*javascript\s*-?%\}(.*?)\{%-?\s*endjavascript\s*-?%\}/m
    SCHEMA_RE = /\{%-?\s*schema\s*-?%\}(.*?)\{%-?\s*endschema\s*-?%\}/m

    module_function

    # @param source [#list, #read] 主題來源
    # @return [String] scripts.js 本體
    def scripts(source)
      sections = files(source, "sections")
      blocks = files(source, "blocks")
      block_js = blocks.to_h { |name, src| [ name, js_of(src) ] }
      block_schema = blocks.to_h { |name, src| [ name, schema_of(src) ] }
      parts = sections.filter_map do |name, src|
        own = js_of(src)
        nested = nested_block_js(schema_of(src), block_js, block_schema)
        next if own.nil? && nested.empty?

        gate("__sections__", name, [ own, *nested ].compact.join("\n"))
      end
      wrap("__sections__", %(document.getElementById("sections-script").getAttribute("data-sections").split(",")), parts, sections_form: true)
    end

    # @return [String] snippet-scripts.js 本體
    def snippet_scripts(source)
      parts = files(source, "snippets").filter_map do |name, src|
        js = js_of(src)
        js && gate("__snippets__", name, js)
      end
      wrap("__snippets__", nil, parts, sections_form: false)
    end

    def files(source, dir)
      source.list.grep(%r{\A#{dir}/[^/]+\.liquid\z}).sort.to_h do |rel|
        [ File.basename(rel, ".liquid"), source.read(rel).to_s ]
      end
    end

    def js_of(src)
      m = JS_RE.match(src)
      m && m[1].strip.presence
    end

    def schema_of(src)
      m = SCHEMA_RE.match(src)
      return {} unless m

      ThemeEngine::Runtime.tolerant_json(m[1]) || {}
    rescue StandardError
      {}
    end

    # section schema 接受的 block 型別（遞迴）之 JS
    def nested_block_js(schema, block_js, block_schema, seen = Set.new)
      types = Array(schema["blocks"]).filter_map { |b| b.is_a?(Hash) ? b["type"] : nil }
      names = types.flat_map { |t| t == "@theme" ? block_js.keys.reject { |k| k.start_with?("_") } : [ t ] }
      names.flat_map do |name|
        next [] if seen.include?(name) || !block_js.key?(name)

        seen << name
        [ block_js[name], *nested_block_js(block_schema[name] || {}, block_js, block_schema, seen) ].compact
      end
    end

    def gate(var, name, js)
      %[(function(){if(!(!#{var}[#{name.to_json}]&&!Shopify.designMode))try{\n#{js}\n}catch(e){console.error(e)}})()]
    end

    def wrap(var, _expr, parts, sections_form:)
      head =
        if sections_form
          %[(function(){var #{var}={};(function(){for(var i=0,s=document.getElementById("sections-script").getAttribute("data-sections").split(",");i<s.length;i++)#{var}[s[i]]=!0})()]
        else
          %[(function(){var #{var}={};(function(){for(var element=document.getElementById("snippets-script"),attribute=element?element.getAttribute("data-snippets"):"",snippets=attribute.split(",").filter(Boolean),i=0;i<snippets.length;i++)#{var}[snippets[i]]=!0})()]
        end
      [ head, *parts ].join(",") + "})();\n"
    end
  end
end
