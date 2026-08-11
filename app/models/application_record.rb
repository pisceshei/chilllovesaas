# 所有 CHILL LOVE 持久化 record 的抽象基底。
#
# 集中承接 Active Record 行為；實體 model 必須自行宣告 tenant boundary。
# 見 AGENTS.md 技術鐵律 2、docs/specs/12 F4。
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
end
