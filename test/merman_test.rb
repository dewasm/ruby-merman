# frozen_string_literal: true

require "test_helper"

class MermanTest < Minitest::Test
  def test_version_constants
    assert_equal "0.1.0", Dewasm::Merman::VERSION
    assert_equal "0.8.0-alpha.5", Dewasm::Merman::MERMAN_VERSION
  end

  def test_render_svg_covers_the_common_diagram_types
    {
      flowchart: Diagrams::FLOWCHART,
      sequence: Diagrams::SEQUENCE,
      pie: Diagrams::PIE,
      class: Diagrams::CLASS,
      state: Diagrams::STATE,
      gantt: Diagrams::GANTT,
      mindmap: Diagrams::MINDMAP
    }.each do |name, text|
      svg = Dewasm::Merman.render_svg(text)

      assert_kind_of String, svg, name.to_s
      assert svg.start_with?("<svg"), "#{name} did not render an SVG element"
    end
  end

  def test_render_svg_readable_and_resvg_safe
    assert Dewasm::Merman.render_svg_readable(Diagrams::FLOWCHART).start_with?("<svg")
    assert Dewasm::Merman.render_svg_resvg_safe(Diagrams::FLOWCHART).start_with?("<svg")
  end

  def test_diagram_id_appears_in_the_svg
    svg = Dewasm::Merman.render_svg(Diagrams::FLOWCHART, diagram_id: "my-diagram")

    assert_includes svg, "my-diagram"
  end

  def test_site_config_changes_the_svg
    default = Dewasm::Merman.render_svg(Diagrams::FLOWCHART)
    themed = Dewasm::Merman.render_svg(Diagrams::FLOWCHART, site_config: { "theme" => "dark" })

    refute_equal default, themed
  end

  def test_render_ascii_flowchart
    text = Dewasm::Merman.render_ascii(Diagrams::FLOWCHART)

    refute_empty text
    assert_includes text, "Start"
    assert_includes text, "Done"
    assert_includes text, "─"
  end

  def test_render_ascii_sequence
    text = Dewasm::Merman.render_ascii(Diagrams::SEQUENCE)

    refute_empty text
    assert_includes text, "Alice"
    assert_includes text, "Bob"
  end

  def test_render_ascii_charset_ascii_avoids_box_drawing
    text = Dewasm::Merman.render_ascii(Diagrams::FLOWCHART, charset: :ascii)

    refute_includes text, "─"
    assert_includes text, "+"
  end

  def test_render_ascii_option_kwargs_reach_the_renderer
    narrow = Dewasm::Merman.render_ascii(Diagrams::SEQUENCE, sequence_participant_spacing: 2)
    wide = Dewasm::Merman.render_ascii(Diagrams::SEQUENCE, sequence_participant_spacing: 20)

    refute_equal narrow, wide
  end

  def test_render_ascii_rejects_an_unknown_option
    assert_raises(ArgumentError) do
      Dewasm::Merman.render_ascii(Diagrams::FLOWCHART, no_such_option: 1)
    end
  end

  def test_parse_metadata_returns_a_hash
    metadata = Dewasm::Merman.parse_metadata(Diagrams::PIE)

    assert_kind_of Hash, metadata
    assert_equal "pie", metadata["diagram_type"]
    assert_kind_of Hash, metadata["effective_config"]
  end

  def test_parse_metadata_reads_the_front_matter_title
    metadata = Dewasm::Merman.parse_metadata("---\ntitle: My Chart\n---\n#{Diagrams::PIE}")

    assert_equal "My Chart", metadata["title"]
  end

  # merman reports undetectable text as an error, not as `Ok(None)`, so there is
  # no input in this build for which the render functions return nil.
  def test_text_that_is_not_a_diagram_raises
    error = assert_raises(Dewasm::Merman::Error) { Dewasm::Merman.render_svg("not a diagram") }

    assert_includes error.message, "No diagram type detected"
  end

  def test_broken_diagram_raises
    error = assert_raises(Dewasm::Merman::Error) do
      Dewasm::Merman.render_svg("flowchart TD\n  ]]] ---")
    end

    assert_includes error.message, "Diagram parse error"
  end

  def test_ascii_rejects_an_unsupported_diagram_family
    error = assert_raises(Dewasm::Merman::Error) { Dewasm::Merman.render_ascii(Diagrams::PIE) }

    assert_includes error.message, "does not support diagram type `pie`"
  end

  def test_render_svg_railroad
    svg = Dewasm::Merman.render_svg(Diagrams::RAILROAD)

    assert svg.start_with?("<svg")
    assert_includes svg, 'aria-roledescription="railroad"'
    assert_includes svg, 'class="railroad-rule"'
    assert_includes svg, 'class="railroad-nonterminal"'
    assert_includes svg, "Expression grammar"
  end

  def test_render_svg_railroad_ebnf
    svg = Dewasm::Merman.render_svg(Diagrams::RAILROAD_EBNF)

    assert svg.start_with?("<svg")
    assert_includes svg, 'aria-roledescription="railroadEbnf"'
    assert_includes svg, 'class="railroad-terminal"'
  end

  def test_parse_metadata_reports_the_railroad_diagram_type
    metadata = Dewasm::Merman.parse_metadata(Diagrams::RAILROAD)

    assert_equal "railroad", metadata["diagram_type"]
  end

  def test_render_svg_is_deterministic
    [Diagrams::FLOWCHART, Diagrams::RAILROAD].each do |text|
      first = Dewasm::Merman.render_svg(text, deterministic_text_measurer: true,
                                              random: Random.new(42))
      second = Dewasm::Merman.render_svg(text, deterministic_text_measurer: true,
                                               random: Random.new(42))

      assert_equal first, second
    end
  end

  def test_gantt_ascii_with_a_fixed_today_is_deterministic
    today = Date.new(2024, 1, 15)
    first = Dewasm::Merman.render_ascii(Diagrams::GANTT, fixed_today: today)
    second = Dewasm::Merman.render_ascii(Diagrams::GANTT, fixed_today: today)

    assert_equal first, second
    assert_includes first, "2024-01-01"
  end

  # The source supplies the hash seed a render starts from, once per render.
  def test_the_random_source_is_consulted_once_per_render
    counter = Object.new
    def counter.calls = @calls ||= 0
    def counter.bytes(size)
      @calls = calls + 1
      "\0" * size
    end

    2.times { Dewasm::Merman.render_svg(Diagrams::FLOWCHART, random: counter) }

    assert_equal 2, counter.calls
  end
end
