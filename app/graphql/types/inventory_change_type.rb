# frozen_string_literal: true

module Types
  # changes 投影的單筆（＝本尊 InventoryChange 的子集）。
  class InventoryChangeType < BaseObject
    graphql_name "InventoryChange"
    description "單一數量名的變動。"

    field :name, String, null: false
    field :delta, Integer, null: false
    field :ledger_document_uri, String, null: true

    def name = object.fetch(:name)
    def delta = object.fetch(:delta)
    def ledger_document_uri = object.fetch(:row).ledger_document_uri
  end
end
