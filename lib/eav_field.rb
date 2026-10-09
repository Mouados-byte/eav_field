# frozen_string_literal: true

require "active_record"
require "active_support/concern"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"

require "eav_field/version"
require "eav_field/errors"
require "eav_field/types"
require "eav_field/validation_rules"
require "eav_field/attribute_definition"
require "eav_field/definition_relationship"
require "eav_field/definition_cache"
require "eav_field/value"
require "eav_field/field_set"
require "eav_field/query"
require "eav_field/has_fields"

ActiveSupport.on_load(:active_record) do
  include EavField::HasFields
end

require "eav_field/railtie" if defined?(Rails::Railtie)
