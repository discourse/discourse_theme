# frozen_string_literal: true
directories %w(app lib test) \
  .select { |d| Dir.exist?(d) ? d : UI.warning("Directory #{d} does not exist") }

guard :minitest do
  # with Minitest::Unit
  watch(%r{^test/(.*)\/?test_(.*)\.rb$})
  watch(%r{^lib/(.*/)?([^/]+)\.rb$})     { |m| "test/test_#{m[2]}.rb" }
  watch(%r{^test/test_helper\.rb$})      { 'test' }
end
