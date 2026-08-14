# frozen_string_literal: true

# Build step: instantiate the generated module, render one small flowchart so that
# merman's once-per-instance initialization runs, and write the resulting state as
# lib/dewasm/merman/snapshot.bin.gz. The library restores that state into every
# fresh instance, so the initialization is paid here instead of on each render.

require "zlib"

require_relative "../lib/dewasm/merman"

FLOWCHART = "flowchart TD\n  A[Start] --> B[Done]\n"

def write(instance, string)
  bytes = string.b
  pointer = instance.invoke("merman_alloc", bytes.bytesize)
  instance.memory.init(pointer, bytes, 0, bytes.bytesize)
  [pointer, bytes.bytesize]
end

instance = Dewasm::Merman::WasmModule.new
text_pointer, text_length = write(instance, FLOWCHART)
options_pointer, options_length = write(instance, "{}")
status = instance.invoke("merman_render_svg", text_pointer, text_length,
                         options_pointer, options_length)
raise "priming render failed with status #{status}" unless status.zero?

memory = instance.memory
image = memory.buffer.get_string(0, memory.size * Dewasm::Merman::Snapshot::PAGE_SIZE)
global = instance.instance_variable_get(:@g0)
blob = Dewasm::Merman::Snapshot.dump(image, global)

path = Dewasm::Merman::Snapshot::PATH
File.binwrite(path, Zlib::Deflate.deflate(blob, Zlib::BEST_COMPRESSION))
puts format("wrote %s: %d pages, %.1f MB compressed",
            path, memory.size, File.size(path) / 1_000_000.0)
