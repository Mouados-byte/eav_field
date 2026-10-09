# EavField

EavField adds an entity-attribute-value (EAV) system to existing Active Record models. Your model is the entity; database records define its dynamic attributes; separate records store their typed values. Adding a field does not require changing the owner's table.

Requires Ruby 3.2+ and Active Record/Railties 7.1–8.x. The gem constrains JSON to 2.x for compatibility with these Rails versions. The development suite uses SQLite and Minitest.

The published release is 0.1.0. This checkout prepares 0.2.0 with validation rules, advanced queries, sorting, and collection preloading. Use a local path or the GitHub dependency below to try these additions before publication.

## Install in a Rails application

Add the gem to your application's `Gemfile`:

```ruby
gem "eav_field", "~> 0.1.0"
```

Then run from the Rails application's root:

```sh
bundle install
bin/rails generate eav_field:install
bin/rails db:migrate
```

For local gem development, replace the dependency with `gem "eav_field", path: "../eav_field"`, adjusting the path to this checkout.

To use the upcoming 0.2.0 code from GitHub:

```ruby
gem "eav_field", github: "Mouados-byte/eav_field", branch: "main"
```

The generator creates `eav_field_definitions` and `eav_field_values`. Owner IDs use `bigint` by default. For PostgreSQL UUID owners, generate with `--entity-id-type=uuid`; for string IDs, use `--entity-id-type=string`. All participating models must have IDs compatible with the selected column type.

Opt in on any existing model:

```ruby
class Product < ApplicationRecord
  has_eav_fields
end
```

## Upgrade an existing 0.1.0 installation

After updating the dependency to the 0.2.0 code, generate and run the additive migration:

```sh
bin/rails generate eav_field:upgrade
bin/rails db:migrate
```

This adds the nullable `validation_rules` JSON column and preserves definitions and values. Existing definitions start without extra rules. Fresh installations already include this column; run only `eav_field:install` for those. Roll back the upgrade migration before switching the application back to 0.1.0. Rolling back discards validation rules but preserves stored values.

## Define and use fields

Create definitions after migrating, for example in a Rails console or data migration:

```ruby
Product.define_eav_field(:color, type: :string, default: "black")
Product.define_eav_field(:weight, type: :decimal)
Product.define_eav_field(:available, type: :boolean, required: true, default: false)
Product.define_eav_field(:metadata, type: :json)

product = Product.new(name: "Chair")
product.eav_fields = { color: "blue", weight: "1.25", metadata: { origin: "MA" } }
product.save!

product.reload.eav_fields[:color]     # => "blue"
product.eav_fields[:weight]           # => BigDecimal("1.25")
product.eav_fields[:available]        # => false
product.eav_fields.to_h               # All defined fields, including defaults.

product.eav_fields[:color] = "green"
product.save!                        # Saves field changes with the owner.
product.update!(eav_fields: { weight: "1.5" })
```

Both symbol and string keys work. Hash assignment merges fields; omitted fields keep their values. `read_eav_field`, `write_eav_field`, and `delete_eav_field` are also available directly on the owner.

Definitions are scoped to the model's polymorphic base class. Different models can use the same field name with different types. STI subclasses share their base model's definitions. Names use lowercase letters, digits, and underscores, starting with a letter, such as `shipping_weight`.

Definitions persist across application restarts. Keep definition creation out of model class bodies. Duplicate definitions raise `ActiveRecord::RecordInvalid`; for repeatable seeds, check `Product.eav_field_definitions.exists?(name: "color")` before defining a field.

## Types and validation

| Type | Accepted values |
| --- | --- |
| `string` | Strings up to 255 characters |
| `text` | Longer strings |
| `integer` | Signed 64-bit integers or whole-number strings |
| `decimal` | Finite numbers or numeric strings; precision 30, scale 10 |
| `boolean` | `true`, `false`, `1`, `0`, or their lowercase string forms |
| `date` | `Date` objects or `YYYY-MM-DD` strings |
| `datetime` | Time objects or ISO 8601 strings with an explicit offset; stored in UTC |
| `json` | JSON-compatible objects, arrays, and scalar values; keys become strings |

Unknown fields raise `EavField::UnknownField`. Invalid assignments raise `EavField::InvalidValue` immediately. Every value in a batch is checked before any field is changed. Required fields participate in owner validation, and `false` and `0` count as present. Datetimes use microsecond precision. [SQLite's numeric storage](https://sqlite.org/datatype3.html#type_affinity) can lose precision for large decimal values; validate decimal behavior against your application's database.

Missing value records return the definition's default without creating a row. Assigning `nil` stores an explicit null override. Delete the override to restore the default:

```ruby
product.eav_fields.delete(:color)
product.save!
product.eav_fields[:color] # => "black"
```

Definition names, types, and entity scopes are immutable after creation. Defaults, `required` flags, and `validation_rules` can be updated through `Product.eav_field_definitions`. Adding or tightening a rule affects existing owners on their next validation; it does not rewrite stored values.

## Validation rules

```ruby
Product.define_eav_field(:weight, type: :decimal, min: 0, max: "100.5")
Product.define_eav_field(:size, type: :string, choices: %w[small medium large])
Product.define_eav_field(:serial, type: :string, min_length: 3, max_length: 20)
Product.define_eav_field(:released_on, type: :date, min: "2026-01-01")

product.eav_fields[:weight] = -1
product.valid?                      # => false
product.errors["eav_fields.weight"] # => ["must be greater than or equal to 0"]
```

`min` and `max` are inclusive and support integer, decimal, date, and datetime fields. `min_length` and `max_length` count characters in strings and text. `choices` accepts a nonempty array of values matching the field's type; each choice must also satisfy the bounds and length rules. Optional `nil` values skip these rules; use `required: true` to reject missing values. Unknown or incompatible rules and defaults that violate rules are rejected when saving the definition.

Type errors still raise immediately on assignment. Rule violations participate in owner validation, so forms can display errors before saving. Direct value saves also enforce the persisted rules. To edit rules, replace the definition's hash:

```ruby
Product.eav_field_definitions.find_by!(name: "weight")
  .update!(validation_rules: { min: 1, max: 200 })
```

Keep custom validators in model code. They run when validating an owner, receive its effective value including defaults, and can add ordinary Rails errors:

```ruby
class Product < ApplicationRecord
  has_eav_fields

  validate_eav_field(:quantity) do |record, value|
    record.errors.add("eav_fields.quantity", "must be even") if value && value.odd?
  end
end
```

Multiple blocks accumulate and are inherited by subclasses. Registering a block does not create a definition; define the field separately after migration. Custom blocks run through owner validation, so save the owner when using them.

## Query fields

```ruby
Product.with_eav_field(:color, "blue")
Product.where(name: "Chair").with_eav_field(:weight, "1.25")
Product.with_eav_field(:color, "blue").with_eav_field(:available, false)
Product.with_eav_field(:weight, gt: "1.25", lte: "10")
Product.with_eav_field(:weight, 1...10)
Product.with_eav_field(:color, in: %w[blue green])
Product.with_eav_field(:color, missing: true)
Product.order_by_eav_field(:weight, :asc, nulls: :last).order(:id)
```

These return chainable Active Record relations and use persisted values. Matching defaults include owners without a stored override; explicit null overrides remain distinct from non-null defaults. Filter inputs are type-cast but need not satisfy validation rules: `gt: 0` is valid even if a field requires `min: 5`.

| Operator | Behavior |
| --- | --- |
| `eq`, `not_eq` | Equality and inequality; a positional value means `eq`. |
| `gt`, `gte`, `lt`, `lte` | Numeric, date, or datetime comparisons. |
| `in` | Match a typed array of values; `nil` matches null values; an empty array matches nothing. |
| `between` | A Ruby range or inclusive `[lower, upper]` pair; exclusive and open-ended ranges are supported. A positional range means `between`. |
| `missing` | `true` means no stored row, even when a default exists; `false` means a stored row exists, including an explicit null. Use this operator alone. |

Multiple operators in one call use AND. Supply either a positional value or keyword operators. Inequality follows SQL null semantics: `not_eq: "blue"` excludes nulls; `not_eq: nil` selects non-null effective values. JSON supports `missing` filters; other comparisons and sorting raise `EavField::UnsupportedQuery` because their behavior differs between adapters.

Sorting uses effective defaults, preserves explicit null overrides, and supports `:asc`/`:desc` and `nulls: :first`/`:last`. It appends to existing ordering. Add a normal column such as `.order(:id)` to break ties. String ordering follows the database's collation.

## Efficient loading and definition caching

```ruby
products = Product.preload_eav_fields(Product.where(name: "Chair").limit(100))
products.each do |product|
  puts product.eav_fields[:color]
  puts product.eav_fields[:weight]
end

Product.with_eav_definition_cache do
  Product.with_eav_field(:color, "blue").count
  Product.with_eav_field(:weight, gt: 1).count
end
```

`preload_eav_fields` returns an array, batches value loading, and shares one definition snapshot across the records. Repeated reads of preloaded fields require no queries. Pass owners from one model or its STI subclasses; unsaved changes are preserved. For large exports, call it for each `find_in_batches` batch.

Owners cache their definition snapshot on first use. `with_eav_definition_cache` additionally shares definitions within an execution-local block, including class-level lookups. Nested blocks share the same cache, which is removed when the outer block exits.

Definition creates, updates, deletes, commits, and rollbacks through Active Record callbacks invalidate snapshots in the current process. Loaded owners retain snapshots of changes made by another process, just as loaded associations do. Refresh them with `product.reload_eav_field_definitions` or `product.reload`; call `Product.reset_eav_field_cache` after bulk changes that bypass callbacks. These caches do not retain definition records globally across requests or database connections.

## Persistence and lifecycle

The gem uses [Rails polymorphic associations](https://guides.rubyonrails.org/association_basics.html#polymorphic-associations) and [association autosave](https://api.rubyonrails.org/classes/ActiveRecord/AutosaveAssociation.html) to validate and save values in the owner's transaction. Unique indexes prevent duplicate definitions and duplicate values for an owner and field. The definition foreign key cascades deletion of its values.

The EAV tables and participating models must use the same Active Record database connection. Multiple databases and composite owner primary keys are outside the current scope.

Destroying an owner deletes its values and preserves definitions. Destroying a definition removes that field's stored values for all owners. Active Record operations that bypass callbacks, such as `delete_all`, also bypass owner cleanup. Polymorphic owner references have no database foreign key; use `destroy`/`destroy_all` when cleanup is required.

Definitions are shared across a model rather than scoped per tenant. The gem does not add controllers, an administration UI, or authorization policies.

## Develop and verify

Run from this repository's root:

```sh
bundle install
bundle exec rake test       # Minitest, including real Rails installation and rollback.
bundle exec rubocop         # Lint and check formatting.
bundle exec rubocop -a      # Apply safe formatting corrections.
bundle exec rake            # Tests and lint together.
bundle exec rake build      # Build pkg/eav_field-0.2.0.gem.
```

To check a different Rails series:

```sh
RAILS_VERSION="~> 7.1.0" bundle update
RAILS_VERSION="~> 7.1.0" bundle exec rake test
bundle update              # Restore the default Rails 8.1 development bundle.
```

Implementation lives in `lib/eav_field/`; generators and migration templates live in `lib/generators/`; tests live in `test/` and use `*_test.rb` filenames. Use two-space Ruby indentation and the committed RuboCop configuration. CI covers Rails 7.1, 7.2, 8.0, and 8.1 on Ruby 3.2 and 3.3.

## Releases

Update `lib/eav_field/version.rb` and `CHANGELOG.md`, run the tests and lint, then build the gem. Publish the reviewed package to RubyGems and create a matching `v<VERSION>` Git tag and GitHub release. Release packages are generated in `pkg/` and excluded from Git.

## License and support

Released under the [MIT License](LICENSE). Report bugs and request features through [GitHub Issues](https://github.com/Mouados-byte/eav_field/issues). Published versions are available on [RubyGems](https://rubygems.org/gems/eav_field).
