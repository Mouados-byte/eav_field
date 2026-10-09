# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"
require "generators/eav_field/definition_relationships_migration"

module EavField
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include DefinitionRelationshipsMigration

      source_root File.expand_path("templates", __dir__)
      desc "Create the EAV field definitions, values, and definition relationships tables."

      class_option :entity_id_type, type: :string, default: "bigint", enum: %w[ bigint uuid string ],
        desc: "ID type of the existing models that will use EAV fields"

      def copy_migration
        migration_template "create_eav_field_tables.rb.tt", "db/migrate/create_eav_field_tables.rb"
      end

      private

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
