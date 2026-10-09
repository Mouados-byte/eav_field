# frozen_string_literal: true

module EavField
  class FieldSet
    include Enumerable

    def initialize(owner)
      @owner = owner
    end

    def [](name)
      @owner.read_eav_field(name)
    end

    def []=(name, value)
      @owner.write_eav_field(name, value)
    end

    def delete(name)
      @owner.delete_eav_field(name)
    end

    def fetch(name, *args, &block)
      to_h.fetch(name, *args, &block)
    end

    def each(&block)
      return enum_for(:each) unless block

      to_h.each(&block)
    end

    def to_h
      @owner.eav_fields_snapshot
    end

    def keys
      to_h.keys
    end
  end
end
