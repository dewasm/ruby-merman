# frozen_string_literal: true

require_relative "lib/dewasm/merman/version"

Gem::Specification.new do |spec|
  spec.name = "dewasm-merman"
  spec.version = Dewasm::Merman::VERSION
  spec.authors = ["Hiroya Fujinami"]
  spec.email = ["make.just.on@gmail.com"]

  spec.summary = "Mermaid diagram rendering in pure Ruby, converted from merman by dewasm"
  spec.description = <<~TEXT
    The merman Mermaid renderer (Rust) compiled to wasm and converted to pure Ruby by dewasm.
    It renders Mermaid text to SVG or to terminal text without a browser, a native extension, or a wasm runtime.
  TEXT
  spec.homepage = "https://github.com/dewasm/ruby-merman"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files =
    Dir["lib/**/*.rb"] + Dir["lib/**/*.bin.gz"] +
      %w[LICENSE LICENSE-MERMAN THIRD_PARTY_NOTICES-MERMAN.md README.md]
  spec.require_paths = ["lib"]
end
