# frozen_string_literal: true

require "test_helper"

# The snapshot restores the state merman builds on its first render into every
# fresh instance, so a restored render must produce what a plain render produces.
class SnapshotTest < Minitest::Test
  include WithoutSnapshot

  def setup
    skip "no snapshot built" unless File.exist?(Dewasm::Merman::Snapshot::PATH)
  end

  def teardown
    Dewasm::Merman::Snapshot.forget
  end

  def test_render_svg_matches_the_plain_path
    assert_equal without_snapshot { Dewasm::Merman.render_svg(Diagrams::FLOWCHART) },
                 Dewasm::Merman.render_svg(Diagrams::FLOWCHART)
  end

  def test_render_ascii_matches_the_plain_path
    assert_equal without_snapshot { Dewasm::Merman.render_ascii(Diagrams::SEQUENCE) },
                 Dewasm::Merman.render_ascii(Diagrams::SEQUENCE)
  end

  def test_render_svg_railroad_matches_the_plain_path
    assert_equal without_snapshot { Dewasm::Merman.render_svg(Diagrams::RAILROAD) },
                 Dewasm::Merman.render_svg(Diagrams::RAILROAD)
  end

  def test_parse_metadata_matches_the_plain_path
    assert_equal without_snapshot { Dewasm::Merman.parse_metadata(Diagrams::PIE) },
                 Dewasm::Merman.parse_metadata(Diagrams::PIE)
  end
end
