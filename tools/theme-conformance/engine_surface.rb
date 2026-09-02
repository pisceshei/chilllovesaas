require "json"
Rails.application.eager_load!
env = ThemeEngine::Runtime::ENVIRONMENT
base = Liquid::Drop.public_instance_methods
drops = {}
ObjectSpace.each_object(Class).select { |k| k < Liquid::Drop && k.name.to_s.start_with?("ThemeEngine") }.sort_by(&:name).each do |k|
  drops[k.name.sub("ThemeEngine::", "")] = {
    methods: (k.public_instance_methods - base).map(&:to_s).sort,
    lmm: k.instance_method(:liquid_method_missing).owner != Liquid::Drop
  }
end
src = File.read(Rails.root.join("app/liquid/theme_engine/runtime.rb"))
globals = src.scan(/^        "([a-z_]+)" =>/).flatten.uniq
out = { tags: env.tags.keys.sort, std_filters: Liquid::StandardFilters.public_instance_methods(false).map(&:to_s).sort,
        engine_filters: ThemeEngine::Filters.public_instance_methods(false).map(&:to_s).sort, globals: globals, drops: drops }
File.write(ARGV[0], JSON.pretty_generate(out))
puts "tags=#{out[:tags].size} std_filters=#{out[:std_filters].size} engine_filters=#{out[:engine_filters].size} globals=#{globals.size} drops=#{drops.size}"
