# frozen_string_literal: true

require "json"

require_relative "merman/version"
require_relative "merman/wasm_module"
require_relative "merman/snapshot"

module Dewasm
  # Mermaid diagram rendering through the merman renderer, compiled to wasm and
  # converted to pure Ruby by dewasm.
  module Merman
    # Raised when merman reports an error for the given input or options.
    class Error < StandardError; end

    STATUS_OK = 0
    STATUS_NONE = 1
    STATUS_ERROR = 2
    private_constant :STATUS_OK, :STATUS_NONE, :STATUS_ERROR

    ASCII_ENUM_OPTIONS = %i[charset default_direction color_mode color_theme].freeze
    ASCII_PLAIN_OPTIONS = %i[
      box_border_padding
      graph_padding_x
      graph_padding_y
      sequence_participant_spacing
      sequence_message_spacing
      sequence_self_message_width
      sequence_mirror_actors
      xychart_vertical_plot_height
      xychart_category_band_width
      xychart_horizontal_plot_width
      max_grid_cells
      relation_summary_diagnostics
    ].freeze
    ASCII_OPTIONS = (ASCII_ENUM_OPTIONS + ASCII_PLAIN_OPTIONS).freeze

    # The generated module carries no WASI implementation, so this resolves every
    # WASI import the module declares. A restored instance has merman's
    # initialization behind it and asks the host for nothing, so a call here means
    # an assumption behind the shipped snapshot no longer holds.
    module Wasi
      def self.import(name)
        lambda do |*|
          raise Error, "wasi import #{name} was called at render time; " \
                       "this is a bug, please report it"
        end
      end
    end

    IMPORTS = { "wasi_snapshot_preview1" => Wasi }.freeze

    module_function

    # Renders the Mermaid parity SVG, or nil when the text is not a recognized diagram.
    def render_svg(text, site_config: nil, diagram_id: nil, deterministic_text_measurer: false,
                   random: Random)
      call("merman_render_svg", text,
           svg_options(site_config, diagram_id, deterministic_text_measurer), random)
    end

    # Renders SVG with readable `<text>` fallbacks for `<foreignObject>` labels.
    def render_svg_readable(text, site_config: nil, diagram_id: nil,
                            deterministic_text_measurer: false, random: Random)
      call("merman_render_svg_readable", text,
           svg_options(site_config, diagram_id, deterministic_text_measurer), random)
    end

    # Renders SVG restricted to what usvg, resvg, and raster converters accept.
    def render_svg_resvg_safe(text, site_config: nil, diagram_id: nil,
                              deterministic_text_measurer: false, random: Random)
      call("merman_render_svg_resvg_safe", text,
           svg_options(site_config, diagram_id, deterministic_text_measurer), random)
    end

    # Renders terminal text, or nil when the text is not a recognized diagram.
    def render_ascii(text, charset: :unicode, strict_parsing: nil, fixed_today: nil,
                     fixed_local_offset_minutes: nil, site_config: nil, random: Random,
                     **ascii_options)
      unknown = ascii_options.keys - ASCII_OPTIONS
      raise ArgumentError, "unknown ascii options: #{unknown.join(", ")}" unless unknown.empty?

      options = {
        "site_config" => site_config,
        "strict_parsing" => strict_parsing,
        "fixed_today" => date_string(fixed_today),
        "fixed_local_offset_minutes" => fixed_local_offset_minutes,
        "ascii" => ascii_option_json(ascii_options.merge(charset: charset))
      }
      call("merman_render_ascii", text, options, random)
    end

    # Returns the diagram type, front-matter config, effective config, and title,
    # or nil when the text is not a recognized diagram.
    def parse_metadata(text, site_config: nil, random: Random)
      json = call("merman_parse_metadata", text, { "site_config" => site_config }, random)
      json && JSON.parse(json)
    end

    def svg_options(site_config, diagram_id, deterministic_text_measurer)
      {
        "site_config" => site_config,
        "diagram_id" => diagram_id,
        "deterministic_text_measurer" => deterministic_text_measurer
      }
    end
    private_class_method :svg_options

    def ascii_option_json(options)
      options.to_h do |key, value|
        [key.to_s, ASCII_ENUM_OPTIONS.include?(key) ? value.to_s : value]
      end
    end
    private_class_method :ascii_option_json

    def date_string(date)
      date&.strftime("%Y-%m-%d")
    end
    private_class_method :date_string

    def call(entry_point, text, options, random)
      run(restored_instance(random), entry_point, text, options)
    end
    private_class_method :call

    # A fresh instance with the shipped snapshot restored into it and a hash seed
    # drawn from `random` written over the seed the snapshot recorded.
    def restored_instance(random)
      instance = WasmModule.new(IMPORTS)
      Snapshot.restore(instance, random)
      instance
    end
    private_class_method :restored_instance

    def run(instance, entry_point, text, options)
      text_ptr, text_len = write(instance, text.to_s.encode(Encoding::UTF_8))
      options_ptr, options_len = write(instance, JSON.generate(options.compact))
      status = instance.invoke(entry_point, text_ptr, text_len, options_ptr, options_len)
      payload = read_result(instance)
      case status
      when STATUS_OK then payload
      when STATUS_NONE then nil
      else raise Error, payload
      end
    end
    private_class_method :run

    def write(instance, string)
      bytes = string.b
      return [0, 0] if bytes.empty?

      ptr = instance.invoke("merman_alloc", bytes.bytesize)
      instance.memory.init(ptr, bytes, 0, bytes.bytesize)
      [ptr, bytes.bytesize]
    end
    private_class_method :write

    def read_result(instance)
      length = instance.invoke("merman_result_len")
      return +"" if length.zero?

      instance.memory.buffer
              .get_string(instance.invoke("merman_result_ptr"), length)
              .force_encoding(Encoding::UTF_8)
    end
    private_class_method :read_result
  end
end
