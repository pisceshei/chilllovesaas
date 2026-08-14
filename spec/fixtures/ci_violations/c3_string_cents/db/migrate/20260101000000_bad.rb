class Bad < ActiveRecord::Migration[8.1]
  def change
    create_table :things do |t|
      # 🔴 `t.string` 建金額欄位。本輪之前 C3 只擋 `t.decimal`／`t.float`／`t.integer`
      #    ⇒ 這一列**完全通過**，而成功訊息還宣告「`_cents` 皆為 bigint」。
      #    改成白名單式（型別不是 bigint 就違規）之後才擋得住。
      t.string :price_cents, null: false
    end
  end
end
