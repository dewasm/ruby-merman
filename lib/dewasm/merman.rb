# frozen_string_literal: true

require "json"

require_relative "merman/version"
require_relative "merman/wasm_module"
require_relative "merman/snapshot"

module Dewasm
  # Mermaid diagram rendering through the merman renderer, compiled to wasm and converted to pure Ruby by dewasm.
  module Merman
    # Raised when merman reports an error for the given input or options.
    class Error < StandardError
    end

    STATUS_OK = 0
    STATUS_NONE = 1
    STATUS_ERROR = 2
    private_constant :STATUS_OK, :STATUS_NONE, :STATUS_ERROR

    ASCII_ENUM_OPTIONS = %i[
      charset
      terminal_width_profile
      layout_profile
      default_direction
      color_mode
      color_theme
    ].freeze
    ASCII_PLAIN_OPTIONS = %i[
      box_border_padding
      graph_padding_x
      graph_padding_y
      flowchart_node_label_wrap_width
      sequence_participant_spacing
      sequence_message_spacing
      sequence_self_message_width
      sequence_mirror_actors
      xychart_vertical_plot_height
      xychart_category_band_width
      xychart_horizontal_plot_width
      relation_summary_diagnostics
    ].freeze
    ASCII_OPTIONS = (ASCII_ENUM_OPTIONS + ASCII_PLAIN_OPTIONS).freeze

    RESOURCE_OPTIONS = %i[
      profile
      max_grid_cells
      max_layout_work_units
      max_document_cells
      max_output_bytes
      max_grapheme_bytes
      max_nesting_depth
    ].freeze
    VIEWPORT_OPTIONS = %i[max_width overflow trim].freeze
    SYMBOL_VALUED_OPTIONS = %i[profile overflow trim].freeze
    private_constant :RESOURCE_OPTIONS, :VIEWPORT_OPTIONS, :SYMBOL_VALUED_OPTIONS

    # The generated module carries no WASI implementation, so this resolves every WASI import the module declares.
    # A restored instance asks the host for nothing, so a call here means an assumption behind the shipped snapshot no longer holds.
    module Wasi
      def self.import(name)
        lambda do |*|
          raise Error,
                "wasi import #{name} was called at render time; " \
                  "this is a bug, please report it"
        end
      end
    end

    IMPORTS = { "wasi_snapshot_preview1" => Wasi }.freeze

    module_function

    # Renders SVG, or nil when the text is not a recognized diagram.
    # The pipeline is merman's SVG postprocess preset (:parity, :readable, or :resvg_safe); nil keeps merman's default of applying none.
    def render_svg(
      text,
      pipeline: nil,
      diagram_id: nil,
      viewbox_padding: nil,
      site_config: nil,
      parse_options: nil,
      fixed_today: nil,
      fixed_local_offset_minutes: nil,
      random: Random
    )
      options =
        operation_options(site_config, parse_options, fixed_today, fixed_local_offset_minutes)
      options["svg"] = {
        "pipeline" => pipeline&.to_s,
        "diagram_id" => diagram_id,
        "viewbox_padding" => viewbox_padding
      }.compact
      call("merman_render_svg", text, options, random)
    end

    # Renders terminal text, or nil when the text is not a recognized diagram.
    # The keyword groups mirror merman's AsciiRequest: AsciiRenderOptions fields directly, the AsciiResourcePolicy as resources:, and the AsciiViewportPolicy as viewport:.
    def render_ascii(
      text,
      resources: nil,
      viewport: nil,
      site_config: nil,
      parse_options: nil,
      fixed_today: nil,
      fixed_local_offset_minutes: nil,
      random: Random,
      **ascii_options
    )
      unknown = ascii_options.keys - ASCII_OPTIONS
      raise ArgumentError, "unknown ascii options: #{unknown.join(", ")}" unless unknown.empty?

      options =
        operation_options(site_config, parse_options, fixed_today, fixed_local_offset_minutes)
      options["ascii"] = {
        "options" => option_json(ascii_options, ASCII_ENUM_OPTIONS),
        "resources" => policy_json(resources, RESOURCE_OPTIONS, "resources"),
        "viewport" => policy_json(viewport, VIEWPORT_OPTIONS, "viewport")
      }.compact
      call("merman_render_ascii", text, options, random)
    end

    # Returns the diagram type, front-matter config, effective config, and title.
    def parse_metadata(text, site_config: nil, random: Random)
      json = call("merman_parse_metadata", text, { "site_config" => site_config }, random)
      json && JSON.parse(json)
    end

    def operation_options(site_config, parse_options, fixed_today, fixed_local_offset_minutes)
      {
        "site_config" => site_config,
        "parse_options" => parse_options&.to_s,
        "fixed_today" => fixed_today&.strftime("%Y-%m-%d"),
        "fixed_local_offset_minutes" => fixed_local_offset_minutes
      }
    end
    private_class_method :operation_options

    def policy_json(options, known, group)
      return nil if options.nil?

      unknown = options.keys - known
      raise ArgumentError, "unknown #{group} options: #{unknown.join(", ")}" unless unknown.empty?

      option_json(options, SYMBOL_VALUED_OPTIONS)
    end
    private_class_method :policy_json

    def option_json(options, enum_keys)
      options.to_h { |key, value| [key.to_s, enum_keys.include?(key) ? value.to_s : value] }
    end
    private_class_method :option_json

    def call(entry_point, text, options, random)
      run(restored_instance(random), entry_point, text, options)
    end
    private_class_method :call

    # A hash seed drawn from `random` is written over the seed the snapshot recorded.
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
      when STATUS_OK
        payload
      when STATUS_NONE
        nil
      else
        raise Error, payload
      end
    end
    private_class_method :run

    def write(instance, string)
      bytes = string.b
      return 0, 0 if bytes.empty?

      ptr = instance.invoke("merman_alloc", bytes.bytesize)
      instance.memory.init(ptr, bytes, 0, bytes.bytesize)
      [ptr, bytes.bytesize]
    end
    private_class_method :write

    def read_result(instance)
      length = instance.invoke("merman_result_len")
      return +"" if length.zero?

      instance
        .memory
        .buffer
        .get_string(instance.invoke("merman_result_ptr"), length)
        .force_encoding(Encoding::UTF_8)
    end
    private_class_method :read_result
  end
end
