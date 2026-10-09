# frozen_string_literal: true

require "test_helper"
require "generators/eav_field/upgrade/upgrade_generator"

class UpgradeGeneratorTest < EavFieldTest
  def test_upgrade_generator_creates_an_additive_reversible_migration
    Dir.mktmpdir("eav-field-upgrade-") do |directory|
      EavField::Generators::UpgradeGenerator.start([ "--quiet" ], destination_root: directory)
      migration = File.read(Dir[File.join(directory, "db/migrate/*_add_eav_field_validation_rules.rb")].fetch(0))

      assert_includes migration, "add_column :eav_field_definitions, :validation_rules, :json"
      assert_includes migration, "remove_column :eav_field_definitions, :validation_rules, :json"
      assert_includes migration, "ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      refute_includes migration, "create_table"
      refute_includes migration, "drop_table"
    end
  end
end
