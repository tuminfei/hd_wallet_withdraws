require 'faraday'
require 'json'

module HdWalletWithdraws
  module Services
    class InfuraCallError < StandardError; end
    class InvalidEthereumAddressError < StandardError; end
    class InvalidApiKeyError < StandardError; end
    class InvalidNetworkError < StandardError; end

    class InfuraClient

      BASE = 'https://api.infura.io'
      ETHEREUM_ADDRESS_REGEX = /^0x[0-9a-fA-F]{40}$/
      # Infura URLs for each network.
      NETWORK_URLS = {
          'main' => 'mainnet',
          'test' => 'ropsten',
      }.freeze

      JSON_RPC_METHODS = [
          'eth_getBalance',
          'eth_getTransactionCount',
          'eth_sendRawTransaction',
          'eth_call',
          'eth_getTransactionByHash'
      ].freeze

      BLOCK_PARAMETERS = [
          /^0x[0-9a-fA-F]{1,}$/, # an integer block number (hex string)
          /^earliest$/,          # for the earliest/genesis block
          /^latest$/,            # for the latest mined block
          /^pending$/            # for the pending state/transactions
      ].freeze

      def initialize(api_key: HdWalletWithdraws.config['infura_token'], network: HdWalletWithdraws.config['infura_chain'])
        validate_api_key(api_key)
        validate_network(network)

        @api_key = api_key
        @network = network
      end

      def eth_get_transaction_count(address, tag: 'latest')
        validate_address(address)
        result_hex_string = fetch('get', 'eth_getTransactionCount', [address, tag])
        result_hex_string.to_i(16)
      end

      def eth_send_raw_transaction(rawtx)
        result_hex_string = fetch('post', 'eth_sendRawTransaction', [rawtx])
        result_hex_string
      end

      def get_eth_balance(address, tag: 'latest')
        result_hex_string = fetch('get', 'eth_getBalance', [address, tag])
        BigDecimal(result_hex_string.to_i(16)) / BigDecimal(10**18)
      end

      def get_token_balance(address, token_contract_address, token_decimals, tag: 'latest')
        # Ethereum::Function.calc_id('balanceOf(address)') # 70a08231
        data = '0x70a08231' + padding(address)
        result_hex_string = fetch('get', 'eth_call', [{to: token_contract_address, data: data}, tag])
        result = result_hex_string.to_i(16)
        BigDecimal(result) / BigDecimal(10**token_decimals)
      end

      def transfer_token(private_key, token_address, token_decimals, amount, gas_limit, gas_price, to)
        function_signature = 'a9059cbb'
        amount_in_wei = (amount * (10**token_decimals)).to_i
        data = '0x' + function_signature + padding(to) + padding(dec_to_hex(amount_in_wei))

        #生成签名交易
        raw_tx = generate_raw_transaction(private_key, nil, data, gas_limit, gas_price, token_address)
        tx_id = eth_send_raw_transaction(raw_tx)
        tx_id
      end

      def generate_raw_transaction(priv, value, data, gas_limit, gas_price, to = nil, nonce = nil)
        key = ::Eth::Key.new priv: priv
        address = key.address
        gas_price_in_dec = gas_price
        nonce = nonce.nil? ? eth_get_transaction_count(address) : nonce
        args = {
            from: address,
            value: 0,
            data: '0x0',
            nonce: nonce,
            gas_limit: gas_limit,
            gas_price: gas_price_in_dec
        }
        args[:value] = (value * 10**18).to_i if value
        args[:data] = data if data
        args[:to] = to if to
        tx = ::Eth::Tx.new(args)
        tx.sign key
        tx.hex
      end

      def wait_for_miner(txhash, timeout: 1200, step: 20)
        start_time = Time.now
        loop do
          raise Timeout::Error if ((Time.now - start_time) > timeout)
          return true if mined?(txhash)
          sleep step
        end
      end

      def mined?(txhash)
        tx = fetch('get', 'eth_getTransactionByHash', [txhash])
        tx and (not tx['blockNumber'].nil?)
      end

      def fetch(http_method, action, params = nil)


        conn = Faraday.new(:url => BASE)

        if http_method == 'post'
          data = {}
          data[:jsonrpc] = '2.0'
          data[:id] = 57386342
          data[:token] = @api_key
          data[:method] = action
          data[:params] = params

          path = "/v1/jsonrpc/#{NETWORK_URLS[@network]}"
          resp = conn.post do |req|
            req.url path
            req.headers['Content-Type'] = 'application/json'
            req.body = data.to_json.to_s
          end
          body = resp.body

        else
          data = {}
          data[:token] = @api_key
          data[:params] = params.to_json if params

          path = "/v1/jsonrpc/#{NETWORK_URLS[@network]}/#{action}"
          body = conn.get(path, data).body
        end

        rep_data = JSON.parse(body)

        raise InfuraCallError, rep_data['error'] if rep_data['error']
        rep_data['result']
      end

      def padding(str)
        if str =~ /^0x[a-f0-9]*/
          str = str[2 .. str.length-1]
        end
        str.rjust(64, '0')
      end

      def dec_to_hex(value)
        '0x'+value.to_s(16)
      end

      private

      def validate_block_tag(tag)
        if BLOCK_PARAMETERS.none? { |regex| regex =~ tag.to_s }
          raise NotImplementedError.new("Block parameter tag '#{tag}' does not exist.")
        end
      end

      def validate_address(address)
        if ETHEREUM_ADDRESS_REGEX !~ address
          raise InvalidEthereumAddressError.new("'#{address}' is not a valid ethereum address.")
        end
      end

      def validate_json_rpc_method(method)
        if !JSON_RPC_METHODS.include?(method)
          raise NotImplementedError.new("JSON RPC method '#{method}' does not exist.")
        end
      end

      def validate_api_key(api_key)
        raise InvalidApiKeyError unless /^[a-zA-Z0-9]{20}$/ =~ api_key
      end

      def validate_network(network)
        raise InvalidNetworkError if NETWORK_URLS[network].nil?
      end
    end
  end
end