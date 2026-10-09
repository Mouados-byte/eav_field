# frozen_string_literal: true

require "test_helper"

class DefinitionRelationshipTest < EavFieldTest
  def setup
    super
    @country = Product.define_eav_field(:country, type: :string)
    @state = Product.define_eav_field(:state, type: :string)
    @city = Product.define_eav_field(:city, type: :string)
  end

  def test_named_links_persist_their_direction_and_kind
    relationship = @state.relate_to(@country, as: :depends_on)

    assert_kind_of EavField::DefinitionRelationship, relationship
    assert relationship.persisted?
    assert_equal @state, relationship.reload.source_definition
    assert_equal @country, relationship.target_definition
    assert_equal "depends_on", relationship.kind
    assert_equal [ relationship ], @state.outgoing_relationships.to_a
    assert_equal [ relationship ], @country.incoming_relationships.to_a
    assert_empty @country.outgoing_relationships
  end

  def test_model_helpers_resolve_names_and_keep_relationships_scoped
    relationship = Product.relate_eav_fields(:state, "country", as: "depends_on")
    customer_country = Customer.define_eav_field(:country, type: :string)
    customer_state = Customer.define_eav_field(:state, type: :string)
    customer_relationship = customer_state.relate_to(customer_country, as: :depends_on)

    assert_equal [ relationship ], Product.eav_field_relationships.to_a
    assert_equal [ customer_relationship ], Customer.eav_field_relationships.to_a
    assert_equal [ relationship ], SpecialProduct.eav_field_relationships.to_a
    assert_raises(EavField::UnknownField) { Product.relate_eav_fields(:unknown, :country, as: :depends_on) }
    assert_raises(EavField::UnknownField) { Product.relate_eav_fields(:state, :unknown, as: :depends_on) }
    assert_raises(EavField::NotEnabled) { PlainProduct.eav_field_relationships }
  end

  def test_links_from_sti_subclasses_use_the_base_models_definitions
    relationship = SpecialProduct.relate_eav_fields(:state, :country, as: :depends_on)
    assert_equal "Product", relationship.source_definition.entity_type
    assert_equal [ relationship ], Product.eav_field_relationships.to_a
  end

  def test_traversal_filters_kinds_and_returns_chainable_relations
    @state.relate_to(@country, as: :depends_on)
    @state.relate_to(@country, as: :related_to)
    @state.relate_to(@city, as: :related_to)
    @city.relate_to(@country, as: :depends_on)

    assert_kind_of ActiveRecord::Relation, @state.related_definitions
    assert_equal [ @country.id, @city.id ].sort, @state.related_definitions.ids.sort
    assert_equal [ @country.id ], @state.related_definitions(as: :depends_on).ids
    assert_equal [ @city.id ], @state.related_definitions(as: "related_to").where(name: "city").ids
    assert_equal [ @state.id, @city.id ].sort, @country.referencing_definitions(as: :depends_on).ids.sort
    assert_equal [ @state.id ], @country.referencing_definitions(as: :related_to).ids
    assert_empty @state.related_definitions(as: :unknown)
  end

  def test_traversal_sees_changes_after_relationship_associations_were_loaded
    @state.outgoing_relationships.load
    @country.incoming_relationships.load
    EavField::DefinitionRelationship.create!(source_definition: @state, target_definition: @country, kind: "depends_on")

    assert_equal [ @country.id ], @state.related_definitions.ids
    assert_equal [ @state.id ], @country.referencing_definitions.ids
    @state.remove_relationship(@country, as: :depends_on)
    assert_empty @state.related_definitions
    assert_empty @country.referencing_definitions
  end

  def test_duplicate_links_are_rejected_but_distinct_kinds_are_allowed
    @state.relate_to(@country, as: :depends_on)
    error = assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(@country, as: :depends_on) }
    assert error.record.errors[:target_definition_id].any?
    @state.relate_to(@country, as: :related_to)
    assert_equal 2, @state.outgoing_relationships.count
  end

  def test_self_links_are_rejected
    error = assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(@state, as: :depends_on) }
    assert_includes error.record.errors[:target_definition], "cannot be the source definition"
    assert_equal 0, EavField::DefinitionRelationship.count
  end

  def test_relationship_kinds_use_field_name_conventions
    [ nil, "", "DependsOn", "depends-on", "1kind", "a" * 101 ].each do |kind|
      error = assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(@country, as: kind) }
      assert error.record.errors[:kind].any?
    end
    assert_equal "a" * 100, @state.relate_to(@country, as: "a" * 100).kind
  end

  def test_relationships_between_different_model_scopes_are_rejected
    customer_country = Customer.define_eav_field(:country, type: :string)
    error = assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(customer_country, as: :depends_on) }
    assert error.record.errors[:target_definition].any?
    assert_equal 0, EavField::DefinitionRelationship.count
  end

  def test_unsaved_scope_changes_cannot_disguise_a_cross_model_relationship
    customer_country = Customer.define_eav_field(:country, type: :string)
    @state.entity_type = "Customer"
    assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(customer_country, as: :depends_on) }
    assert_equal "Product", @state.reload.entity_type
  end

  def test_unsaved_or_destroyed_definitions_are_rejected_without_autosaving_them
    unsaved = Product.eav_field_definitions.new(name: "region", data_type: "string")
    error = assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(unsaved, as: :depends_on) }
    assert_includes error.record.errors[:target_definition], "must already be saved"
    assert_equal 3, Product.eav_field_definitions.count
    assert_raises(ActiveRecord::RecordNotSaved) { unsaved.relate_to(@country, as: :depends_on) }
    error = assert_raises(ActiveRecord::RecordInvalid) do
      EavField::DefinitionRelationship.create!(source_definition: unsaved, target_definition: @country, kind: :depends_on)
    end
    assert_includes error.record.errors[:source_definition], "must already be saved"
    refute unsaved.persisted?
    @city.destroy!
    assert_raises(ActiveRecord::RecordInvalid) { @state.relate_to(@city, as: :depends_on) }
    assert_equal 0, EavField::DefinitionRelationship.count
  end

  def test_remove_relationship_removes_only_the_requested_direction_and_kind
    @state.relate_to(@country, as: :depends_on)
    @state.relate_to(@country, as: :related_to)
    @country.relate_to(@state, as: :depends_on)

    assert_equal 1, @state.remove_relationship(@country, as: :depends_on)
    assert_equal 0, @state.remove_relationship(@country, as: :depends_on)
    assert_equal [ "related_to" ], @state.outgoing_relationships.pluck(:kind)
    assert_equal [ @state.id ], @country.related_definitions(as: :depends_on).ids
    assert_equal 0, @state.remove_relationship(@country, as: "related_to' OR 1=1 --")
    assert_equal 2, EavField::DefinitionRelationship.count
    assert_raises(ArgumentError) { @state.remove_relationship(nil, as: :depends_on) }
  end

  def test_destroying_a_definition_removes_both_directions_and_preserves_other_fields_and_values
    @state.relate_to(@country, as: :depends_on)
    @city.relate_to(@state, as: :depends_on)
    surviving = @city.relate_to(@country, as: :related_to)
    product = Product.create!(name: "Chair", eav_fields: { country: "US", state: "CA", city: "Oakland" })
    @state.destroy!

    assert_equal [ surviving.id ], EavField::DefinitionRelationship.ids
    assert_equal [ @country.id, @city.id ].sort, Product.eav_field_definitions.ids.sort
    assert_equal({ "country" => "US", "city" => "Oakland" }, product.reload.eav_fields.to_h)
    assert_equal 2, product.eav_values.count
  end

  def test_database_cascades_links_when_a_definition_is_deleted_without_callbacks
    @state.relate_to(@country, as: :depends_on)
    @city.relate_to(@state, as: :depends_on)
    @state.delete

    assert_equal 0, EavField::DefinitionRelationship.count
    assert Product.eav_field_definitions.exists?(@country.id)
    assert Product.eav_field_definitions.exists?(@city.id)
  end

  def test_database_indexes_and_constraints_protect_bulk_inserts
    @state.relate_to(@country, as: :depends_on)
    attributes = { source_definition_id: @state.id, target_definition_id: @country.id, kind: "depends_on" }
    assert_raises(ActiveRecord::RecordNotUnique) { EavField::DefinitionRelationship.insert_all!([ attributes ]) }
    assert_raises(ActiveRecord::StatementInvalid) do
      EavField::DefinitionRelationship.insert_all!([ attributes.merge(target_definition_id: @state.id) ])
    end
    assert_raises(ActiveRecord::InvalidForeignKey) do
      EavField::DefinitionRelationship.insert_all!([ attributes.merge(target_definition_id: -1) ])
    end
    assert_equal 1, EavField::DefinitionRelationship.count
  end

  def test_general_named_links_can_form_cycles_and_use_different_field_types
    rank = Product.define_eav_field(:rank, type: :integer)
    @state.relate_to(rank, as: :related_to)
    rank.relate_to(@state, as: :related_to)
    assert_equal [ rank.id ], @state.related_definitions.ids
    assert_equal [ @state.id ], rank.related_definitions.ids
  end

  def test_creating_and_removing_links_obey_transactions
    Product.transaction do
      @state.relate_to(@country, as: :depends_on)
      assert_equal [ @country.id ], @state.related_definitions.ids
      raise ActiveRecord::Rollback
    end
    assert_empty @state.related_definitions
    @state.relate_to(@country, as: :depends_on)
    Product.transaction do
      @state.remove_relationship(@country, as: :depends_on)
      assert_empty @state.related_definitions
      raise ActiveRecord::Rollback
    end
    assert_equal [ @country.id ], @state.related_definitions.ids
  end

  def test_rolling_back_definition_destruction_restores_its_relationships
    relationship = @state.relate_to(@country, as: :depends_on)
    Product.transaction do
      @state.destroy!
      assert_equal 0, EavField::DefinitionRelationship.count
      raise ActiveRecord::Rollback
    end
    assert_equal [ relationship.id ], @state.reload.outgoing_relationships.ids
    assert_equal [ @country.id ], @state.related_definitions.ids
  end

  def test_named_links_do_not_change_owner_validation_or_stored_values
    @state.relate_to(@country, as: :depends_on)
    product = Product.create!(name: "Chair", eav_fields: { state: "CA" })
    assert product.valid?
    assert_nil product.eav_fields[:country]
    assert_equal "CA", product.eav_fields[:state]
    assert_equal 1, product.eav_values.count
  end
end
