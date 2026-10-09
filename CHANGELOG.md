# Changelog

## 0.3.0 — Unreleased

- Add directed, named links between persisted field definitions in the same model scope, including STI support.
- Add model helpers, outgoing and incoming relationship associations, chainable traversal, and link removal.
- Reject duplicate links and self-links with validations and database constraints; cascade links when either definition is deleted.
- Add an additive `eav_field:relationships` migration for existing installations and include relationships in fresh installs.
- Preserve definitions, validation rules, and stored values during relationship upgrades and rollbacks.

## 0.2.0 — 2026-10-09

- Add persisted minimum/maximum, length, and allowed-choice validation rules with owner errors and validated defaults.
- Add application-defined `validate_eav_field` blocks with inheritance and support for defaults.
- Add typed comparisons, ranges, inclusion, inequality, and missing-row filters.
- Add EAV sorting with effective defaults and explicit null placement.
- Add collection preloading, owner definition snapshots, and execution-local definition cache blocks.
- Invalidate local definition caches on changes, commits, and rollbacks; provide explicit refresh for external or bulk changes.
- Add an upgrade generator for existing 0.1.0 installations and preserve stored values during SQLite rollback.

## 0.1.0 — 2026-10-09

- Add `has_eav_fields` for existing Active Record models.
- Persist model-scoped definitions and polymorphic typed values.
- Support string, text, integer, decimal, boolean, date, datetime, and JSON fields.
- Add defaults, required-field validation, transactional autosave, and equality queries.
- Provide a Rails installation generator with bigint, UUID, and string owner ID options.
- Add Minitest integration coverage, RuboCop configuration, and a Rails CI matrix.
- Release under the MIT License.
