# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module EavField
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)
      desc "Upgrade EavField 0.1 tables to support persisted validation rules."

      def copy_migration
        migration_template "add_eav_field_validation_rules.rb.tt", "db/migrate/add_eav_field_validation_rules.rb"
      end

      private

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
