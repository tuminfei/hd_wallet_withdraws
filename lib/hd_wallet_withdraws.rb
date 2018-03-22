require 'eth'
require 'bip44'

require "hd_wallet_withdraws/version"
require 'hd_wallet_withdraws/withdraw_server'

require 'active_record'
require 'active_hash'
require 'hd_wallet_withdraws/orm/hd_wallet_balance'
require 'hd_wallet_withdraws/orm/hd_wallet_withdraw'
require 'hd_wallet_withdraws/orm/currency'

require 'hd_wallet_withdraws/services/infura_client'

module HdWalletWithdraws


  class<< self
    attr_accessor :config, :database_config

    attr_writer :logger

    def init_yml=(options = {})
      unless options.empty?
        if options[:collect_config]
          @config = YAML.load(File.open(options[:collect_config]))
        end
        if options[:database_config]
          @database_config = YAML.load(File.open(options[:database_config]))
        end

        #database
        ActiveRecord::Base.establish_connection(
            :adapter  => @database_config['database']['adapter'],
            :host     => @database_config['database']['host'],
            :port     => @database_config['database']['port'],
            :username => @database_config['database']['username'],
            :password => @database_config['database']['password'],
            :database => @database_config['database']['database'],
            :encoding => @database_config['database']['encoding']
        )

        HdWalletWithdraws::Orm::Currency.data = @config['currencies']
      end
    end

    def logger
      @logger ||= Logger.new($stdout).tap do |log|
        log.progname = self.name
      end
    end

  end
end
