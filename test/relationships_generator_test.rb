# frozen_string_literal: true

require "test_helper"
require "generators/eav_field/relationships/relationships_generator"

class RelationshipsGeneratorTest < EavFieldTest
  def test_relationships_generator_only_adds_its_table_and_indexes
    Dir.mktmpdir("eav-field-relationships-generator-") do |directory|
      EavField::Generators::RelationshipsGenerator.start([ "--quiet" ], destination_root: directory)
      migrations = Dir[File.join(directory, "db/migrate/*.rb")]
      assert_equal 1, migrations.size
      migration = File.read(migrations.first)
      assert_includes migration, "create_table :eav_field_definition_relationships"
      assert_includes migration, "foreign_key: { to_table: :eav_field_definitions, on_delete: :cascade }"
      assert_includes migration, "eav_definition_relationships_no_self_link"
      assert_includes migration, "[ :source_definition_id, :kind, :target_definition_id ], unique: true"
      assert_includes migration, "ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      refute_includes migration, "create_table :eav_field_definitions do"
      refute_includes migration, "create_table :eav_field_values"
    end
  end

  def test_fresh_installation_and_upgrade_use_the_same_relationship_schema
    Dir.mktmpdir("eav-field-relationships-schema-") do |directory|
      EavField::Generators::InstallGenerator.start([ "--quiet" ], destination_root: File.join(directory, "install"))
      EavField::Generators::RelationshipsGenerator.start([ "--quiet" ], destination_root: File.join(directory, "upgrade"))
      install = File.read(Dir[File.join(directory, "install/db/migrate/*.rb")].fetch(0))
      upgrade = File.read(Dir[File.join(directory, "upgrade/db/migrate/*.rb")].fetch(0))
      schema = File.read(File.expand_path("../lib/generators/eav_field/templates/definition_relationships_table.rb.tt", __dir__))

      assert_includes install, schema
      assert_includes upgrade, schema
    end
  end
end
