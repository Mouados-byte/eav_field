# EavField

EavField adds an entity-attribute-value (EAV) system to existing Active Record models. Your model is the entity; database records define its dynamic attributes; separate records store their typed values. Adding a field does not require changing the owner's table.

Requires Ruby 3.2+ and Active Record/Railties 7.1–8.x. The gem constrains JSON to 2.x for compatibility with these Rails versions. The development suite uses SQLite and Minitest.

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

The generator creates `eav_field_definitions` and `eav_field_values`. Owner IDs use `bigint` by default. For PostgreSQL UUID owners, generate with `--entity-id-type=uuid`; for string IDs, use `--entity-id-type=string`. All participating models must have IDs compatible with the selected column type.

Opt in on any existing model:

```ruby
class Product < ApplicationRecord
  has_eav_fields
end
```

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

Definition names, types, and entity scopes are immutable after creation. Defaults and `required` flags can be updated through `Product.eav_field_definitions`. Adding a required definition affects validation of existing owners on their next save.

## Query fields

```ruby
Product.with_eav_field(:color, "blue")
Product.where(name: "Chair").with_eav_field(:weight, "1.25")
Product.with_eav_field(:color, "blue").with_eav_field(:available, false)
```

These return chainable Active Record relations with typed equality comparisons. Matching defaults include owners without a stored override; explicit null overrides remain distinct from non-null defaults. Queries use persisted values. JSON equality raises `EavField::UnsupportedQuery` because JSON comparisons differ between database adapters.

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
bundle exec rake build      # Build pkg/eav_field-0.1.0.gem.
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
