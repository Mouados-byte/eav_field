# frozen_string_literal: true

require "test_helper"

class AttributeDefinitionTest < EavFieldTest
  def test_definitions_are_scoped_to_models_and_unique_within_a_model
    product_field = Product.define_eav_field(:color, type: :string)
    customer_field = Customer.define_eav_field(:color, type: :integer)

    assert_equal "Product", product_field.entity_type
    assert_equal "Customer", customer_field.entity_type
    assert_equal [ product_field ], Product.eav_field_definitions.to_a
    assert_raises(ActiveRecord::RecordInvalid) { Product.define_eav_field(:color, type: :string) }
  end

  def test_invalid_names_and_types_are_rejected
    [ "", "bad-name", "Uppercase", "1name" ].each do |name|
      assert_raises(ActiveRecord::RecordInvalid) { Product.define_eav_field(name, type: :string) }
    end
    assert_raises(ActiveRecord::RecordInvalid) { Product.define_eav_field(:color, type: :unknown) }
  end

  def test_invalid_defaults_are_rejected_at_definition_time
    error = assert_raises(ActiveRecord::RecordInvalid) do
      Product.define_eav_field(:quantity, type: :integer, default: "invalid")
    end
    assert error.record.errors[:default_value].any?
    assert_equal 0, Product.eav_field_definitions.count
  end

  def test_typed_defaults_round_trip_without_losing_decimal_precision
    decimal = Product.define_eav_field(:weight, type: :decimal, default: "12.1234567891")
    date = Product.define_eav_field(:released_on, type: :date, default: Date.new(2026, 1, 2))
    datetime = Product.define_eav_field(:published_at, type: :datetime, default: Time.utc(2026, 1, 2, 3, 4, 5))
    boolean = Product.define_eav_field(:available, type: :boolean, default: false)

    assert_equal BigDecimal("12.1234567891"), decimal.reload.default
    assert_equal Date.new(2026, 1, 2), date.reload.default
    assert_equal Time.utc(2026, 1, 2, 3, 4, 5), datetime.reload.default
    assert_equal false, boolean.reload.default
  end

  def test_name_type_and_entity_scope_are_immutable
    { name: "other", data_type: "text", entity_type: "Customer" }.each do |attribute, value|
      field = Product.define_eav_field("field_#{attribute}", type: :string)
      assert_raises(ActiveRecord::RecordInvalid) { field.update!(attribute => value) }
    end
  end

  def test_defaults_and_required_flags_can_change
    field = Product.define_eav_field(:color, type: :string, default: "black")
    field.update!(required: true, default_value: "red")

    assert_equal "red", Product.new.eav_fields[:color]
    assert field.reload.required?
  end

  def test_destroying_a_definition_removes_its_values
    field = Product.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Chair", eav_fields: { color: "red" })
    field.destroy!

    assert_empty EavField::Value.where(entity: product)
    assert Product.exists?(product.id)
    assert_raises(EavField::UnknownField) { product.reload.eav_fields[:color] }
  end

  def test_models_must_opt_in
    assert_raises(EavField::NotEnabled) { PlainProduct.define_eav_field(:color, type: :string) }
    assert_raises(EavField::NotEnabled) { PlainProduct.new.eav_fields }
  end
end
