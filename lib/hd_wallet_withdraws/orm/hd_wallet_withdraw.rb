module HdWalletWithdraws
  module Orm
    class HdWalletWithdraw < ActiveRecord::Base
      self.table_name = 'hd_wallet_withdraws'
    end
  end
end