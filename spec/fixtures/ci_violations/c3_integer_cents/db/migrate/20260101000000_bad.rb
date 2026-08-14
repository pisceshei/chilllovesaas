class Bad < ActiveRecord::Migration[8.1]
  def change
    create_table :things do |t|
      t.integer :price_cents, null: false
    end
  end
end
