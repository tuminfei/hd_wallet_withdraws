require 'rails/generators/active_record'

class HdWalletWithdraws::MigrationGenerator < ::Rails::Generators::Base
  include Rails::Generators::Migration
  source_root File.expand_path('../templates', __FILE__)
  desc 'Installs hd wallet withraws migration file.'

  def install
    migration_template 'migration.rb', 'db/migrate/create_hd_wallet_withraws.rb'
  end

  def self.next_migration_number(dirname)
    ActiveRecord::Generators::Base.next_migration_number(dirname)
  end
end