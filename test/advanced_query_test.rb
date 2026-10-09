# frozen_string_literal: true

require "test_helper"

class AdvancedQueryTest < EavFieldTest
  def test_comparisons_include_matching_defaults_and_preserve_null_overrides
    Product.define_eav_field(:quantity, type: :integer, default: 5)
    implicit = Product.create!(name: "Implicit")
    equal = Product.create!(name: "Equal", eav_fields: { quantity: 5 })
    lower = Product.create!(name: "Lower", eav_fields: { quantity: 2 })
    higher = Product.create!(name: "Higher", eav_fields: { quantity: 8 })
    Product.create!(name: "Null", eav_fields: { quantity: nil })

    assert_equal [ higher.id ], Product.with_eav_field(:quantity, gt: "5").ids
    assert_equal [ implicit.id, equal.id, higher.id ].sort, Product.with_eav_field(:quantity, gte: 5).ids.sort
    assert_equal [ lower.id ], Product.with_eav_field(:quantity, lt: 5).ids
    assert_equal [ implicit.id, equal.id, lower.id ].sort, Product.with_eav_field(:quantity, lte: 5).ids.sort
    assert_equal [ implicit.id, equal.id ].sort, Product.with_eav_field(:quantity, gt: 2, lt: 8).ids.sort
  end

  def test_ranges_support_inclusive_exclusive_and_open_bounds
    Product.define_eav_field(:quantity, type: :integer, default: 3)
    implicit = Product.create!(name: "Implicit")
    one = Product.create!(name: "One", eav_fields: { quantity: 1 })
    two = Product.create!(name: "Two", eav_fields: { quantity: 2 })
    three = Product.create!(name: "Three", eav_fields: { quantity: 3 })

    assert_equal [ implicit.id, two.id, three.id ].sort, Product.with_eav_field(:quantity, 2..3).ids.sort
    assert_equal [ two.id ], Product.with_eav_field(:quantity, between: 2...3).ids
    assert_equal [ implicit.id, two.id, three.id ].sort, Product.with_eav_field(:quantity, between: [ "2", "3" ]).ids.sort
    assert_equal [ one.id, two.id ], Product.with_eav_field(:quantity, ...3).order(:id).ids
    assert_equal [ implicit.id, three.id ].sort, Product.with_eav_field(:quantity, 3..).ids.sort
    assert_empty Product.with_eav_field(:quantity, between: [ 3, 2 ])
  end

  def test_inclusion_casts_values_and_handles_nil_false_and_empty_lists
    Product.define_eav_field(:quantity, type: :integer, default: 2)
    implicit = Product.create!(name: "Implicit")
    explicit = Product.create!(name: "Explicit", eav_fields: { quantity: 3 })
    null = Product.create!(name: "Null", eav_fields: { quantity: nil })

    assert_equal [ implicit.id, explicit.id ].sort, Product.with_eav_field(:quantity, in: [ "2", 3 ]).ids.sort
    assert_equal [ implicit.id, null.id ].sort, Product.with_eav_field(:quantity, in: [ nil, 2 ]).ids.sort
    assert_empty Product.with_eav_field(:quantity, in: [])
    Product.define_eav_field(:available, type: :boolean, default: false)
    assert_equal Product.ids.sort, Product.with_eav_field(:available, in: [ "false" ]).ids.sort
  end

  def test_not_equal_uses_sql_null_semantics
    Product.define_eav_field(:color, type: :string, default: "black")
    implicit = Product.create!(name: "Implicit")
    red = Product.create!(name: "Red", eav_fields: { color: "red" })
    Product.create!(name: "Null", eav_fields: { color: nil })

    assert_equal [ implicit.id ], Product.with_eav_field(:color, not_eq: "red").ids
    assert_equal [ implicit.id, red.id ].sort, Product.with_eav_field(:color, not_eq: nil).ids.sort
  end

  def test_missing_checks_storage_independently_of_defaults_and_nulls
    Product.define_eav_field(:color, type: :string, default: "black")
    missing = Product.create!(name: "Missing")
    explicit = Product.create!(name: "Explicit", eav_fields: { color: "black" })
    null = Product.create!(name: "Null", eav_fields: { color: nil })

    assert_equal [ missing.id ], Product.with_eav_field(:color, missing: true).ids
    assert_equal [ explicit.id, null.id ].sort, Product.with_eav_field(:color, missing: false).ids.sort
  end

  def test_json_supports_missing_filters_but_not_comparisons_or_sorting
    Product.define_eav_field(:metadata, type: :json)
    missing = Product.create!(name: "Missing")
    Product.create!(name: "Stored", eav_fields: { metadata: {} })

    assert_equal [ missing.id ], Product.with_eav_field(:metadata, missing: true).ids
    assert_raises(EavField::UnsupportedQuery) { Product.with_eav_field(:metadata, in: [ {} ]) }
    assert_raises(EavField::UnsupportedQuery) { Product.order_by_eav_field(:metadata) }
  end

  def test_numeric_date_and_datetime_comparisons_cast_inputs
    Product.define_eav_field(:weight, type: :decimal)
    Product.define_eav_field(:released_on, type: :date)
    Product.define_eav_field(:published_at, type: :datetime)
    matching = Product.create!(name: "Chair", eav_fields: {
      weight: "1.25", released_on: "2026-01-02", published_at: "2026-01-02T10:00:00.123456Z"
    })

    assert_equal [ matching.id ], Product.with_eav_field(:weight, between: [ "1.24", "1.26" ]).ids
    assert_equal [ matching.id ], Product.with_eav_field(:released_on, gt: "2026-01-01").ids
    assert_equal [ matching.id ], Product.with_eav_field(:published_at, gte: "2026-01-02T12:00:00.123456+02:00").ids
  end

  def test_sorting_uses_defaults_but_does_not_replace_explicit_nil
    Product.define_eav_field(:quantity, type: :integer, default: 5)
    implicit = Product.create!(name: "Implicit")
    lower = Product.create!(name: "Lower", eav_fields: { quantity: 2 })
    higher = Product.create!(name: "Higher", eav_fields: { quantity: 8 })
    null = Product.create!(name: "Null", eav_fields: { quantity: nil })

    assert_equal [ lower.id, implicit.id, higher.id, null.id ], Product.order_by_eav_field(:quantity).ids
    assert_equal [ higher.id, implicit.id, lower.id, null.id ], Product.order_by_eav_field(:quantity, :desc).ids
    assert_equal [ null.id, lower.id, implicit.id, higher.id ], Product.order_by_eav_field(:quantity, nulls: :first).ids
    assert_equal [ null.id, higher.id, implicit.id, lower.id ], Product.order_by_eav_field(:quantity, "desc", nulls: "first").ids
  end

  def test_sorting_supports_false_and_nil_defaults
    Product.define_eav_field(:available, type: :boolean, default: false)
    implicit = Product.create!(name: "Implicit")
    available = Product.create!(name: "Available", eav_fields: { available: true })
    null = Product.create!(name: "Null", eav_fields: { available: nil })
    assert_equal [ implicit.id, available.id, null.id ], Product.order_by_eav_field(:available).ids

    Product.define_eav_field(:quantity, type: :integer)
    null.update!(eav_fields: { quantity: 1 })
    assert_equal null.id, Product.order_by_eav_field(:quantity).first.id
  end

  def test_sorting_is_chainable_and_keeps_owner_and_sti_scopes
    Product.define_eav_field(:quantity, type: :integer)
    Product.define_eav_field(:color, type: :string)
    Product.create!(name: "Regular", eav_fields: { quantity: 1, color: "blue" })
    first = SpecialProduct.create!(name: "Special", eav_fields: { quantity: 2, color: "blue" })
    second = SpecialProduct.create!(name: "Special", eav_fields: { quantity: 2, color: "red" })
    Customer.define_eav_field(:quantity, type: :integer)
    Customer.create!(id: first.id, name: "Customer", eav_fields: { quantity: 99 })

    relation = SpecialProduct.where(name: "Special").with_eav_field(:quantity, gte: 2)
      .order_by_eav_field(:quantity).order_by_eav_field(:color)
    assert_equal [ first.id, second.id ], relation.ids
    assert_equal [ first.id, second.id ], relation.order_by_eav_field(:quantity).ids
    assert_equal "Special", relation.first.name
  end

  def test_queries_do_not_apply_validation_rules_to_filter_inputs
    Product.define_eav_field(:quantity, type: :integer, min: 5, choices: [ 5, 10 ])
    matching = Product.create!(name: "Chair", eav_fields: { quantity: 5 })
    assert_equal [ matching.id ], Product.with_eav_field(:quantity, gt: 0).ids
    assert_empty Product.with_eav_field(:quantity, 3)
  end

  def test_invalid_operators_bounds_and_sort_arguments_are_rejected
    Product.define_eav_field(:quantity, type: :integer)
    Product.define_eav_field(:color, type: :string)
    invalid = [ {}, { typo: 1 }, { gt: nil }, { in: 1 }, { between: [ 1 ] },
      { between: [ nil, nil ] }, { missing: "true" }, { missing: true, eq: 1 } ]
    invalid.each do |conditions|
      assert_raises(EavField::UnsupportedQuery) { Product.with_eav_field(:quantity, **conditions) }
    end
    assert_raises(EavField::UnsupportedQuery) { Product.with_eav_field(:quantity, 1, gt: 0) }
    assert_raises(EavField::UnsupportedQuery) { Product.with_eav_field(:color, gt: "a") }
    assert_raises(EavField::InvalidValue) { Product.with_eav_field(:quantity, in: [ 1, "bad" ]) }
    assert_raises(EavField::UnsupportedQuery) { Product.order_by_eav_field(:quantity, "asc; DROP TABLE products") }
    assert_raises(EavField::UnsupportedQuery) { Product.order_by_eav_field(:quantity, nulls: :unknown) }
  end

  def test_inclusion_and_sort_defaults_quote_sql_metacharacters
    unusual = "red' OR 1=1 --"
    Product.define_eav_field(:color, type: :string, default: unusual)
    implicit = Product.create!(name: "Implicit")
    other = Product.create!(name: "Other", eav_fields: { color: "blue" })
    assert_equal [ implicit.id ], Product.with_eav_field(:color, in: [ unusual ]).ids
    assert_equal [ other.id, implicit.id ], Product.order_by_eav_field(:color).ids
  end
end
