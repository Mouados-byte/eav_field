# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"
require "generators/eav_field/definition_relationships_migration"

module EavField
  module Generators
    class RelationshipsGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      include DefinitionRelationshipsMigration

      source_root File.expand_path("templates", __dir__)
      desc "Add named relationships between existing EAV field definitions."

      def copy_migration
        migration_template "create_eav_field_definition_relationships.rb.tt",
          "db/migrate/create_eav_field_definition_relationships.rb"
      end

      private

      def migration_version
        "#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}"
      end
    end
  end
end
