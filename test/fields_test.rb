# frozen_string_literal: true

require "test_helper"

class FailingProduct < Product
  after_save { raise "Simulated callback failure" }
end

class FieldsTest < EavFieldTest
  def test_all_types_persist_with_the_owner_and_round_trip
    samples = {
      string: [ "blue", "blue" ],
      text: [ "a" * 1000, "a" * 1000 ],
      integer: [ "42", 42 ],
      decimal: [ "1.2500000001", BigDecimal("1.2500000001") ],
      boolean: [ "false", false ],
      date: [ "2026-01-02", Date.new(2026, 1, 2) ],
      datetime: [ "2026-01-02T10:30:00.123456Z", Time.utc(2026, 1, 2, 10, 30, 0, 123456) ],
      json: [ { tags: [ "a", 1, false ] }, { "tags" => [ "a", 1, false ] } ]
    }
    samples.each_key { |type| Product.define_eav_field("field_#{type}", type: type) }
    product = Product.new(name: "Chair")
    samples.each { |type, pair| product.eav_fields["field_#{type}"] = pair.first }

    assert_equal 0, EavField::Value.count
    product.save!
    product.reload

    samples.each do |type, pair|
      assert_equal pair.last, product.eav_fields["field_#{type}"]
    end
    assert_equal samples.size, product.eav_values.count
  end

  def test_existing_records_can_update_only_eav_fields
    Product.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Chair", eav_fields: { color: "red" })
    product.eav_fields[:color] = "blue"

    assert_equal "red", Product.find(product.id).eav_fields[:color]
    product.save!

    assert_equal "blue", product.reload.eav_fields[:color]
    assert_equal 1, product.eav_values.count
  end

  def test_hash_assignment_merges_fields_and_works_with_update
    Product.define_eav_field(:color, type: :string)
    Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { color: "red", quantity: 2 })
    product.update!(eav_fields: { quantity: "3" })

    assert_equal "red", product.reload.eav_fields[:color]
    assert_equal 3, product.eav_fields[:quantity]
  end

  def test_invalid_batch_assignment_does_not_stage_partial_changes
    Product.define_eav_field(:color, type: :string)
    Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { color: "red", quantity: 2 })

    assert_raises(EavField::InvalidValue) { product.eav_fields = { color: "blue", quantity: "bad" } }
    assert_equal "red", product.eav_fields[:color]
    assert_equal 2, product.eav_fields[:quantity]
    assert_raises(ArgumentError) { product.eav_fields = [] }
  end

  def test_invalid_individual_assignment_keeps_the_previous_value
    Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { quantity: 2 })

    assert_raises(EavField::InvalidValue) { product.eav_fields[:quantity] = "bad" }
    product.save!
    assert_equal 2, product.reload.eav_fields[:quantity]
  end

  def test_unknown_fields_are_rejected
    product = Product.new(name: "Chair")

    assert_raises(EavField::UnknownField) { product.eav_fields[:unknown] }
    assert_raises(EavField::UnknownField) { product.eav_fields[:unknown] = 1 }
    assert_raises(EavField::UnknownField) { product.eav_fields = { unknown: 1 } }
    assert_raises(EavField::UnknownField) { product.eav_fields.delete(:unknown) }
  end

  def test_missing_fields_use_defaults_without_creating_rows
    Product.define_eav_field(:color, type: :string, default: "black")
    Product.define_eav_field(:available, type: :boolean, default: false)
    product = Product.create!(name: "Chair")

    assert_equal "black", product.eav_fields[:color]
    assert_equal false, product.eav_fields[:available]
    assert_equal 0, product.eav_values.count
  end

  def test_explicit_nil_overrides_a_default_and_deleting_restores_it
    Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.create!(name: "Chair", eav_fields: { color: nil })

    assert_nil product.reload.eav_fields[:color]
    assert_equal 1, product.eav_values.count
    assert_nil product.eav_fields.delete(:color)
    assert_equal "black", product.eav_fields[:color]
    assert_equal 1, EavField::Value.where(entity: product).count
    product.save!

    assert_equal "black", product.reload.eav_fields[:color]
    assert_equal 0, product.eav_values.count
  end

  def test_deleted_fields_can_be_reassigned_before_save
    Product.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Chair", eav_fields: { color: "red" })
    product.eav_fields.delete(:color)
    product.eav_fields[:color] = "blue"
    product.save!

    assert_equal "blue", product.reload.eav_fields[:color]
    assert_equal 1, product.eav_values.count
  end

  def test_new_fields_can_be_deleted_and_reassigned_before_the_owner_is_created
    Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.new(name: "Chair", eav_fields: { color: "red" })
    product.eav_fields.delete(:color)
    assert_equal "black", product.eav_fields[:color]
    product.eav_fields[:color] = "blue"
    product.eav_fields.delete(:color)
    product.eav_fields[:color] = "green"
    product.save!

    assert_equal "green", product.reload.eav_fields[:color]
    assert_equal 1, product.eav_values.count
  end

  def test_required_fields_fail_owner_validation_and_false_and_zero_are_present
    Product.define_eav_field(:available, type: :boolean, required: true)
    Product.define_eav_field(:quantity, type: :integer, required: true)
    product = Product.new(name: "Chair")

    refute product.valid?
    assert product.errors[:"eav_fields.available"].any?
    assert product.errors[:"eav_fields.quantity"].any?
    product.eav_fields = { available: false, quantity: 0 }
    assert product.valid?
    product.save!
  end

  def test_required_defaults_satisfy_validation_but_explicit_nil_does_not
    Product.define_eav_field(:available, type: :boolean, required: true, default: false)
    product = Product.create!(name: "Chair")
    product.eav_fields[:available] = nil

    refute product.valid?
    assert_raises(ActiveRecord::RecordInvalid) { product.save! }
    assert_equal false, product.reload.eav_fields[:available]
  end

  def test_whitespace_does_not_satisfy_required_string_fields
    Product.define_eav_field(:serial, type: :string, required: true)
    product = Product.new(name: "Chair", eav_fields: { serial: "  " })

    refute product.valid?
    assert_equal 0, EavField::Value.count
  end

  def test_failed_owner_validation_does_not_persist_new_or_updated_values
    Product.define_eav_field(:color, type: :string)
    unsaved = Product.new(eav_fields: { color: "red" })
    refute unsaved.save
    assert_equal 0, EavField::Value.count

    product = Product.create!(name: "Chair", eav_fields: { color: "red" })
    product.assign_attributes(name: nil, eav_fields: { color: "blue" })
    refute product.save
    assert_equal "red", product.reload.eav_fields[:color]
  end

  def test_callback_failure_rolls_back_the_owner_and_its_values
    Product.define_eav_field(:color, type: :string)
    product = FailingProduct.new(name: "Chair", eav_fields: { color: "red" })

    assert_raises(RuntimeError) { product.save! }
    assert_equal 0, Product.count
    assert_equal 0, EavField::Value.count
  end

  def test_destroying_the_owner_removes_values_but_preserves_definitions
    field = Product.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Chair", eav_fields: { color: "red" })
    product.destroy!

    assert_equal 0, EavField::Value.count
    assert EavField::AttributeDefinition.exists?(field.id)
  end

  def test_sti_uses_the_base_models_definitions_and_polymorphic_type
    Product.define_eav_field(:color, type: :string)
    product = SpecialProduct.create!(name: "Chair", eav_fields: { color: "red" })

    assert_equal "Product", product.eav_values.first.entity_type
    assert_equal "red", product.reload.eav_fields[:color]
    assert_equal Product.eav_field_definitions.ids, SpecialProduct.eav_field_definitions.ids
  end

  def test_definitions_from_another_model_cannot_be_used
    field = Product.define_eav_field(:color, type: :string)
    customer = Customer.create!(name: "Customer")
    entry = EavField::Value.new(entity: customer, attribute_definition: field)
    entry.value = "red"

    refute entry.valid?
    assert entry.errors[:attribute_definition].any?
  end

  def test_database_unique_index_protects_against_duplicate_values
    field = Product.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Chair", eav_fields: { color: "red" })

    assert_raises(ActiveRecord::RecordNotUnique) do
      EavField::Value.insert_all!([ { entity_type: "Product", entity_id: product.id,
        attribute_definition_id: field.id, string_value: "blue" } ])
    end
  end

  def test_default_json_values_are_independent_between_owners
    Product.define_eav_field(:metadata, type: :json, default: { tags: [] })
    first = Product.new(name: "First")
    second = Product.new(name: "Second")
    first.eav_fields[:metadata]["tags"] << "changed"

    assert_equal({ "tags" => [] }, second.eav_fields[:metadata])
  end

  def test_field_set_supports_indifferent_keys_enumeration_and_fetch
    Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.new(name: "Chair", eav_fields: { "color" => "red" })

    assert_equal "red", product.eav_fields["color"]
    assert_equal "red", product.eav_fields.to_h[:color]
    assert_equal [ [ "color", "red" ] ], product.eav_fields.each.to_a
    assert_equal [ "color" ], product.eav_fields.keys
    assert_equal "red", product.eav_fields.fetch(:color)
    assert_equal "fallback", product.eav_fields.fetch(:missing, "fallback")
    assert_raises(KeyError) { product.eav_fields.fetch(:missing) }
  end
end
