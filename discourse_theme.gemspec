# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "discourse_theme/version"

Gem::Specification.new do |spec|
  spec.name = "discourse_theme"
  spec.version = DiscourseTheme::VERSION
  spec.authors = ["Sam Saffron"]
  spec.email = ["sam.saffron@gmail.com"]

  spec.summary = "CLI helper for creating Discourse themes"
  spec.description = "CLI helper for creating Discourse themes"
  spec.homepage = "https://github.com/discourse/discourse_theme"
  spec.license = "MIT"

  spec.files = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }

  spec.bindir = "bin"
  spec.executables = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.0.0"

  spec.add_runtime_dependency "minitar", "~> 0.6"
  spec.add_runtime_dependency "listen", "~> 3.1"
  spec.add_runtime_dependency "multipart-post", "~> 2.0"
  spec.add_runtime_dependency "tty-prompt", "~> 0.18"
  spec.add_runtime_dependency "rubyzip", "~> 1.2"
  spec.add_runtime_dependency "selenium-webdriver", "> 4.11"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-minitest"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "rubocop-discourse", "~> 3.6.0"
  spec.add_development_dependency "m"
  spec.add_development_dependency "syntax_tree"
  spec.add_development_dependency "mocha"
end
