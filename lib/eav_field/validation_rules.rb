# frozen_string_literal: true

module EavField
  class ValidationRules
    ORDERED_TYPES = %w[ integer decimal date datetime ].freeze
    KEYS = %w[ min max min_length max_length choices ].freeze

    attr_reader :rules

    def initialize(type, input)
      @type = type.to_s
      raise InvalidValue, "Validation rules must be a hash" unless input.is_a?(Hash)

      @rules = input.transform_keys(&:to_s)
      unknown = @rules.keys - KEYS
      raise InvalidValue, "Unknown validation rules: #{unknown.join(', ')}" if unknown.any?

      normalize_bounds
      normalize_lengths
      normalize_choices
    end

    def errors_for(value)
      return [] if value.nil?

      errors = constraint_errors(value)
      if rules.key?("choices") && !rules["choices"].any? { |choice| Types.cast(@type, choice) == value }
        errors << "is not included in the allowed choices"
      end
      errors
    end

    private

    def constraint_errors(value)
      return [] if value.nil?

      errors = []
      if rules.key?("min") && value < Types.cast(@type, rules["min"])
        errors << "must be greater than or equal to #{rules['min']}"
      end
      if rules.key?("max") && value > Types.cast(@type, rules["max"])
        errors << "must be less than or equal to #{rules['max']}"
      end
      if rules.key?("min_length") && value.length < rules["min_length"]
        errors << "is too short (minimum is #{rules['min_length']} characters)"
      end
      if rules.key?("max_length") && value.length > rules["max_length"]
        errors << "is too long (maximum is #{rules['max_length']} characters)"
      end
      errors
    end

    def normalize_bounds
      bounds = rules.keys & %w[ min max ]
      return if bounds.empty?
      raise InvalidValue, "Minimum and maximum require a numeric, date, or datetime field" unless ORDERED_TYPES.include?(@type)

      bounds.each do |key|
        raise InvalidValue, "#{key} cannot be nil" if rules[key].nil?

        rules[key] = Types.dump(@type, rules[key])
      end
      if bounds.size == 2 && Types.cast(@type, rules["min"]) > Types.cast(@type, rules["max"])
        raise InvalidValue, "Minimum cannot exceed maximum"
      end
    end

    def normalize_lengths
      lengths = rules.keys & %w[ min_length max_length ]
      return if lengths.empty?
      raise InvalidValue, "Length rules require a string or text field" unless %w[ string text ].include?(@type)

      lengths.each do |key|
        unless rules[key].is_a?(Integer) && rules[key] >= 0
          raise InvalidValue, "#{key} must be a nonnegative integer"
        end
      end
      if lengths.size == 2 && rules["min_length"] > rules["max_length"]
        raise InvalidValue, "Minimum length cannot exceed maximum length"
      end
    end

    def normalize_choices
      return unless rules.key?("choices")
      unless rules["choices"].is_a?(Array) && !rules["choices"].empty?
        raise InvalidValue, "Choices must be a nonempty array"
      end

      rules["choices"] = rules["choices"].map { |choice| Types.dump(@type, choice) }.uniq
      if rules["choices"].any? { |choice| constraint_errors(Types.cast(@type, choice)).any? }
        raise InvalidValue, "Choices must satisfy the field's bounds and length rules"
      end
    end
  end
end
