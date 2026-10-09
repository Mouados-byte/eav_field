# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "rails"
require "eav_field"
require "generators/eav_field/install/install_generator"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Migration.verbose = false

# Exercise the shipped migration rather than maintaining a separate test schema.
Dir.mktmpdir("eav-field-schema-") do |directory|
  EavField::Generators::InstallGenerator.start([ "--quiet" ], destination_root: directory)
  load Dir[File.join(directory, "db/migrate/*_create_eav_field_tables.rb")].fetch(0)
  CreateEavFieldTables.migrate(:up)
end

ActiveRecord::Schema.define do
  create_table :products do |table|
    table.string :name
    table.string :type
  end
  create_table :customers do |table|
    table.string :name
  end
end

class Product < ActiveRecord::Base
  has_eav_fields
  validates :name, presence: true
end

class SpecialProduct < Product; end

class Customer < ActiveRecord::Base
  has_eav_fields
end

class PlainProduct < ActiveRecord::Base
  self.table_name = "products"
end

class EavFieldTest < Minitest::Test
  def setup
    EavField::Value.delete_all
    EavField::AttributeDefinition.delete_all
    Product.delete_all
    Customer.delete_all
  end

  def capture_selects
    queries = []
    listener = lambda do |*arguments|
      payload = arguments.last
      if payload[:sql].lstrip.start_with?("SELECT") && payload[:name] != "SCHEMA" && !payload[:cached]
        queries << payload[:sql]
      end
    end
    ActiveSupport::Notifications.subscribed(listener, "sql.active_record") do
      ActiveRecord::Base.uncached { yield }
    end
    queries
  end
end
