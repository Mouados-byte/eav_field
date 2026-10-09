# frozen_string_literal: true

module EavField
  module HasFields
    extend ActiveSupport::Concern

    included do
      class_attribute :eav_field_validators, instance_accessor: false, default: {}.freeze
    end

    class_methods do
      def has_eav_fields
        association = reflect_on_association(:eav_values)
        return if association&.class_name == "EavField::Value"
        raise NotEnabled, "#{name} already defines an eav_values association" if association

        has_many :eav_values, -> { includes(:attribute_definition) }, as: :entity,
          class_name: "EavField::Value", inverse_of: :entity, autosave: true, dependent: :destroy
        validate :validate_eav_fields
      end

      def eav_field_definitions
        ensure_eav_fields_enabled!
        AttributeDefinition.where(entity_type: polymorphic_name)
      end

      def define_eav_field(name, type:, required: false, default: nil, **rules)
        eav_field_definitions.create!(name: name.to_s, data_type: type.to_s,
          required: required, default_value: default, validation_rules: rules)
      end

      def find_eav_field!(name)
        return DefinitionCache.fetch(self).find!(name) if DefinitionCache.active?

        eav_field_definitions.find_by(name: name.to_s) ||
          raise(UnknownField, "Unknown EAV field #{name.inspect} for #{self.name}")
      end

      def with_eav_field(name, value = Query::UNSET, **conditions)
        Query.new(self, find_eav_field!(name)).filter(value, conditions)
      end

      def order_by_eav_field(name, direction = :asc, nulls: :last)
        Query.new(self, find_eav_field!(name)).order(direction, nulls: nulls)
      end

      def validate_eav_field(name, &validator)
        raise ArgumentError, "A validator block is required" unless validator

        validators = [ *eav_field_validators[name.to_s], validator ].freeze
        self.eav_field_validators = eav_field_validators.merge(name.to_s => validators).freeze
      end

      def with_eav_definition_cache(&block)
        ensure_eav_fields_enabled!
        DefinitionCache.with(&block)
      end

      def reset_eav_field_cache
        ensure_eav_fields_enabled!
        DefinitionCache.invalidate(polymorphic_name)
      end

      def preload_eav_fields(records)
        ensure_eav_fields_enabled!
        records = records.to_a
        unless records.all? { |record| record.is_a?(base_class) }
          raise ArgumentError, "Records must belong to #{base_class.name}"
        end
        return records if records.empty?

        snapshot = DefinitionCache.fetch(self)
        snapshot.definitions
        ActiveRecord::Associations::Preloader.new(records: records, associations: :eav_values).call
        records.each { |record| record.instance_variable_set(:@eav_definition_snapshot, snapshot) }
        records
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
        definition = eav_definition_snapshot.find!(name)
        [ definition, definition.cast(value) ]
      end
      assignments.each { |definition, value| assign_eav_value(definition, value) }
    end

    def read_eav_field(name)
      definition = eav_definition_snapshot.find!(name)
      entry = eav_entry_for(definition)
      entry ? entry.value : definition.default
    end

    def write_eav_field(name, value)
      definition = eav_definition_snapshot.find!(name)
      assign_eav_value(definition, definition.cast(value))
      value
    end

    # Removing an override restores the definition's default on the next read.
    def delete_eav_field(name)
      definition = eav_definition_snapshot.find!(name)
      entry = eav_entry_for(definition)
      previous_value = entry ? entry.value : definition.default
      entry&.mark_for_destruction
      previous_value
    end

    def eav_fields_snapshot
      entries = eav_values.reject { |entry| entry.marked_for_destruction? || entry.destroyed? }
        .index_by(&:attribute_definition_id)
      eav_definition_snapshot.definitions.each_value.with_object({}.with_indifferent_access) do |definition, fields|
        entry = entries[definition.id]
        fields[definition.name] = entry ? entry.value : definition.default
      end
    end

    def reload(...)
      super.tap { @eav_definition_snapshot&.reload }
    end

    def reload_eav_field_definitions
      eav_definition_snapshot.reload
      self
    end

    private

    def eav_definition_snapshot
      self.class.send(:ensure_eav_fields_enabled!)
      @eav_definition_snapshot ||= DefinitionCache.fetch(self.class)
    end

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
      entry.attribute_definition = definition
      entry.value = value
    end

    def validate_eav_fields
      eav_definition_snapshot.definitions.each_value do |definition|
        entry = eav_entry_for(definition)
        value = entry ? entry.value : definition.default
        definition.validation_errors(value).each do |message|
          errors.add("eav_fields.#{definition.name}", message)
        end
        Array(self.class.eav_field_validators[definition.name]).each do |validator|
          validator.call(self, value)
        end
      end
    end
  end
end
