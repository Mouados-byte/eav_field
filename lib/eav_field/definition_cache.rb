# frozen_string_literal: true

module EavField
  # Cache records on owners and within explicit blocks, never for an entire process.
  module DefinitionCache
    STATE_KEY = :eav_field_definition_cache
    @versions = Hash.new(0)
    @mutex = Mutex.new

    class Snapshot
      def initialize(model)
        @model = model.base_class
        @key = DefinitionCache.key(@model.polymorphic_name)
      end

      def definitions
        version = DefinitionCache.version(@key)
        if @version != version
          @definitions = @model.eav_field_definitions.to_a.index_by(&:name).freeze
          @version = version
        end
        @definitions
      end

      def find!(name)
        definitions.fetch(name.to_s) do
          raise UnknownField, "Unknown EAV field #{name.inspect} for #{@model.name}"
        end
      end

      def reload
        @version = nil
        definitions
        self
      end
    end

    module_function

    def key(entity_type)
      [ AttributeDefinition.connection_pool, entity_type ]
    end

    def version(key)
      @mutex.synchronize { @versions[key] }
    end

    def invalidate(entity_type)
      @mutex.synchronize { @versions[key(entity_type)] += 1 }
    end

    def fetch(model)
      cache = ActiveSupport::IsolatedExecutionState[STATE_KEY]
      return Snapshot.new(model) unless cache

      cache[key(model.polymorphic_name)] ||= Snapshot.new(model)
    end

    def active?
      !!ActiveSupport::IsolatedExecutionState[STATE_KEY]
    end

    def with
      previous = ActiveSupport::IsolatedExecutionState[STATE_KEY]
      ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous || {}
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[STATE_KEY] = previous
    end
  end
end
