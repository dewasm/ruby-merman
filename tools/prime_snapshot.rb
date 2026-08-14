# frozen_string_literal: true

# Build step: carry a fresh instance through merman's once-per-instance
# initialization, locate the hash seed it drew there, and write the resulting
# state as lib/dewasm/merman/snapshot.bin.gz. The library restores that state into
# every fresh instance, so the initialization is paid here instead of on each
# render.

require "zlib"

require_relative "priming"

Snapshot = Dewasm::Merman::Snapshot
Priming = Dewasm::Merman::Priming

# Every render overwrites the seed in place, which only works if the cell the
# initialization left it in is identified beyond doubt. A toolchain that puts the
# bytes somewhere else, or in more than one place, stops the build here rather
# than shipping a snapshot whose renders would share one seed.
def seed_offset(image)
  offsets = []
  offset = 0
  while (found = image.index(Priming::SEED, offset))
    offsets << found
    offset = found + 1
  end
  return offsets.first if offsets.size == 1

  raise "the priming seed appears #{offsets.size} times in the initialized memory, " \
        "expected exactly once: merman's hash seed cell can no longer be located"
end

instance = Priming.instance
memory = instance.memory
image = memory.buffer.get_string(0, memory.size * Snapshot::PAGE_SIZE)
offset = seed_offset(image)
blob = Snapshot.dump(image, instance.instance_variable_get(:@g0), offset)

File.binwrite(Snapshot::PATH, Zlib::Deflate.deflate(blob, Zlib::BEST_COMPRESSION))
puts format("wrote %s: %d pages, seed at %#x, %.1f MB compressed",
            Snapshot::PATH, memory.size, offset, File.size(Snapshot::PATH) / 1_000_000.0)
