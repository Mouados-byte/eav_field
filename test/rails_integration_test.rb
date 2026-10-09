# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class RailsIntegrationTest < EavFieldTest
  ROOT = File.expand_path("..", __dir__)

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
        puts "RAILS_INTEGRATION_OK"
      RUBY
      assert_includes output, "RAILS_INTEGRATION_OK"

      run_rails(directory, "db:rollback", "STEP=1")
      run_rails(directory, "runner", <<~RUBY)
        abort "rollback failed" if ActiveRecord::Base.connection.table_exists?(:eav_field_values)
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
      RUBY
    end
  end

  private

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
      { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "RAILS_ENV" => "test" },
      RbConfig.ruby, "bin/rails", *arguments, chdir: directory
    )
    assert status.success?, "rails #{arguments.first} failed:\n#{output}\n#{errors}"
    output
  end
end
