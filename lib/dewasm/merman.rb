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

    SVG_ENUM_OPTIONS = %i[pipeline].freeze
    SVG_OPTIONS = (SVG_ENUM_OPTIONS + %i[svg_id viewbox_padding]).freeze

    ASCII_ENUM_OPTIONS = %i[
      charset
      width_profile
      layout_profile
      direction
      color
      color_theme
      overflow
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
      max_width
      trim_trailing_spaces
    ].freeze
    ASCII_OPTIONS = (ASCII_ENUM_OPTIONS + ASCII_PLAIN_OPTIONS).freeze

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

    # Renders the diagram text, or returns nil when the text is not a recognized diagram.
    # The keywords follow merman-cli's render command: format takes the compiled --format values (:svg renders SVG and takes the SvgRequest options; :ascii and :unicode render terminal text starting from that charset), suppress_errors emits an error diagram instead of failing on parse errors, and resource_profile with resource_limits resolve the operation's resource policies from one profile and per-limit overrides keyed by merman's stable limit ids.
    def render(
      text,
      format: :svg,
      site_config: nil,
      suppress_errors: nil,
      resource_profile: nil,
      resource_limits: nil,
      fixed_today: nil,
      fixed_local_offset_minutes: nil,
      random: Random,
      **format_options
    )
      options = {
        "site_config" => site_config,
        "suppress_errors" => suppress_errors,
        "resource_profile" => resource_profile&.to_s,
        "resource_limits" => resource_limits&.to_h { |key, value| [key.to_s.tr("_", "-"), value] },
        "fixed_today" => fixed_today&.strftime("%Y-%m-%d"),
        "fixed_local_offset_minutes" => fixed_local_offset_minutes,
        "format" => format_json(format, format_options)
      }
      call("merman_render", text, options, random)
    end

    # Returns the diagram type, front-matter config, effective config, and title.
    def parse_metadata(text, site_config: nil, random: Random)
      json = call("merman_parse_metadata", text, { "site_config" => site_config }, random)
      json && JSON.parse(json)
    end

    def format_json(format, format_options)
      case format
      when :svg
        unknown = format_options.keys - SVG_OPTIONS
        raise ArgumentError, "unknown svg options: #{unknown.join(", ")}" unless unknown.empty?

        { "svg" => option_json(format_options, SVG_ENUM_OPTIONS) }
      when :ascii, :unicode
        unknown = format_options.keys - ASCII_OPTIONS
        raise ArgumentError, "unknown ascii options: #{unknown.join(", ")}" unless unknown.empty?

        { format.to_s => option_json(format_options, ASCII_ENUM_OPTIONS) }
      else
        raise ArgumentError, "unknown format #{format.inspect}"
      end
    end
    private_class_method :format_json

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
