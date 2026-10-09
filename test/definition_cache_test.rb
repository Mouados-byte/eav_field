# frozen_string_literal: true

require "test_helper"

class DefinitionCacheTest < EavFieldTest
  def test_repeated_reads_reuse_owner_definitions_and_values
    Product.define_eav_field(:color, type: :string, default: "black")
    Product.define_eav_field(:quantity, type: :integer)
    product = Product.create!(name: "Chair", eav_fields: { quantity: 1 }).reload
    product.eav_fields.to_h

    queries = capture_selects do
      3.times do
        assert_equal "black", product.eav_fields[:color]
        assert_equal 1, product.eav_fields[:quantity]
        assert_equal 2, product.eav_fields.to_h.size
      end
    end
    assert_empty queries
  end

  def test_preloading_uses_a_fixed_number_of_queries_and_reads_without_queries
    Product.define_eav_field(:color, type: :string, default: "black")
    Product.define_eav_field(:quantity, type: :integer)
    8.times { |index| Product.create!(name: "Product #{index}", eav_fields: { quantity: index }) }

    small_count = capture_selects { Product.preload_eav_fields(Product.limit(2)) }.size
    products = nil
    large_count = capture_selects { products = Product.preload_eav_fields(Product.all) }.size
    assert_equal small_count, large_count
    assert_operator large_count, :<=, 4
    queries = capture_selects do
      products.each do |product|
        assert_equal "black", product.eav_fields[:color]
        assert_kind_of Integer, product.eav_fields[:quantity]
        assert_equal 2, product.eav_fields.to_h.size
      end
    end
    assert_empty queries
  end

  def test_preloading_accepts_sti_and_preserves_unsaved_values
    Product.define_eav_field(:color, type: :string, default: "black")
    persisted = SpecialProduct.create!(name: "Persisted", eav_fields: { color: "red" })
    persisted.eav_fields[:color] = "blue"
    unsaved = Product.new(name: "Unsaved", eav_fields: { color: "green" })
    products = Product.preload_eav_fields([ persisted, unsaved ])

    assert_equal "blue", products.first.eav_fields[:color]
    assert_equal "green", products.last.eav_fields[:color]
    assert_equal [], Product.preload_eav_fields([])
    assert_raises(ArgumentError) { Product.preload_eav_fields([ Customer.new ]) }
    assert_raises(EavField::NotEnabled) { PlainProduct.preload_eav_fields([]) }
  end

  def test_explicit_cache_blocks_share_definitions_and_restore_the_outer_scope
    Product.define_eav_field(:color, type: :string, default: "black")
    queries = capture_selects do
      Product.with_eav_definition_cache do
        assert_equal "black", Product.new.eav_fields[:color]
        Product.with_eav_definition_cache do
          assert_equal "color", Product.find_eav_field!(:color).name
        end
        assert_equal "black", Product.new.eav_fields[:color]
      end
    end
    assert_equal(1, queries.count { |sql| sql.include?("eav_field_definitions") })
    refute EavField::DefinitionCache.active?
    assert_raises(RuntimeError) { Product.with_eav_definition_cache { raise "test" } }
    refute EavField::DefinitionCache.active?
  end

  def test_definitions_are_isolated_between_models_even_with_identical_names
    Product.define_eav_field(:color, type: :string, default: "black")
    Customer.define_eav_field(:color, type: :integer, default: 2)
    Product.with_eav_definition_cache do
      assert_equal "black", Product.new.eav_fields[:color]
      assert_equal 2, Customer.new.eav_fields[:color]
      assert_equal "black", SpecialProduct.new.eav_fields[:color]
    end
  end

  def test_local_definition_create_update_and_destroy_invalidate_loaded_snapshots
    field = Product.define_eav_field(:color, type: :string, default: "black")
    products = Product.preload_eav_fields([ Product.new(name: "First"), Product.new(name: "Second") ])
    field.update!(default_value: "red")
    assert_equal "red", products.first.eav_fields[:color]
    assert_equal "red", products.last.eav_fields[:color]
    Product.define_eav_field(:quantity, type: :integer, default: 2)
    assert_equal 2, products.first.eav_fields[:quantity]
    field.destroy!
    assert_raises(EavField::UnknownField) { products.last.eav_fields[:color] }
  end

  def test_cached_definitions_refresh_after_rollback
    field = Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.new(name: "Chair")
    assert_equal "black", product.eav_fields[:color]
    Product.transaction do
      field.update!(default_value: "red")
      assert_equal "red", product.eav_fields[:color]
      Product.define_eav_field(:quantity, type: :integer)
      assert_nil product.eav_fields[:quantity]
      raise ActiveRecord::Rollback
    end
    assert_equal "black", product.eav_fields[:color]
    assert_raises(EavField::UnknownField) { product.eav_fields[:quantity] }
  end

  def test_manual_reset_and_reload_refresh_changes_that_bypass_callbacks
    field = Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.new(name: "Chair")
    assert_equal "black", product.eav_fields[:color]
    Product.eav_field_definitions.where(id: field.id).update_all(default_value: "red")
    Product.reset_eav_field_cache
    assert_equal "red", product.eav_fields[:color]
    Product.eav_field_definitions.where(id: field.id).update_all(default_value: "blue")
    assert_same product, product.reload_eav_field_definitions
    assert_equal "blue", product.eav_fields[:color]
  end

  def test_owner_reload_refreshes_definition_snapshots
    field = Product.define_eav_field(:color, type: :string, default: "black")
    product = Product.create!(name: "Chair")
    assert_equal "black", product.eav_fields[:color]
    Product.eav_field_definitions.where(id: field.id).update_all(default_value: "red")
    assert_equal "red", product.reload.eav_fields[:color]
  end

  def test_owner_reload_refreshes_definitions_inside_a_shared_cache_block
    field = Product.define_eav_field(:color, type: :string, default: "black")
    Product.with_eav_definition_cache do
      product = Product.create!(name: "Chair")
      assert_equal "black", product.eav_fields[:color]
      Product.eav_field_definitions.where(id: field.id).update_all(default_value: "red")
      assert_equal "red", product.reload.eav_fields[:color]
    end
  end

  def test_definition_cache_is_execution_local
    Product.define_eav_field(:color, type: :string)
    Product.with_eav_definition_cache do
      assert EavField::DefinitionCache.active?
      assert_equal false, Thread.new { EavField::DefinitionCache.active? }.value
    end
  end
end
