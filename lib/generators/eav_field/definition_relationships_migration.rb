# frozen_string_literal: true

module EavField
  module Generators
    module DefinitionRelationshipsMigration
      private

      def definition_relationships_table
        File.read(File.expand_path("templates/definition_relationships_table.rb.tt", __dir__))
      end
    end
  end
end
