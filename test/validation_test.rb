# frozen_string_literal: true

require "test_helper"

class ValidationTest < EavFieldTest
  def test_numeric_bounds_are_inclusive_and_errors_belong_to_the_owner
    Product.define_eav_field(:quantity, type: :integer, min: 0, max: 10)
    product = Product.new(name: "Chair", eav_fields: { quantity: -1 })

    refute product.valid?
    assert_includes product.errors[:"eav_fields.quantity"], "must be greater than or equal to 0"
    refute product.save
    assert_equal 0, EavField::Value.count
    product.eav_fields[:quantity] = 0
    assert product.valid?
    product.eav_fields[:quantity] = 10
    assert product.valid?
    product.eav_fields[:quantity] = 11
    refute product.valid?
  end

  def test_decimal_bounds_keep_precision_when_definitions_reload
    field = Product.define_eav_field(:weight, type: :decimal, min: "0.1234567891", max: "9.1234567891")
    assert_equal "0.1234567891", field.reload.validation_rules["min"]
    product = Product.new(name: "Chair", eav_fields: { weight: "0.1234567890" })
    refute product.valid?
    product.eav_fields[:weight] = "0.1234567891"
    assert product.valid?
  end

  def test_date_and_datetime_bounds_are_typed
    Product.define_eav_field(:released_on, type: :date, min: Date.new(2026, 1, 1))
    Product.define_eav_field(:published_at, type: :datetime, max: "2026-01-01T10:00:00Z")
    product = Product.new(name: "Chair", eav_fields: {
      released_on: "2025-12-31", published_at: "2026-01-01T12:00:01+02:00"
    })

    refute product.valid?
    assert product.errors[:"eav_fields.released_on"].any?
    assert product.errors[:"eav_fields.published_at"].any?
    product.eav_fields = { released_on: "2026-01-01", published_at: "2026-01-01T12:00:00+02:00" }
    assert product.valid?
  end

  def test_string_and_text_lengths_count_characters
    Product.define_eav_field(:code, type: :string, min_length: 2, max_length: 3)
    Product.define_eav_field(:description, type: :text, max_length: 5)
    product = Product.new(name: "Chair", eav_fields: { code: "éé", description: "short" })
    assert product.valid?
    product.eav_fields[:code] = "a"
    refute product.valid?
    product.eav_fields = { code: "abcd", description: "too long" }
    refute product.valid?
    assert product.errors[:"eav_fields.code"].any?
    assert product.errors[:"eav_fields.description"].any?
  end

  def test_choices_are_cast_and_preserved_after_reload
    field = Product.define_eav_field(:quantity, type: :integer, choices: [ "1", 2, 2 ])
    assert_equal [ 1, 2 ], field.reload.validation_rules["choices"]
    product = Product.new(name: "Chair", eav_fields: { quantity: "2" })
    assert product.valid?
    product.eav_fields[:quantity] = 3
    refute product.valid?
    assert_includes product.errors[:"eav_fields.quantity"], "is not included in the allowed choices"
  end

  def test_false_zero_and_json_choices_are_supported
    Product.define_eav_field(:available, type: :boolean, required: true, choices: [ false ])
    Product.define_eav_field(:quantity, type: :integer, required: true, choices: [ 0 ])
    Product.define_eav_field(:metadata, type: :json, choices: [ { category: "a" } ])
    product = Product.new(name: "Chair", eav_fields: { available: false, quantity: 0, metadata: { category: "a" } })
    assert product.valid?
    product.eav_fields[:metadata] = { category: "b" }
    refute product.valid?
  end

  def test_optional_nil_values_skip_rules_but_required_nil_values_fail
    Product.define_eav_field(:size, type: :string, choices: %w[ small large ])
    required = Product.define_eav_field(:quantity, type: :integer, min: 1)
    product = Product.new(name: "Chair", eav_fields: { size: nil, quantity: nil })
    assert product.valid?
    required.update!(required: true)
    refute product.valid?
    assert_includes product.errors[:"eav_fields.quantity"], "can't be blank"
  end

  def test_defaults_must_satisfy_validation_rules
    [ { min: 10, default: 9 }, { max: 10, default: 11 }, { choices: [ 1, 2 ], default: 3 } ].each do |options|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Product.define_eav_field(:quantity, type: :integer, **options)
      end
      assert error.record.errors[:default_value].any?
    end
    field = Product.define_eav_field(:quantity, type: :integer, min: 10, default: 10)
    assert_raises(ActiveRecord::RecordInvalid) { field.update!(default_value: 9) }
    assert_equal 10, field.reload.default
  end

  def test_invalid_rule_definitions_are_rejected
    invalid = [
      [ :integer, { min: 2, max: 1 } ],
      [ :string, { min: 1 } ],
      [ :boolean, { max: 1 } ],
      [ :json, { max_length: 2 } ],
      [ :integer, { min: nil } ],
      [ :integer, { min: "bad" } ],
      [ :string, { min_length: -1 } ],
      [ :string, { max_length: 1.5 } ],
      [ :string, { min_length: 3, max_length: 2 } ],
      [ :string, { choices: [] } ],
      [ :string, { choices: "small" } ],
      [ :integer, { choices: [ "invalid" ] } ],
      [ :integer, { min: 5, choices: [ 3, 10 ] } ],
      [ :string, { max_length: 2, choices: [ "large" ] } ],
      [ :integer, { typo: 1 } ]
    ]
    invalid.each do |type, rules|
      error = assert_raises(ActiveRecord::RecordInvalid) do
        Product.define_eav_field(:field, type: type, **rules)
      end
      assert error.record.errors[:validation_rules].any?, rules.inspect
    end
  end

  def test_direct_rule_updates_reject_non_hash_configuration
    field = Product.define_eav_field(:quantity, type: :integer)
    [ false, [], "invalid" ].each do |rules|
      assert_raises(ActiveRecord::RecordInvalid) { field.update!(validation_rules: rules) }
    end
  end

  def test_rules_can_be_changed_without_changing_the_field_identity
    field = Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { quantity: 3 })
    field.update!(validation_rules: { "min" => 5 })

    refute product.valid?
    assert product.errors[:"eav_fields.quantity"].any?
    product.eav_fields[:quantity] = 5
    product.save!
    assert_equal 5, product.reload.eav_fields[:quantity]
  end

  def test_direct_value_saves_enforce_the_current_rules
    field = Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { quantity: 3 })
    entry = product.eav_values.first
    field.update!(validation_rules: { "min" => 5 })
    refute entry.valid?
    assert entry.errors[:value].any?
    entry.value = 5
    assert entry.valid?
  end

  def test_custom_validators_add_owner_errors_and_run_for_defaults
    Product.define_eav_field(:quantity, type: :integer, default: 3)
    Product.validate_eav_field(:quantity) do |record, value|
      record.errors.add("eav_fields.quantity", "must be even") if value && value.odd?
    end
    product = Product.new(name: "Chair")
    refute product.valid?
    assert_includes product.errors[:"eav_fields.quantity"], "must be even"
    product.eav_fields[:quantity] = 4
    assert product.valid?
    assert_raises(ArgumentError) { Product.validate_eav_field(:quantity) }
  ensure
    Product.eav_field_validators = {}.freeze
  end

  def test_custom_validators_are_inherited_and_accumulate
    Product.define_eav_field(:quantity, type: :integer)
    Product.validate_eav_field(:quantity) do |record, value|
      record.errors.add("eav_fields.quantity", "must be even") if value && value.odd?
    end
    Product.validate_eav_field(:quantity) do |record, value|
      record.errors.add("eav_fields.quantity", "must be positive") if value && value <= 0
    end
    product = SpecialProduct.new(name: "Chair", eav_fields: { quantity: -1 })
    refute product.valid?
    assert_equal [ "must be even", "must be positive" ], product.errors[:"eav_fields.quantity"]
    assert_empty Customer.eav_field_validators
  ensure
    Product.eav_field_validators = {}.freeze
  end
end
