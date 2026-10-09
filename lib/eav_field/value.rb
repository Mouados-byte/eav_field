# frozen_string_literal: true

module EavField
  class Value < ActiveRecord::Base
    self.table_name = "eav_field_values"

    belongs_to :attribute_definition, class_name: "EavField::AttributeDefinition", inverse_of: :values, optional: false
    belongs_to :entity, polymorphic: true, inverse_of: :eav_values, optional: false

    validates :attribute_definition_id, uniqueness: { scope: [ :entity_type, :entity_id ] }
    validate :definition_matches_entity
    validate :typed_columns_are_valid

    def value
      self[Types.column_for(attribute_definition.data_type)]
    end

    def value=(input)
      cast_value = attribute_definition.cast(input)
      Types::COLUMNS.each_value { |column| self[column] = nil }
      self[Types.column_for(attribute_definition.data_type)] = cast_value
    end

    private

    def definition_matches_entity
      return unless entity && attribute_definition

      unless entity.class.reflect_on_association(:eav_values) && entity.class.polymorphic_name == attribute_definition.entity_type
        errors.add(:attribute_definition, "belongs to a different entity type")
      end
    end

    def typed_columns_are_valid
      return unless attribute_definition && Types::COLUMNS.key?(attribute_definition.data_type)

      active_column = Types.column_for(attribute_definition.data_type)
      if Types::COLUMNS.values.any? { |column| column != active_column && !self[column].nil? }
        errors.add(:value, "must use only the column matching its field type")
      end
      attribute_definition.cast(value)
      if attribute_definition.required? && Types.missing?(value)
        errors.add(:value, "can't be blank")
      end
    rescue InvalidValue => error
      errors.add(:value, error.message)
    end
  end
end
