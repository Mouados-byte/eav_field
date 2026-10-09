# frozen_string_literal: true

require "test_helper"

class QueryTest < EavFieldTest
  def test_queries_cast_values_and_chain_with_normal_scopes
    Product.define_eav_field(:quantity, type: :integer)
    first = Product.create!(name: "Chair", eav_fields: { quantity: 2 })
    Product.create!(name: "Table", eav_fields: { quantity: 2 })
    Product.create!(name: "Chair", eav_fields: { quantity: 3 })

    assert_equal [ first.id ], Product.where(name: "Chair").with_eav_field(:quantity, "2").ids
  end

  def test_multiple_field_filters_can_be_chained
    Product.define_eav_field(:color, type: :string)
    Product.define_eav_field(:quantity, type: :integer)
    matching = Product.create!(name: "First", eav_fields: { color: "red", quantity: 2 })
    Product.create!(name: "Second", eav_fields: { color: "blue", quantity: 2 })
    Product.create!(name: "Third", eav_fields: { color: "red", quantity: 3 })

    assert_equal [ matching.id ], Product.with_eav_field(:color, "red").with_eav_field(:quantity, 2).ids
  end

  def test_queries_include_missing_rows_when_the_default_matches
    Product.define_eav_field(:color, type: :string, default: "black")
    implicit = Product.create!(name: "Implicit")
    explicit = Product.create!(name: "Explicit", eav_fields: { color: "black" })
    Product.create!(name: "Other", eav_fields: { color: "red" })
    Product.create!(name: "Null", eav_fields: { color: nil })

    assert_equal [ implicit.id, explicit.id ].sort, Product.with_eav_field(:color, "black").ids.sort
  end

  def test_nil_queries_include_implicit_nil_and_explicit_nil
    Product.define_eav_field(:color, type: :string)
    implicit = Product.create!(name: "Implicit")
    explicit = Product.create!(name: "Explicit", eav_fields: { color: nil })
    Product.create!(name: "Other", eav_fields: { color: "red" })

    assert_equal [ implicit.id, explicit.id ].sort, Product.with_eav_field(:color, nil).ids.sort
  end

  def test_false_default_queries_include_implicit_false
    Product.define_eav_field(:available, type: :boolean, default: false)
    implicit = Product.create!(name: "Implicit")
    explicit = Product.create!(name: "Explicit", eav_fields: { available: false })
    Product.create!(name: "Other", eav_fields: { available: true })

    assert_equal [ implicit.id, explicit.id ].sort, Product.with_eav_field(:available, "false").ids.sort
  end

  def test_queries_do_not_match_another_model_with_the_same_id
    Product.define_eav_field(:color, type: :string)
    Customer.define_eav_field(:color, type: :string)
    product = Product.create!(name: "Product", eav_fields: { color: "blue" })
    Customer.create!(id: product.id, name: "Customer", eav_fields: { color: "red" })

    assert_empty Product.with_eav_field(:color, "red")
  end

  def test_sti_query_keeps_the_subclass_scope
    Product.define_eav_field(:color, type: :string)
    Product.create!(name: "Regular", eav_fields: { color: "red" })
    special = SpecialProduct.create!(name: "Special", eav_fields: { color: "red" })

    assert_equal [ special.id ], SpecialProduct.with_eav_field(:color, "red").ids
  end

  def test_query_errors_are_explicit
    Product.define_eav_field(:quantity, type: :integer)
    Product.define_eav_field(:metadata, type: :json)

    assert_raises(EavField::UnknownField) { Product.with_eav_field(:missing, "x") }
    assert_raises(EavField::InvalidValue) { Product.with_eav_field(:quantity, "invalid") }
    assert_raises(EavField::UnsupportedQuery) { Product.with_eav_field(:metadata, { x: 1 }) }
  end

  def test_sql_metacharacters_are_treated_as_a_value
    Product.define_eav_field(:color, type: :string)
    unusual = "red' OR 1=1 --"
    matching = Product.create!(name: "First", eav_fields: { color: unusual })
    Product.create!(name: "Second", eav_fields: { color: "blue" })

    assert_equal [ matching.id ], Product.with_eav_field(:color, unusual).ids
  end
end
