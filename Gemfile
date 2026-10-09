# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "~> 8.1.0")
gem "activerecord", rails_version
gem "railties", rails_version

gem "minitest", "~> 5.0"
gem "rake", "~> 13.0"
gem "rubocop", "~> 1.0"
gem "rubocop-rails-omakase", "~> 1.1"
gem "sqlite3", rails_version.include?("7.1") ? "~> 1.7" : "~> 2.0"
