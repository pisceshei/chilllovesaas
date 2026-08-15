class Bad < ActiveRecord::Migration[8.1]
  def change
    create_table :things do |t|
      t.decimal :price, precision: 10, scale: 2
    end
  end
end
