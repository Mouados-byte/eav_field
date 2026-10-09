# frozen_string_literal: true

module EavField
  module HasFields
    extend ActiveSupport::Concern

    class_methods do
      def has_eav_fields
        association = reflect_on_association(:eav_values)
        return if association&.class_name == "EavField::Value"
        raise NotEnabled, "#{name} already defines an eav_values association" if association

        has_many :eav_values, -> { includes(:attribute_definition) }, as: :entity,
          class_name: "EavField::Value", inverse_of: :entity, autosave: true, dependent: :destroy
        validate :validate_required_eav_fields
      end

      def eav_field_definitions
        ensure_eav_fields_enabled!
        AttributeDefinition.where(entity_type: polymorphic_name)
      end

      def define_eav_field(name, type:, required: false, default: nil)
        eav_field_definitions.create!(name: name.to_s, data_type: type.to_s,
          required: required, default_value: default)
      end

      def find_eav_field!(name)
        eav_field_definitions.find_by(name: name.to_s) ||
          raise(UnknownField, "Unknown EAV field #{name.inspect} for #{self.name}")
      end

      def with_eav_field(name, value)
        definition = find_eav_field!(name)
        raise UnsupportedQuery, "JSON field equality is not portable across databases" if definition.data_type == "json"

        cast_value = definition.cast(value)
        entries = Value.where(attribute_definition_id: definition.id, entity_type: polymorphic_name)
        matching = entries.where(Types.column_for(definition.data_type) => cast_value).select(:entity_id)
        result = where(primary_key => matching)
        if cast_value == definition.default
          result = result.or(where.not(primary_key => entries.select(:entity_id)))
        end
        result
      end

      private

      def ensure_eav_fields_enabled!
        return if reflect_on_association(:eav_values)&.class_name == "EavField::Value"

        raise NotEnabled, "Call has_eav_fields in #{name} before using EAV fields"
      end
    end

    def eav_fields
      self.class.send(:ensure_eav_fields_enabled!)
      FieldSet.new(self)
    end

    # Hash assignment merges fields; omitted fields retain their current values.
    def eav_fields=(fields)
      raise ArgumentError, "eav_fields must be a hash" unless fields.respond_to?(:each_pair)

      assignments = fields.each_pair.map do |name, value|
        definition = self.class.find_eav_field!(name)
        [ definition, definition.cast(value) ]
      end
      assignments.each { |definition, value| assign_eav_value(definition, value) }
    end

    def read_eav_field(name)
      definition = self.class.find_eav_field!(name)
      entry = eav_entry_for(definition)
      entry ? entry.value : definition.default
    end

    def write_eav_field(name, value)
      definition = self.class.find_eav_field!(name)
      assign_eav_value(definition, definition.cast(value))
      value
    end

    # Removing an override restores the definition's default on the next read.
    def delete_eav_field(name)
      definition = self.class.find_eav_field!(name)
      entry = eav_entry_for(definition)
      previous_value = entry ? entry.value : definition.default
      entry&.mark_for_destruction
      previous_value
    end

    def eav_fields_snapshot
      entries = eav_values.reject { |entry| entry.marked_for_destruction? || entry.destroyed? }
        .index_by(&:attribute_definition_id)
      self.class.eav_field_definitions.each_with_object({}.with_indifferent_access) do |definition, fields|
        entry = entries[definition.id]
        fields[definition.name] = entry ? entry.value : definition.default
      end
    end

    private

    def eav_entry_for(definition)
      eav_values.detect do |entry|
        entry.attribute_definition_id == definition.id && !entry.marked_for_destruction? && !entry.destroyed?
      end
    end

    def assign_eav_value(definition, value)
      entry = eav_entry_for(definition)
      unless entry
        deleted_entry = eav_values.detect do |candidate|
          candidate.attribute_definition_id == definition.id && candidate.persisted? && candidate.marked_for_destruction?
        end
        entry = deleted_entry.reload if deleted_entry
      end
      entry ||= eav_values.build(attribute_definition: definition)
      entry.value = value
    end

    def validate_required_eav_fields
      self.class.eav_field_definitions.where(required: true).each do |definition|
        entry = eav_entry_for(definition)
        value = entry ? entry.value : definition.default
        errors.add("eav_fields.#{definition.name}", "can't be blank") if Types.missing?(value)
      end
    end
  end
end
