# frozen_string_literal: true

# G6 步 11（買家帳戶線；74 §7 新版帳號形＝passwordless）：
# ①customer_sessions——365 天上限（74 §7）；token 只存 digest（sessions 表同紀律）。
# ②customer_otps——6 位驗證碼（74 §7 官方形）；code 只存 digest；attempts 防爆破。
class CreateCustomerSessionsAndOtps < ActiveRecord::Migration[8.1]
  def change
    unless table_exists?(:customer_sessions)
      create_table :customer_sessions, comment: "買家登入 session（365 天；token digest）" do |t|
        t.bigint :shop_id, null: false
        t.bigint :customer_id, null: false
        t.string :token_digest, limit: 64, null: false
        t.datetime :expires_at, null: false
        t.datetime :created_at, null: false

        t.index [ :token_digest ], unique: true, name: "uq_customer_sessions_token"
        t.index [ :shop_id, :customer_id ], name: "ix_customer_sessions_customer"
      end
    end
    if table_exists?(:customer_sessions) &&
       foreign_keys(:customer_sessions).none? { |fk| fk.to_table == "customers" }
      safety_assured { add_foreign_key :customer_sessions, :customers }
    end

    unless table_exists?(:customer_otps)
      create_table :customer_otps, comment: "登入驗證碼（74 §7 六位；digest＋attempts）" do |t|
        t.bigint :shop_id, null: false
        t.string :email, limit: 320, null: false, comment: "正規化後（normalize_email 同一定義點）"
        t.string :code_digest, limit: 64, null: false
        t.integer :attempts, null: false, default: 0
        t.datetime :expires_at, null: false
        t.datetime :consumed_at
        t.datetime :created_at, null: false

        t.index [ :shop_id, :email ], name: "ix_customer_otps_email"
      end
    end
  end
end
