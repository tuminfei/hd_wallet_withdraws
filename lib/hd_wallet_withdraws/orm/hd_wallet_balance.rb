module HdWalletWithdraws
  module Orm
    class HdWalletBalance < ActiveRecord::Base
      self.table_name = 'hd_wallet_balances'
    end
  end
end