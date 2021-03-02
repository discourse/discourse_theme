# frozen_string_literal: true

lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "discourse_theme/version"

Gem::Specification.new do |spec|
  spec.name          = "discourse_theme"
  spec.version       = DiscourseTheme::VERSION
  spec.authors       = ["Sam Saffron"]
  spec.email         = ["sam.saffron@gmail.com"]

  spec.summary       = %q{CLI helper for creating Discourse themes}
  spec.description   = %q{CLI helper for creating Discourse themes}
  spec.homepage      = "https://github.com/discourse/discourse_theme"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end

  spec.bindir        = "bin"
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.6.0'

  spec.add_runtime_dependency "minitar", "~> 0.6"
  spec.add_runtime_dependency "listen", "~> 3.1"
  spec.add_runtime_dependency "multipart-post", "~> 2.0"
  spec.add_runtime_dependency "tty-prompt", "~> 0.18"
  spec.add_runtime_dependency "rubyzip", "~> 1.2"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "guard", "~> 2.14"
  spec.add_development_dependency "guard-minitest", "~> 2.4"
  spec.add_development_dependency "webmock", "~> 3.5"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "rubocop-discourse"
end
