# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class RailsIntegrationTest < EavFieldTest
  def test_install_migrate_and_use_the_gem_in_a_real_rails_application
    Dir.mktmpdir("eav-field-rails-") do |directory|
      write_application(directory)
      run_rails(directory, "generate", "eav_field:install", "--quiet")
      run_rails(directory, "db:migrate")
      output = run_rails(directory, "runner", <<~RUBY)
        Product.define_eav_field(:color, type: :string, default: "black")
        product = Product.create!(name: "Chair", eav_fields: { color: "blue" })
        abort "value was not saved" unless product.reload.eav_fields[:color] == "blue"
        abort "query failed" unless Product.with_eav_field(:color, "blue").exists?(product.id)
        Product.define_eav_field(:weight, type: :decimal, min: 0, max: 100)
        product.update!(eav_fields: { weight: "1.25" })
        abort "range query failed" unless Product.with_eav_field(:weight, gt: 1, lte: 2).exists?(product.id)
        abort "sorting failed" unless Product.order_by_eav_field(:weight).first.id == product.id
        Product.preload_eav_fields(Product.all).each do |entry|
          abort "preload failed" unless entry.eav_fields[:color] == "blue"
        end
        product.eav_fields[:weight] = -1
        abort "validation failed" if product.valid?
        abort "owner error missing" if product.errors[:"eav_fields.weight"].empty?
        Product.define_eav_field(:country, type: :string)
        Product.define_eav_field(:state, type: :string)
        relationship = Product.relate_eav_fields(:state, :country, as: :depends_on)
        state = Product.find_eav_field!(:state)
        country = Product.find_eav_field!(:country)
        abort "outgoing relationship failed" unless state.related_definitions(as: :depends_on).ids == [country.id]
        abort "incoming relationship failed" unless country.referencing_definitions(as: :depends_on).ids == [state.id]
        abort "model relationships failed" unless Product.eav_field_relationships.ids == [relationship.id]
        puts "RAILS_INTEGRATION_OK"
      RUBY
      assert_includes output, "RAILS_INTEGRATION_OK"

      run_rails(directory, "db:rollback", "STEP=1")
      run_rails(directory, "runner", <<~RUBY)
        abort "rollback failed" if ActiveRecord::Base.connection.table_exists?(:eav_field_values)
        abort "relationship rollback failed" if ActiveRecord::Base.connection.table_exists?(:eav_field_definition_relationships)
        abort "owner table was removed" unless ActiveRecord::Base.connection.table_exists?(:products)
      RUBY
    end
  end

  def test_installation_supports_string_owner_ids
    Dir.mktmpdir("eav-field-string-ids-") do |directory|
      write_application(directory, id_type: :string)
      run_rails(directory, "generate", "eav_field:install", "--entity-id-type=string", "--quiet")
      run_rails(directory, "db:migrate")
      run_rails(directory, "runner", <<~RUBY)
        Product.define_eav_field(:color, type: :string)
        product = Product.create!(id: "external-product-1", name: "Chair", eav_fields: { color: "blue" })
        abort "value was not saved" unless product.reload.eav_fields[:color] == "blue"
        abort "query failed" unless Product.with_eav_field(:color, "blue").exists?(product.id)
        abort "owner ID changed" unless product.eav_values.first.entity_id == "external-product-1"
        abort "sorting failed" unless Product.order_by_eav_field(:color).first.id == product.id
      RUBY
    end
  end

  def test_upgrading_version_0_1_preserves_definitions_and_values_and_can_roll_back
    Dir.mktmpdir("eav-field-upgrade-rails-") do |directory|
      write_application(directory)
      write_legacy_eav_migration(directory)
      run_rails(directory, "db:migrate")
      run_rails(directory, "runner", <<~RUBY)
        product = Product.create!(name: "Legacy chair")
        EavField::AttributeDefinition.insert_all!([ {
          entity_type: "Product", name: "color", data_type: "string", required: false,
          default_value: "black", created_at: Time.current, updated_at: Time.current
        } ])
        EavField::Value.insert_all!([ {
          entity_type: "Product", entity_id: product.id,
          attribute_definition_id: EavField::AttributeDefinition.first.id, string_value: "blue",
          created_at: Time.current, updated_at: Time.current
        } ])
      RUBY
      run_rails(directory, "generate", "eav_field:upgrade", "--quiet")
      run_rails(directory, "generate", "eav_field:relationships", "--quiet")
      run_rails(directory, "db:migrate")
      run_rails(directory, "runner", <<~RUBY)
        field = Product.find_eav_field!(:color)
        abort "legacy default changed" unless field.default == "black"
        abort "legacy rules should be empty" unless field.validation_rules.nil?
        abort "relationship table missing" unless EavField::DefinitionRelationship.count == 0
        field.update!(validation_rules: { choices: %w[black blue] })
        product = Product.first
        abort "legacy value changed" unless product.eav_fields[:color] == "blue"
        product.eav_fields[:color] = "red"
        abort "upgraded validation failed" if product.valid?
        abort "legacy value was overwritten" unless product.reload.eav_fields[:color] == "blue"
      RUBY
      run_rails(directory, "db:rollback", "STEP=2")
      run_rails(directory, "runner", <<~RUBY)
        connection = ActiveRecord::Base.connection
        abort "upgrade rollback failed" if connection.column_exists?(:eav_field_definitions, :validation_rules)
        abort "relationship rollback failed" if connection.table_exists?(:eav_field_definition_relationships)
        abort "legacy definitions removed" unless EavField::AttributeDefinition.count == 1
        abort "legacy values removed" unless EavField::Value.first&.string_value == "blue"
        abort "owner removed" unless Product.first.name == "Legacy chair"
      RUBY
    end
  end

  def test_upgrading_version_0_2_adds_relationships_without_changing_definitions_or_values
    Dir.mktmpdir("eav-field-relationships-rails-") do |directory|
      write_application(directory)
      write_legacy_eav_migration(directory, validation_rules: true)
      run_rails(directory, "db:migrate")
      run_rails(directory, "runner", <<~RUBY)
        Product.define_eav_field(:country, type: :string, default: "US")
        Product.define_eav_field(:state, type: :string, choices: %w[CA NY])
        Product.create!(name: "Legacy chair", eav_fields: { state: "CA" })
      RUBY
      run_rails(directory, "generate", "eav_field:relationships", "--quiet")
      run_rails(directory, "db:migrate")
      run_rails(directory, "runner", <<~RUBY)
        relationship = Product.relate_eav_fields(:state, :country, as: :depends_on)
        state = Product.find_eav_field!(:state)
        country = Product.find_eav_field!(:country)
        abort "relationship failed" unless state.related_definitions(as: :depends_on).ids == [country.id]
        abort "inverse traversal failed" unless country.referencing_definitions.ids == [state.id]
        abort "stored value changed" unless Product.first.eav_fields[:state] == "CA"
        abort "default changed" unless Product.first.eav_fields[:country] == "US"
        abort "rules changed" unless state.validation_rules == { "choices" => %w[CA NY] }
        abort "extra value created" unless EavField::Value.count == 1
      RUBY
      run_rails(directory, "db:rollback", "STEP=1")
      run_rails(directory, "runner", <<~RUBY)
        abort "table not removed" if ActiveRecord::Base.connection.table_exists?(:eav_field_definition_relationships)
        abort "definitions changed" unless Product.eav_field_definitions.count == 2
        abort "stored value changed" unless Product.first.eav_fields[:state] == "CA"
        abort "rules changed" unless Product.find_eav_field!(:state).validation_rules == { "choices" => %w[CA NY] }
      RUBY
    end
  end

  private

  def write_legacy_eav_migration(directory, validation_rules: false)
    content = File.read(File.expand_path("fixtures/create_eav_field_tables_0_1.rb", __dir__))
    content = content.sub("      t.json :default_value\n", "      t.json :default_value\n      t.json :validation_rules\n") if validation_rules
    File.write(File.join(directory, "db/migrate/20000101000001_create_eav_field_tables.rb"), content)
  end

  def write_application(directory, id_type: :bigint)
    %w[ bin config app/models db/migrate ].each { |path| FileUtils.mkdir_p(File.join(directory, path)) }
    File.write(File.join(directory, "bin/rails"), <<~RUBY)
      APP_PATH = File.expand_path("../config/application", __dir__)
      require "rails/commands"
    RUBY
    File.write(File.join(directory, "config/application.rb"), <<~RUBY)
      require "bundler/setup"
      require "rails"
      require "active_record/railtie"
      require "eav_field"

      module EavFieldDummy
        class Application < Rails::Application
          config.root = File.expand_path("..", __dir__)
          config.eager_load = false
          config.secret_key_base = "eav_field_integration_test_only"
          config.logger = Logger.new(nil)
        end
      end
    RUBY
    File.write(File.join(directory, "config/environment.rb"), <<~RUBY)
      require_relative "application"
      Rails.application.initialize!
    RUBY
    File.write(File.join(directory, "config/database.yml"), <<~YAML)
      test:
        adapter: sqlite3
        database: db/test.sqlite3
    YAML
    File.write(File.join(directory, "Rakefile"), <<~RUBY)
      require_relative "config/application"
      Rails.application.load_tasks
    RUBY
    File.write(File.join(directory, "app/models/product.rb"), <<~RUBY)
      class Product < ActiveRecord::Base
        has_eav_fields
      end
    RUBY
    File.write(File.join(directory, "db/migrate/20000101000000_create_products.rb"), <<~RUBY)
      class CreateProducts < ActiveRecord::Migration[7.1]
        def change
          create_table :products, id: :#{id_type} do |t|
            t.string :name
          end
        end
      end
    RUBY
  end

  def run_rails(directory, *arguments)
    output, errors, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => Bundler.default_gemfile.to_s, "RAILS_ENV" => "test" },
      RbConfig.ruby, "bin/rails", *arguments, chdir: directory
    )
    assert status.success?, "rails #{arguments.first} failed:\n#{output}\n#{errors}"
    output
  end
end
