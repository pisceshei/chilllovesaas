# frozen_string_literal: true

module ThemeEngine
  # Theme 記錄 → 唯讀檔案來源的解析（D77 架構：主題是資料，Liquid 檔案外源）。
  #
  # 解析順序：
  #   1. `Rails.root/themes/<key>`——倉內第一方主題（包 33 的「自寫最小預設主題」落點）。
  #   2. `test/fixtures/themes/<key>`——🔴 **僅 development／test**：Ella 是使用者已購
  #      授權的測試 fixture（鐵律 9：不隨平台散布 ⇒ production 一律不解析 fixture 路徑）。
  # key＝`<name.parameterize>-<version>`（如 ella-7.2.0）；version 空 ⇒ 只用 name。
  module Sources
    module_function

    # 🔴 AST cache 的鍵同源自此（runtime AST_CACHE 鍵＝[key_for, rel]）：匯入主題
    # 一律回 content_checksum（內容定址 ⇒ 同鍵恆同內容——跨租戶 AST 汙染根治，
    # 99 §5；storage 目錄不可變）。first_party/fixture 維持名稱鍵（共用唯讀目錄）。
    def key_for(theme)
      return "sha256-#{theme.content_checksum}" if theme.content_checksum.present?

      [ theme.name.to_s.parameterize, theme.version.to_s.presence ].compact.join("-")
    end

    # @return [FileSource, OverlaySource, nil] 解析不到 ⇒ nil（呼叫端 fail-closed）。
    # 16e1：該主題存在檔案覆寫列 ⇒ 包 OverlaySource（overlay 優先、缺列回落）；
    # AST cache 鍵的租戶安全見 OverlaySource 檔頭與 Runtime#compiled。
    def resolve(theme)
      base = base_resolve(theme)
      return nil if base.nil?

      # 🔴 without_tenant＋顯式 shop_id（鐵律 2 條款②）：resolve 可能在租戶
      # context 外被叫（引擎層、資產端點）；查詢仍逐條帶 shop_id。
      overlaid = ActsAsTenant.without_tenant do
        ThemeFileOverlay.where(shop_id: theme.shop_id, theme_id: theme.id).exists?
      end
      overlaid ? OverlaySource.new(base, shop_id: theme.shop_id, theme_id: theme.id) : base
    end

    def base_resolve(theme)
      if theme.content_checksum.present?
        imported = Rails.root.join("storage", "themes", theme.content_checksum)
        return File.directory?(imported) ? FileSource.new(imported) : nil
      end

      key = key_for(theme)
      first_party = Rails.root.join("themes", key)
      return FileSource.new(first_party) if File.directory?(first_party)

      unless Rails.env.production?
        fixture = Rails.root.join("test", "fixtures", "themes", key)
        return FileSource.new(fixture) if File.directory?(fixture)
      end
      nil
    end
  end
end
