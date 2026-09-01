# frozen_string_literal: true

module ThemeEngine
  # 檔案覆寫層來源（步 16e1）：overlay 列優先，缺列回落 base（FileSource）。
  #
  # 🔴 AST cache 租戶安全（15a 跨租戶汙染同軸）：base 的 cache 鍵是**共用**的
  # （first_party 名稱鍵／匯入內容定址鍵），被覆寫的檔若沿用共用鍵，A 店的
  # 編輯會汙染 B 店的編譯結果 ⇒ Runtime#compiled 對 overlay 檔改用
  # per-row 版本鍵（overlay_stamp）；未覆寫檔維持共用鍵（保快取效益）。
  class OverlaySource
    def initialize(base, shop_id:, theme_id:)
      @base = base
      @shop_id = shop_id
      @theme_id = theme_id
    end

    def read(rel)
      key = rel.to_s
      return fetch_content(key) if stamps.key?(key)

      @base.read(rel)
    end

    def exist?(rel)
      stamps.key?(rel.to_s) || @base.exist?(rel)
    end

    def list
      (@base.list | stamps.keys).sort
    end

    def size_of(rel)
      key = rel.to_s
      return fetch_content(key)&.bytesize if stamps.key?(key)

      @base.size_of(rel)
    end

    # @return [String, nil] overlay 檔的版本戳（AST cache 鍵維度）；未覆寫 ⇒ nil
    def overlay_stamp(rel)
      row = stamps[rel.to_s]
      row && "#{row[0]}-#{row[1].to_f}"
    end

    private

    # path → [lock_version, updated_at]（一次 pluck；單請求生命週期記憶）。
    # without_tenant＋顯式 shop_id 同 Sources.resolve（鐵律 2 條款②）。
    def stamps
      @stamps ||= ActsAsTenant.without_tenant do
        ThemeFileOverlay.where(shop_id: @shop_id, theme_id: @theme_id)
                        .pluck(:path, :lock_version, :updated_at)
                        .to_h { |path, lock, at| [ path, [ lock, at ] ] }
      end
    end

    def fetch_content(path)
      @contents ||= {}
      return @contents[path] if @contents.key?(path)

      @contents[path] = ActsAsTenant.without_tenant do
        ThemeFileOverlay.where(shop_id: @shop_id, theme_id: @theme_id).find_by(path:)&.content
      end
    end
  end
end
