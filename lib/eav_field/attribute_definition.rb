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
    validate :identity_is_immutable, on: :update

    def cast(value)
      Types.cast(data_type, value)
    end

    def default
      cast(default_value)
    end

    private

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
