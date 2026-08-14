# frozen_string_literal: true

require "zlib"

module Dewasm
  module Merman
    # The module state captured after merman's once-per-instance initialization,
    # restored into every fresh instance so that no render pays that cost.
    #
    # The state is the linear memory plus the single mutable global `@g0`, the
    # shadow stack pointer. The file is a zlib stream of
    # `magic | version | memory length | global | memory bytes`.
    module Snapshot
      PATH = File.expand_path("snapshot.bin.gz", __dir__)
      PAGE_SIZE = 65_536
      MAGIC = "DWMS"
      VERSION = 1
      HEADER = "a4CQ<L<"
      HEADER_SIZE = 17
      private_constant :MAGIC, :VERSION, :HEADER, :HEADER_SIZE

      module_function

      def dump(image, global)
        [MAGIC, VERSION, image.bytesize, global].pack(HEADER) + image
      end

      # Writes the captured memory and global into a freshly instantiated module,
      # and reports whether there was a snapshot to write.
      def restore(instance)
        image, global = state
        return false unless image

        memory = instance.memory
        growth = image.bytesize / PAGE_SIZE - memory.size
        memory.grow(growth) if growth.positive?
        memory.buffer.set_string(image, 0, image.bytesize, 0)
        # The wasm module exports no global, so the generated class has no writer
        # for the shadow stack pointer.
        instance.instance_variable_set(:@g0, global)
        true
      end

      # Read once per process. A missing file leaves the plain path in place, so
      # that a checkout whose snapshot has not been built yet still renders.
      def state
        return @state if defined?(@state)

        @state = File.exist?(PATH) ? read : [nil, nil]
      end

      def read
        blob = Zlib::Inflate.inflate(File.binread(PATH))
        magic, version, length, global = blob.unpack(HEADER)
        raise Error, "#{PATH} is not a version #{VERSION} snapshot" unless
          magic == MAGIC && version == VERSION

        [blob.byteslice(HEADER_SIZE, length).freeze, global]
      end
      private_class_method :read

      # Test support: drops the memoized state so that the next restore reads the
      # file again.
      def forget
        remove_instance_variable(:@state) if defined?(@state)
      end
    end
  end
end
