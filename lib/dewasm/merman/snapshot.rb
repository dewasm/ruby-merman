# frozen_string_literal: true

require "zlib"

module Dewasm
  module Merman
    # The module state captured after merman's once-per-instance initialization, restored into every fresh instance so that no render pays that cost.
    #
    # The state is the linear memory, the shadow stack pointer held in the single mutable global `@g0`, and the offset of the hash seed merman drew while initializing.
    # A restored instance shares the initialized tables but not the hash seed, which restoring overwrites at the recorded offset.
    # The file is a zlib stream of `magic | version | seed offset | global | memory length | memory bytes`.
    module Snapshot
      PATH = File.expand_path("snapshot.bin.gz", __dir__)
      PAGE_SIZE = 65_536
      SEED_SIZE = 16
      MAGIC = "DWMS"
      VERSION = 2
      HEADER = "a4CL<L<Q<"
      HEADER_SIZE = 21
      private_constant :MAGIC, :HEADER, :HEADER_SIZE

      module_function

      def dump(image, global, seed_offset)
        [MAGIC, VERSION, seed_offset, global, image.bytesize].pack(HEADER) + image
      end

      def restore(instance, random)
        image, global, seed_offset = state

        memory = instance.memory
        growth = image.bytesize / PAGE_SIZE - memory.size
        memory.grow(growth) if growth.positive?
        memory.buffer.set_string(image, 0, image.bytesize, 0)
        # The wasm module exports no global, so the generated class has no writer for the shadow stack pointer `@g0`.
        instance.instance_variable_set(:@g0, global)
        memory.init(seed_offset, random.bytes(SEED_SIZE).b, 0, SEED_SIZE)
      end

      def seed_offset
        state[2]
      end

      def state
        @state ||= read
      end

      def read
        raise Error, "#{PATH} is missing; run `rake generate` to build it" unless File.exist?(PATH)

        blob = Zlib::Inflate.inflate(File.binread(PATH))
        magic, version, seed_offset, global, length = blob.unpack(HEADER)
        unless magic == MAGIC && version == VERSION
          raise Error,
                "#{PATH} is not a version #{VERSION} snapshot; run `rake generate` to " \
                  "rebuild it"
        end

        [blob.byteslice(HEADER_SIZE, length).freeze, global, seed_offset]
      end
      private_class_method :read

      # Test support: the next restore reads the file again.
      def forget
        remove_instance_variable(:@state) if defined?(@state)
      end
    end
  end
end
