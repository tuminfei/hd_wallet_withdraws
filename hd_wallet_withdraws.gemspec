# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "hd_wallet_withdraws/version"

Gem::Specification.new do |spec|
  spec.name          = "hd_wallet_withdraws"
  spec.version       = HdWalletWithdraws::VERSION
  spec.authors       = ["tarzansos"]
  spec.email         = ["tuminfei1981@gmail.com"]

  spec.summary       = "Hd Wallet Withdraws"
  spec.description   = "Hd Wallet Withdraws"
  spec.homepage      = "https://github.com/tuminfei/hd_wallet_withdraws"
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency 'thread', '>= 0.2.2'
  spec.add_dependency 'peatio_client'
  spec.add_dependency 'railties', '>= 3.1.0'
  spec.add_dependency 'activerecord', '>= 3.1.0'
  spec.add_dependency 'rufus-scheduler', '>= 3.4.2'
  spec.add_dependency 'faraday', '>= 0.11.0'
  spec.add_dependency 'active_hash', '~> 1.5.3'


  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
