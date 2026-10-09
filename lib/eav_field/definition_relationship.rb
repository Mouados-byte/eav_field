# frozen_string_literal: true

module EavField
  class DefinitionRelationship < ActiveRecord::Base
    self.table_name = "eav_field_definition_relationships"

    belongs_to :source_definition, class_name: "EavField::AttributeDefinition",
      inverse_of: :outgoing_relationships, optional: false
    belongs_to :target_definition, class_name: "EavField::AttributeDefinition",
      inverse_of: :incoming_relationships, optional: false

    validates :kind, presence: true, length: { maximum: 100 },
      format: { with: /\A[a-z][a-z0-9_]*\z/ }
    validates :target_definition_id, uniqueness: { scope: [ :source_definition_id, :kind ] }
    validate :definitions_are_persisted
    validate :definitions_share_scope
    validate :definitions_are_distinct

    before_validation { self.kind = kind.to_s }

    private

    def definitions_are_persisted
      %i[ source_definition target_definition ].each do |attribute|
        definition = public_send(attribute)
        errors.add(attribute, "must already be saved") if definition && !definition.persisted?
      end
    end

    def definitions_share_scope
      return unless source_definition && target_definition

      if source_definition.entity_type_in_database != target_definition.entity_type_in_database
        errors.add(:target_definition, "must belong to the same model as the source definition")
      end
    end

    def definitions_are_distinct
      return unless source_definition_id && source_definition_id == target_definition_id

      errors.add(:target_definition, "cannot be the source definition")
    end
  end
end
