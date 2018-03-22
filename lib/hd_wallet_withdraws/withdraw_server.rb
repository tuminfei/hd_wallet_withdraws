require 'rufus-scheduler'
require 'peatio_client'
require 'thread/pool'

module HdWalletWithdraws
  class WithdrawServer
    attr_accessor :scheduler_watcher, :scheduler_withdraw, :infura, :exchange_client

    def initialize

      scheduler_watcher = Rufus::Scheduler.new
      scheduler_withdraw = Rufus::Scheduler.new

      config = HdWalletWithdraws.config
      withdraw_when_ever = config['scheduler_params']['withdraw_when_ever']
      watcher_when_ever = config['scheduler_params']['watcher_when_ever']
      exchange_params = config['exchange_params']

      @infura = HdWalletWithdraws::Services::InfuraClient.new
      @exchange_client = PeatioAPI::Client.new access_key: config['exchange_params']['access_key'], secret_key: config['exchange_params']['secret_key'], endpoint: config['exchange_params']['api_url'], timeout: 60

      # 计划任务：查询账户地址余额
      scheduler_watcher.every watcher_when_ever||'3s', :tag => config['scheduler_name'] + '_watcher', :blocking => true do
        HdWalletWithdraws.logger.info "-----------watcher scheduler start-----------"
        # 查询当前同步的余额的最大数量
        wallet_ids = config['wallet_params']['wallet_ids'].split(',')
        max_id = HdWalletWithdraws::Orm::HdWalletBalance.maximum(:member_id) || 0

        start_id = max_id > wallet_ids[0].to_i ? max_id : wallet_ids[0].to_i
        start_id = start_id == wallet_ids[1].to_i ? wallet_ids[0].to_i : start_id

        currency_codes = HdWalletWithdraws::Orm::Currency.all
        # 并发执行
        pool = Thread.pool(currency_codes.size)
        ((start_id)..(wallet_ids[1].to_i)).each do |member_id|
          # 计算私钥
          wallet_xprv = HdWalletWithdraws.config['wallet_params']['wallet_xprv']
          wallet = Bip44::Wallet.from_xprv(wallet_xprv)
          sub_wallet = wallet.sub_wallet("m/#{member_id}")
          sub_address = sub_wallet.ethereum_address

          currency_codes.each do |currency|
            pool.process {
              save_balance(currency, member_id,sub_address)
            }
          end
        end
        pool.shutdown
      end

      # 计划任务：发起提币
      scheduler_withdraw.every withdraw_when_ever||'3s', :tag => config['scheduler_name']+ '_withdraw', :blocking => true do
        HdWalletWithdraws.logger.info "-----------withdraw scheduler start-----------"

        resp = @exchange_client.get '/api/v2/withdraws/all', page: 1, per_page: 50, tonce: Time.now.to_i, state: 'processing'#state: 'accept'
        withdraws = resp['data']
        withdraws.each do |withdraw|
          currency = withdraw['account']['currency']
          withdraw.merge!({'currency_code' => currency})
          withdraw.delete('account')
          withdraw.delete('channel')
          withdraw.delete('type')
          HdWalletWithdraws.logger.info "0.start withdraw: [#{withdraw}]"
          txid = withdraw!(withdraw, exchange_params)
          if txid
            HdWalletWithdraws.logger.info "4.post withdraw done: id[#{withdraw['id']}], txid[#{txid}]"
            @exchange_client.post '/api/v2/withdraws/succeed', id: withdraw['id'], txid: txid, tonce: Time.now.to_i
          else
            withdraw_db = HdWalletWithdraws::Orm::HdWalletWithdraw.where(id: withdraw['id']).first
            HdWalletWithdraws.logger.info "4.post withdraw done: id[#{withdraw_db.id}], txid[#{withdraw_db.txid}]"
            @exchange_client.post '/api/v2/withdraws/succeed', id: withdraw_db.id, txid: withdraw_db.txid, tonce: Time.now.to_i
          end
        end

      end

    end

    def fill_eth(private_key, to, gas_limit, gas_price, fill_gas_limit, fill_gas_price)
      # 目标地址上现有eth
      eth_balance = @infura.get_eth_balance(to)
      # 目标地址上需要填充满这么多eth
      amount = BigDecimal(gas_limit) * BigDecimal(gas_price) / 10**18
      return nil unless eth_balance < amount
      rawtx = @infura.generate_raw_transaction(private_key, (amount - eth_balance), nil, fill_gas_limit, fill_gas_price, to)
      txid = @infura.eth_send_raw_transaction(rawtx)
      return txid
    end

    def withdraw_token(private_key, from, to, amout, gas_limit, gas_price, token_address, token_decimals)
      # 余额查询
      token_balance = @infura.get_token_balance(from, token_address, token_decimals)
      return nil if token_balance < amout

      tx_id = @infura.transfer_token(private_key, token_address, token_decimals, amout, gas_limit, gas_price, to)
      return tx_id
    end

    def withdraw_eth(private_key, from, to, amout, gas_limit, gas_price)
      # 目标地址上现有eth
      eth_balance = @infura.get_eth_balance(from)
      # 提现花费金额
      withdraw_amount = BigDecimal(gas_limit) * BigDecimal(gas_price) / BigDecimal(10**18)

      return nil if eth_balance < amout + withdraw_amount
      rawtx = @infura.generate_raw_transaction(private_key, amout, nil, gas_limit, gas_price, to)
      txid = @infura.eth_send_raw_transaction(rawtx)
      return txid
    end

    # 获取钱包余额并保存
    def save_balance(currency, member_id, to_address)
      if currency.code == 'eth'
        balance = @infura.get_eth_balance(to_address)
      else
        balance = @infura.get_token_balance(to_address, currency.token_contract_address, currency.token_decimals)
      end

      hd_wallet_balance = HdWalletWithdraws::Orm::HdWalletBalance.where(:currency => currency.id, :member_id => member_id).first
      unless hd_wallet_balance.nil?
        hd_wallet_balance.member_id = member_id
        hd_wallet_balance.wallet_address = to_address
        hd_wallet_balance.currency = currency.id
        hd_wallet_balance.currency_code = currency.code
        hd_wallet_balance.balance = balance
        hd_wallet_balance.token_address = currency.token_contract_address
        hd_wallet_balance.token_decimals = currency.token_decimals
        hd_wallet_balance.save
      else
        hd_wallet_balance = HdWalletWithdraws::Orm::HdWalletBalance.new
        hd_wallet_balance.currency = currency.id
        hd_wallet_balance.member_id = member_id
        hd_wallet_balance.wallet_address = to_address
        hd_wallet_balance.currency = currency.id
        hd_wallet_balance.currency_code = currency.code
        hd_wallet_balance.balance = balance
        hd_wallet_balance.token_address = currency.token_contract_address
        hd_wallet_balance.token_decimals = currency.token_decimals
        hd_wallet_balance.save
      end


      HdWalletWithdraws.logger.info "get member_id[#{member_id}], address[#{to_address}], currency[#{currency.code}] balance:#{balance}"
    end

    # 获取提币钱包
    def find_wallet_address(currency_code, amount, exchange_params)
      # eth提币要预留转账费用
      if currency_code == 'eth'
        query_mount = amount + '0.001'
      else
        query_mount = amount
      end
      wallet_id = nil

      withdraw_address = HdWalletWithdraws::Orm::HdWalletBalance.where(["currency_code = ? and balance >= ? and withdraw_state is null", currency_code, query_mount]).order(:balance).first
      # 取交易所钱包
      sub_address = exchange_params['address']
      sub_key = exchange_params['private_key']

      if withdraw_address
        # 取用户钱包
        wallet_xprv = HdWalletWithdraws.config['wallet_params']['wallet_xprv']
        wallet = Bip44::Wallet.from_xprv(wallet_xprv)
        sub_wallet = wallet.sub_wallet("m/#{withdraw_address.member_id}")
        sub_address = sub_wallet.ethereum_address
        sub_key = sub_wallet.private_key

        withdraw_address.withdraw_state = 1
        withdraw_address.save
        wallet_id = withdraw_address.id
      end
      return sub_address, sub_key, wallet_id
    end

    def withdraw!(withdraw_info, exchange_params)
      txid = nil
      begin
        HdWalletWithdraws::Orm::HdWalletWithdraw.transaction do
          withdraw = HdWalletWithdraws::Orm::HdWalletWithdraw.where(id: withdraw_info['id']).first
          if withdraw.nil?
            withdraw = HdWalletWithdraws::Orm::HdWalletWithdraw.create(withdraw_info.symbolize_keys)
          end

          if withdraw.txid.nil?
            # 查询提币地址
            wallet_address, wallet_key, wallet_id = find_wallet_address(withdraw.currency_code, withdraw.amount, exchange_params)
            currency = HdWalletWithdraws::Orm::Currency.find_by_code(withdraw.currency_code)
            gas_limit = currency.gas_limit
            gas_price = currency.gas_price

            exchange_key = exchange_params['private_key']
            eth_gas_limit = exchange_params['fill_gas_limit']
            eth_gas_price = exchange_params['fill_gas_price']

            # 开始提币
            if withdraw.currency_code == 'eth'
              # 1. withdraw_eth
              txid = withdraw_eth(wallet_key, wallet_address, withdraw.fund_uid, withdraw.amount, gas_limit, gas_price)

              # 发送提币处理
              HdWalletWithdraws.logger.info "0.post call_rpc: id[#{withdraw.id}], txid[#{txid}]"
              @exchange_client.post '/api/v2/withdraws/call_rpc', id: withdraw.id, txid: txid, tonce: Time.now.to_i

              if txid
                HdWalletWithdraws.logger.info "1.withdraw_eth: to_address[#{wallet_address}], txid[#{txid}]"
                @infura.wait_for_miner(txid)
              end
            else
              # 2. withdraw_token
              fill_txid = fill_eth(exchange_key, wallet_address, gas_limit, gas_price, eth_gas_limit, eth_gas_price)
              if fill_txid
                HdWalletWithdraws.logger.info "2.fill eth to_address[#{wallet_address}], txid[#{fill_txid}]"
                @infura.wait_for_miner(fill_txid)
              end

              txid = withdraw_token(wallet_key, wallet_address, withdraw.fund_uid, withdraw.amount, gas_limit, gas_price, currency.token_contract_address, currency.token_decimals)

              # 发送提币处理
              HdWalletWithdraws.logger.info "0.post call_rpc: id[#{withdraw.id}], txid[#{txid}]"
              @exchange_client.post '/api/v2/withdraws/call_rpc', id: withdraw.id, txid: txid, tonce: Time.now.to_i

              if txid
                HdWalletWithdraws.logger.info "3.withdraw_token: to_address[#{wallet_address}], txid[#{txid}]"
                @infura.wait_for_miner(txid)
              end
            end

            unless txid.nil?
              withdraw.txid = txid
              withdraw.save

              # 更新钱包可用余额
              if wallet_id
                withdraw_address = HdWalletWithdraws::Orm::HdWalletBalance.find_by_id(wallet_id)
                withdraw_address.balance = withdraw_address.balance - withdraw.amount
                withdraw_address.save
              end
            end
          end
        end
      rescue Exception => e
        txid = nil
        HdWalletWithdraws.logger.info "提币失败，withdraw_info:【#{withdraw_info}】"
        HdWalletWithdraws.logger.error e
      end

      return txid
    end

    def run!
      while true
        puts ".."
        sleep(2)
      end
    end
  end
end