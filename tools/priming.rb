# frozen_string_literal: true

require_relative "../lib/dewasm/merman"

module Dewasm
  module Merman
    # A fresh module instance carried through merman's once-per-instance initialization, which is what the shipped snapshot captures.
    #
    # The snapshot build step and the tests are the only users, so this file stays outside the gem: what ships neither initializes nor carries a WASI implementation.
    module Priming
      # The bytes handed to merman's single `random_get` call while priming; the snapshot records where they land so that every render overwrites them with a hash seed of its own, so this value seeds nothing that ships.
      SEED = "\x8f\x1d\xc2\x74\x53\xab\x09\xe6\x3f\x71\xd8\x4c\x25\xba\x60\x97".b.freeze

      # Small enough to initialize quickly, and a flowchart so that the layout and text measurement tables are built.
      FLOWCHART = "flowchart TD\n  A[Start] --> B[Done]\n"

      # What merman asks of the host while initializing; every other WASI import raises, so priming cannot quietly depend on one.
      class Wasi
        ERRNO_SUCCESS = 0

        IMPLEMENTED = %w[random_get environ_get environ_sizes_get clock_time_get fd_write].freeze

        def initialize(seed)
          @seed = seed
        end

        def import(name)
          return method(name) if IMPLEMENTED.include?(name)

          ->(*) { raise Error, "wasi import #{name} was called while priming" }
        end

        def attach(instance)
          @memory = instance.memory
        end

        def random_get(pointer, length)
          bytes = (@seed * (length / @seed.bytesize + 1)).byteslice(0, length)
          @memory.init(pointer, bytes, 0, length)
          ERRNO_SUCCESS
        end

        def environ_sizes_get(count_pointer, size_pointer)
          write_u32(count_pointer, 0)
          write_u32(size_pointer, 0)
          ERRNO_SUCCESS
        end

        def environ_get(_environ_pointer, _buffer_pointer)
          ERRNO_SUCCESS
        end

        def clock_time_get(id, _precision, out_pointer)
          clock = id.zero? ? Process::CLOCK_REALTIME : Process::CLOCK_MONOTONIC
          @memory.buffer.set_value(:u64, out_pointer, Process.clock_gettime(clock, :nanosecond))
          ERRNO_SUCCESS
        end

        def fd_write(_fd, iovs_pointer, iovs_length, written_pointer)
          written = 0
          iovs_length.times do |i|
            pointer = read_u32(iovs_pointer + i * 8)
            length = read_u32(iovs_pointer + i * 8 + 4)
            $stderr.write(@memory.buffer.get_string(pointer, length))
            written += length
          end
          write_u32(written_pointer, written)
          ERRNO_SUCCESS
        end

        private

        def read_u32(address)
          @memory.buffer.get_value(:u32, address)
        end

        def write_u32(address, value)
          @memory.buffer.set_value(:u32, address, value)
        end
      end

      module_function

      # An instance whose initialization has run, equivalent to what restoring the snapshot produces.
      def instance
        instance = WasmModule.new({ "wasi_snapshot_preview1" => Wasi.new(SEED) })
        Merman.send(:run, instance, "merman_render_svg", FLOWCHART, {})
        instance
      end

      # The public functions with their default options, each on its own freshly initialized instance.
      # They reach into the private call path on purpose: taking the same path with a different instance is what makes the comparison against a restored render meaningful.
      def render_svg(text)
        call("merman_render_svg", text, Merman.send(:svg_options, nil, nil, false))
      end

      def render_ascii(text)
        call("merman_render_ascii", text,
             { "ascii" => Merman.send(:ascii_option_json, charset: :unicode) })
      end

      def parse_metadata(text)
        json = call("merman_parse_metadata", text, {})
        json && JSON.parse(json)
      end

      def call(entry_point, text, options)
        Merman.send(:run, instance, entry_point, text, options)
      end
    end
  end
end
