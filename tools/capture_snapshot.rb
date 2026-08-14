# frozen_string_literal: true

# Build step: writes the state merman's once-per-instance initialization leaves behind as lib/dewasm/merman/snapshot.bin.gz, so that the library restores it instead of paying it on each render.

require "zlib"

require_relative "snapshot_util"

Snapshot = Dewasm::Merman::Snapshot
SnapshotUtil = Dewasm::Merman::SnapshotUtil

# Every render overwrites the seed in place, which only works if the cell the initialization left it in is identified beyond doubt: a snapshot whose renders would share one seed must not ship.
def seed_offset(image)
  offsets = []
  offset = 0
  while (found = image.index(SnapshotUtil::SEED, offset))
    offsets << found
    offset = found + 1
  end
  return offsets.first if offsets.size == 1

  raise "the capture seed appears #{offsets.size} times in the initialized memory, " \
          "expected exactly once: merman's hash seed cell can no longer be located"
end

instance = SnapshotUtil.instance
memory = instance.memory
image = memory.buffer.get_string(0, memory.size * Snapshot::PAGE_SIZE)
offset = seed_offset(image)
blob = Snapshot.dump(image, instance.instance_variable_get(:@g0), offset)

File.binwrite(Snapshot::PATH, Zlib::Deflate.deflate(blob, Zlib::BEST_COMPRESSION))
puts format(
       "wrote %s: %d pages, seed at %#x, %.1f MB compressed",
       Snapshot::PATH,
       memory.size,
       offset,
       File.size(Snapshot::PATH) / 1_000_000.0
     )
