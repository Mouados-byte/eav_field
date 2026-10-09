# frozen_string_literal: true

require_relative "lib/eav_field/version"

Gem::Specification.new do |spec|
  spec.name = "eav_field"
  spec.version = EavField::VERSION
  spec.authors = [ "Mouad Imam" ]
  spec.license = "MIT"
  spec.homepage = "https://github.com/Mouados-byte/eav_field"
  spec.summary = "Typed entity-attribute-value fields for Active Record models."
  spec.description = "Add database-defined, validated, queryable fields to existing Rails models without altering their tables."
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*", "README.md", "CHANGELOG.md", "LICENSE"].select { |path| File.file?(path) }
  spec.require_paths = [ "lib" ]
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "#{spec.homepage}#readme"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/v#{EavField::VERSION}/CHANGELOG.md"

  spec.add_dependency "activerecord", ">= 7.1", "< 9.0"
  # Rails versions in the supported range use JSON APIs removed in JSON 3.
  spec.add_dependency "json", ">= 2.0", "< 3.0"
  spec.add_dependency "railties", ">= 7.1", "< 9.0"
end
