# frozen_string_literal: true

require "rails_helper"

# 靜態掃描：每支具體 mutation 的 `resolve` 都必須呼叫 `enforce_idempotency_contract!`。
#
# 為什麼是掃原始碼而不是 runtime hook：graphql-ruby 的 `GraphQL::Schema::Mutation`
# **沒有 around hook**，「在 resolve 開頭主動呼叫」是唯一的接線方式，而忘了呼叫
# 沒有任何 runtime 機制會發現（base_mutation.rb 檔頭明文）。這條斷言是
# 2026-08-15 mutation 地基 worklog 承諾「第一支真 mutation 落地時要補的 CI 斷言」。
#
# 判準刻意是「resolve 方法體內出現該呼叫」而不只是「檔案裡出現字串」——
# 寫在註釋裡不算（謂詞不得被便宜的實作偷換）。
RSpec.describe "Mutation idempotency contract call" do
  # 遞迴 glob：日後 namespaced mutation（子目錄）不得靜默逃出掃描（對抗審查 confirmed #15）。
  MUTATION_SOURCE_GLOB = Rails.root.join("app/graphql/mutations/**/*.rb")

  it "每支具體 mutation 的 resolve 都呼叫 enforce_idempotency_contract!" do
    offenders = Dir.glob(MUTATION_SOURCE_GLOB).filter_map do |path|
      next if File.basename(path) == "base_mutation.rb"

      source = File.read(path)
      resolve_body = source[/^\s*def resolve\b.*?^\s*end$/m]
      next "#{File.basename(path)}：找不到 resolve 方法" if resolve_body.nil?

      unless resolve_body.match?(/^\s*enforce_idempotency_contract!/)
        "#{File.basename(path)}：resolve 內未呼叫 enforce_idempotency_contract!"
      end
    end

    expect(offenders).to be_empty, offenders.join("\n")
  end

  it "掃描的母體非空（app/graphql/mutations 下至少有一支具體 mutation）" do
    concrete = Dir.glob(MUTATION_SOURCE_GLOB).reject { |p| File.basename(p) == "base_mutation.rb" }
    expect(concrete).not_to be_empty
  end
end
