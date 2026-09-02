# 探針：三套主題全部 sections/blocks 的 {% schema %} 用引擎自己的 tolerant_json 解析，統計失敗
re = ThemeEngine::Runtime::SCHEMA_RE
%w[ella-7.2.0 minimog-6.0.0 kalles-5.4.2].each do |th|
  fails = []; total = 0
  %w[sections blocks].each do |sub|
    Dir.glob(Rails.root.join("test/fixtures/themes/#{th}/#{sub}/*.liquid")).each do |f|
      src = File.read(f); j = src[re, 1] or next
      total += 1
      begin
        ThemeEngine::Runtime.tolerant_json(j)
      rescue StandardError => e
        fails << [ "#{sub}/#{File.basename(f)}", e.message[0, 90] ]
      end
    end
  end
  puts "#{th}: schemas=#{total} tolerant_json fails=#{fails.size}"
  fails.first(6).each { |f| puts "   #{f.join(' | ')}" }
end
