# frozen_string_literal: true

require "bundler/setup"
require "fileutils"
require "rake/testtask"
require "rubygems/package"

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

desc "Build the gem into pkg/"
task :build do
  specification = Gem::Specification.load("eav_field.gemspec")
  FileUtils.mkdir_p("pkg")
  Gem::Package.build(specification, false, false, File.join("pkg", specification.file_name))
end

desc "Check Ruby formatting and lint"
task :lint do
  sh "bundle exec rubocop"
end

task default: [ :test, :lint ]
