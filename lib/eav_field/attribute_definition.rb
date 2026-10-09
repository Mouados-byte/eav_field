# frozen_string_literal: true

module EavField
  class AttributeDefinition < ActiveRecord::Base
    self.table_name = "eav_field_definitions"

    has_many :values, class_name: "EavField::Value", inverse_of: :attribute_definition, dependent: :destroy

    validates :entity_type, presence: true, length: { maximum: 255 }
    validates :name, presence: true, length: { maximum: 100 },
      format: { with: /\A[a-z][a-z0-9_]*\z/ }, uniqueness: { scope: :entity_type }
    validates :data_type, inclusion: { in: Types::COLUMNS.keys }
    validates :required, inclusion: { in: [ true, false ] }

    before_validation :normalize_default
    before_validation :normalize_validation_rules
    validate :identity_is_immutable, on: :update
    validate :default_satisfies_rules

    after_save :invalidate_definition_cache
    after_destroy :invalidate_definition_cache
    after_commit :invalidate_definition_cache
    after_rollback :invalidate_definition_cache

    def cast(value)
      Types.cast(data_type, value)
    end

    def default
      cast(default_value)
    end

    def validation_errors(value)
      errors = ValidationRules.new(data_type, validation_rules || {}).errors_for(cast(value))
      errors.unshift("can't be blank") if required? && Types.missing?(value)
      errors
    end

    private

    def normalize_validation_rules
      return unless Types::COLUMNS.key?(data_type)

      input = validation_rules.nil? ? {} : validation_rules
      self.validation_rules = ValidationRules.new(data_type, input).rules
    rescue InvalidValue => error
      errors.add(:validation_rules, error.message)
    end

    def default_satisfies_rules
      return if default_value.nil? || errors.any? || !Types::COLUMNS.key?(data_type)

      ValidationRules.new(data_type, validation_rules || {}).errors_for(default).each do |message|
        errors.add(:default_value, message)
      end
    end

    def invalidate_definition_cache
      DefinitionCache.invalidate(entity_type)
    end

    def normalize_default
      return unless Types::COLUMNS.key?(data_type)

      self.default_value = Types.dump(data_type, default_value)
    rescue InvalidValue => error
      errors.add(:default_value, error.message)
    end

    def identity_is_immutable
      %w[ entity_type name data_type ].each do |attribute|
        errors.add(attribute, "cannot change after creation") if will_save_change_to_attribute?(attribute)
      end
    end
  end
end
