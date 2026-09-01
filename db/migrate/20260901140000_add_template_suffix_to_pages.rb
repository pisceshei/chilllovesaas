# frozen_string_literal: true

# 步 14a：pages 補 template_suffix（官方 Page.templateSuffix；?view= 替代模板——96 §6）。
class AddTemplateSuffixToPages < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:pages, :template_suffix)
      add_column :pages, :template_suffix, :string
    end
  end
end
