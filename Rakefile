# frozen_string_literal: true

require "rake/testtask"

WASM_SOURCE = "wasm/target/wasm32-wasip1/release/merman_wasm.wasm"
WASM = "wasm/merman.wasm"
GENERATED = "lib/dewasm/merman/wasm_module.rb"
SNAPSHOT = "lib/dewasm/merman/snapshot.bin.gz"
DEWASM = ENV.fetch("DEWASM_BIN", File.expand_path("../dewasm/target/release/dewasm", __dir__))

file WASM_SOURCE => FileList["wasm/src/*.rs", "wasm/Cargo.toml", "wasm/Cargo.lock"] do
  sh "cargo build --release --target wasm32-wasip1 --manifest-path wasm/Cargo.toml"
end

file WASM => WASM_SOURCE do
  sh "wasm-opt -Oz --enable-bulk-memory --enable-sign-ext " \
     "--enable-nontrapping-float-to-int #{WASM_SOURCE} -o #{WASM}"
end

file GENERATED => WASM do
  sh "#{DEWASM} #{WASM} --target ruby --mode library --no-default-wasi " \
     "--module-name Dewasm::Merman::WasmModule -o #{GENERATED}"
end

file SNAPSHOT => [GENERATED, "lib/dewasm/merman/snapshot.rb", "tools/snapshot_util.rb",
                  "tools/capture_snapshot.rb"] do
  sh RbConfig.ruby, "tools/capture_snapshot.rb"
end

Dir["tasks/*.rake"].sort.each { |path| load path }

namespace :wasm do
  desc "Build wasm/merman.wasm from the Rust wrapper crate"
  task build: WASM
end

desc "Convert wasm/merman.wasm to Ruby with dewasm and capture the state snapshot"
task generate: [GENERATED, SNAPSHOT]

Rake::TestTask.new(test: :generate) do |t|
  t.libs = %w[lib test]
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Build the gem"
task build: :generate do
  sh "gem build dewasm-merman.gemspec"
end

desc "Remove build products"
task :clean do
  rm_f [WASM, GENERATED, SNAPSHOT]
  rm_rf "wasm/target"
end

task default: :test
