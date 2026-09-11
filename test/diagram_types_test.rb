# frozen_string_literal: true

require "test_helper"
require_relative "../tools/diagram_types"

class DiagramTypesTest < Minitest::Test
  # Regenerating the block verifies every cell against the module: the row list is the module's own export, each sample must be detected as its row's type and render to SVG, and the ASCII column is what the text formats accepted.
  def test_readme_diagram_type_table_matches_a_regenerated_one
    table = Dewasm::Merman::DiagramTypes.block
    readme = File.read(File.expand_path("../README.md", __dir__))
    expected = [
      Dewasm::Merman::DiagramTypes::BEGIN_MARKER,
      table,
      Dewasm::Merman::DiagramTypes::END_MARKER
    ].join("\n")

    assert_includes readme,
                    expected,
                    "the README.md diagram type table is stale; run `rake diagram_types`"
  end

  def test_samples_cover_the_module_rows
    Dewasm::Merman::DiagramTypes.check_samples_cover_rows
  end
end
