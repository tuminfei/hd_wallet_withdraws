class CreateHdWalletWithdraws < ActiveRecord::Migration
  def self.up
    create_table :hd_wallet_withdraws do |t|
      t.string   "sn"
      t.integer  "member_id"
      t.string   "currency_code"
      t.decimal  "amount",         precision: 32, scale: 16
      t.decimal  "fee",            precision: 32, scale: 16
      t.string   "fund_uid"
      t.string   "fund_extra"
      t.datetime "done_at"
      t.string   "txid"
      t.string   "aasm_state"
      t.decimal  "sum",            precision: 32, scale: 16, default: 0.0, null: false
      t.string   "type"
      t.string   "agent_fee_type"
      t.decimal  "agent_fee",      precision: 32, scale: 16, default: 0.0, null: false
      t.string   "memo"
      t.string   "withdraw_state"
      t.timestamps
    end

    create_table :hd_wallet_balances, force: true do |t|
      t.integer  "member_id"
      t.string   "wallet_address"
      t.integer  "currency"
      t.string   "currency_code"
      t.decimal  "balance",        precision: 32, scale: 18
      t.string   "token_address"
      t.integer  "token_decimals"
      t.string   "withdraw_state"
      t.timestamps
    end
  end

  def self.down
    drop_table :hd_wallet_withdraws
    drop_table :hd_wallet_balances
  end
end