# frozen_string_literal: true

module EavField
  class Query
    UNSET = Object.new.freeze
    OPERATORS = %i[ eq not_eq gt gte lt lte in between missing ].freeze

    def initialize(model, definition)
      @model = model
      @definition = definition
      @scope = model.all
      @entries = Value.where(attribute_definition_id: definition.id, entity_type: model.polymorphic_name)
      @column = Value.arel_table[Types.column_for(definition.data_type)]
    end

    def filter(value, conditions)
      conditions = normalize_conditions(value, conditions)
      if conditions.key?(:missing)
        unless conditions.size == 1 && [ true, false ].include?(conditions[:missing])
          raise UnsupportedQuery, "missing must be a boolean and used on its own"
        end
        ids = @entries.select(:entity_id)
        return conditions[:missing] ? @scope.where.not(@model.primary_key => ids) : @scope.where(@model.primary_key => ids)
      end
      ensure_scalar!

      predicates = []
      default_predicates = []
      default = Arel::Nodes.build_quoted(@definition.default, @column)
      conditions.each do |operator, input|
        predicates << predicate_for(@column, operator, input)
        default_predicates << predicate_for(default, operator, input)
      end
      matching = @entries.where(predicates.reduce(&:and)).select(:entity_id)
      result = @scope.where(@model.primary_key => matching)
      # Evaluate fallback defaults in SQL using the same operators as stored values.
      missing = @scope.where.not(@model.primary_key => @entries.select(:entity_id))
        .where(default_predicates.reduce(&:and))
      result.or(missing)
    end

    def order(direction, nulls:)
      ensure_scalar!
      direction = direction.to_s
      nulls = nulls.to_s
      raise UnsupportedQuery, "Direction must be asc or desc" unless %w[ asc desc ].include?(direction)
      raise UnsupportedQuery, "nulls must be first or last" unless %w[ first last ].include?(nulls)

      owner = @model.arel_table
      values = Value.arel_table.alias("eav_sort_#{@definition.id}")
      join = owner.join(values, Arel::Nodes::OuterJoin).on(
        values[:entity_id].eq(owner[@model.primary_key])
          .and(values[:entity_type].eq(@model.polymorphic_name))
          .and(values[:attribute_definition_id].eq(@definition.id))
      ).join_sources
      default = Arel::Nodes.build_quoted(@definition.default, @column)
      effective = Arel::Nodes::Case.new.when(values[:id].eq(nil)).then(default)
        .else(values[Types.column_for(@definition.data_type)])
      null_order = Arel::Nodes::Case.new.when(effective.eq(nil)).then(nulls == "last" ? 1 : 0)
        .else(nulls == "last" ? 0 : 1).asc
      @scope.joins(join).order(null_order, direction == "asc" ? effective.asc : effective.desc)
    end

    private

    def normalize_conditions(value, conditions)
      unless value.equal?(UNSET)
        raise UnsupportedQuery, "Pass a value or operators, not both" if conditions.any?

        conditions = value.is_a?(Range) ? { between: value } : { eq: value }
      end
      unknown = conditions.keys - OPERATORS
      if conditions.empty? || unknown.any?
        raise UnsupportedQuery, "Supported operators: #{OPERATORS.join(', ')}"
      end
      conditions
    end

    def ensure_scalar!
      raise UnsupportedQuery, "JSON field comparisons and sorting are not portable across databases" if @definition.data_type == "json"
    end

    def predicate_for(column, operator, input)
      case operator
      when :eq, :not_eq
        value = @definition.cast(input)
        operator == :eq ? column.eq(value) : column.not_eq(value)
      when :in
        inclusion_predicate(column, input)
      when :between
        range_predicate(column, input)
      else
        comparison_predicate(column, operator, input)
      end
    end

    def inclusion_predicate(column, input)
      raise UnsupportedQuery, "in requires an array" unless input.is_a?(Array)

      values = input.map { |value| @definition.cast(value) }.uniq
      predicate = column.in(values.compact)
      predicate = predicate.or(column.eq(nil)) if values.include?(nil)
      predicate
    end

    def comparison_predicate(column, operator, input)
      ensure_ordered!
      value = @definition.cast(input)
      raise UnsupportedQuery, "Comparison bounds cannot be nil" if value.nil?

      arel_operator = { gt: :gt, gte: :gteq, lt: :lt, lte: :lteq }.fetch(operator)
      column.public_send(arel_operator, value)
    end

    def range_predicate(column, input)
      ensure_ordered!
      unless input.is_a?(Range) || (input.is_a?(Array) && input.size == 2)
        raise UnsupportedQuery, "between requires a range or a two-element array"
      end

      lower, upper = input.is_a?(Range) ? [ input.begin, input.end ] : input
      raise UnsupportedQuery, "A range needs at least one bound" if lower.nil? && upper.nil?

      conditions = []
      conditions << comparison_predicate(column, :gte, lower) unless lower.nil?
      upper_operator = input.is_a?(Range) && input.exclude_end? ? :lt : :lte
      conditions << comparison_predicate(column, upper_operator, upper) unless upper.nil?
      conditions.reduce(&:and)
    end

    def ensure_ordered!
      unless ValidationRules::ORDERED_TYPES.include?(@definition.data_type)
        raise UnsupportedQuery, "Ordered comparisons require a numeric, date, or datetime field"
      end
    end
  end
end
