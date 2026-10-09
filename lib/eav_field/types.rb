# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

module EavField
  module Types
    COLUMNS = {
      "string" => "string_value",
      "text" => "text_value",
      "integer" => "integer_value",
      "decimal" => "decimal_value",
      "boolean" => "boolean_value",
      "date" => "date_value",
      "datetime" => "datetime_value",
      "json" => "json_value"
    }.freeze

    module_function

    def column_for(type)
      COLUMNS.fetch(type.to_s) { raise InvalidValue, "Unsupported field type: #{type.inspect}" }
    end

    def cast(type, value)
      column_for(type)
      return if value.nil?

      case type.to_s
      when "string", "text"
        raise TypeError unless value.is_a?(String)
        raise RangeError if type.to_s == "string" && value.length > 255

        value
      when "integer"
        cast_integer(value)
      when "decimal"
        cast_decimal(value)
      when "boolean"
        cast_boolean(value)
      when "date"
        cast_date(value)
      when "datetime"
        cast_datetime(value)
      when "json"
        cast_json(value)
      end
    rescue ArgumentError, TypeError, RangeError
      raise InvalidValue, "#{value.inspect} is not a valid #{type} value"
    end

    def dump(type, value)
      cast_value = cast(type, value)
      return if cast_value.nil?

      case type.to_s
      when "decimal"
        cast_value.to_s("F")
      when "date"
        cast_value.iso8601
      when "datetime"
        cast_value.iso8601(6)
      else
        cast_value
      end
    end

    def missing?(value)
      value != false && value.blank?
    end

    def cast_integer(value)
      number = if value.is_a?(Integer)
        value
      elsif value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)
        Integer(value, 10)
      else
        raise TypeError
      end
      raise RangeError unless (-(2**63)...(2**63)).cover?(number)

      number
    end

    def cast_decimal(value)
      raise TypeError unless value.is_a?(String) || value.is_a?(Integer) || value.is_a?(Float) || value.is_a?(BigDecimal)

      number = BigDecimal(value.to_s)
      raise RangeError unless number.finite? && number.abs < 10**20
      raise RangeError if number.to_s("F").split(".").last.length > 10

      number
    end

    def cast_boolean(value)
      return value if value == true || value == false
      return value == 1 if value.is_a?(Integer) && [ 0, 1 ].include?(value)
      return true if value.is_a?(String) && [ "true", "1" ].include?(value)
      return false if value.is_a?(String) && [ "false", "0" ].include?(value)

      raise TypeError
    end

    def cast_date(value)
      return value.to_date if value.is_a?(Date)
      raise TypeError unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(value)
    end

    def cast_datetime(value)
      return value.getutc.round(6) if value.is_a?(Time)
      return value.utc.round(6) if value.is_a?(ActiveSupport::TimeWithZone)
      return Time.iso8601(value.iso8601(6)).utc if value.is_a?(DateTime)

      unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})\z/)
        raise TypeError
      end

      Date.iso8601(value[0, 10])
      Time.iso8601(value).utc.round(6)
    end

    def cast_json(value)
      case value
      when Hash
        value.to_h do |key, item|
          raise TypeError unless key.is_a?(String) || key.is_a?(Symbol)

          [ key.to_s, cast_json(item) ]
        end
      when Array
        value.map { |item| cast_json(item) }
      when Float
        raise RangeError unless value.finite?

        value
      when String, Integer, TrueClass, FalseClass, NilClass
        value
      else
        raise TypeError
      end
    end
  end
end
