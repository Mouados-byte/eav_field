# frozen_string_literal: true

require "test_helper"

class InstallGeneratorTest < EavFieldTest
  def test_generator_supports_uuid_and_string_entity_ids
    %w[ uuid string ].each do |id_type|
      Dir.mktmpdir("eav-field-generator-") do |directory|
        EavField::Generators::InstallGenerator.start(
          [ "--entity-id-type=#{id_type}", "--quiet" ], destination_root: directory
        )
        migration = File.read(Dir[File.join(directory, "db/migrate/*_create_eav_field_tables.rb")].fetch(0))
        assert_includes migration, "t.column :entity_id, :#{id_type}, null: false"
        assert_includes migration, "ActiveRecord::Migration[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
