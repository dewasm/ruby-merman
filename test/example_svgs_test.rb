# frozen_string_literal: true

require "test_helper"
require_relative "../tools/example_svgs"

class ExampleSvgsTest < Minitest::Test
  def test_committed_example_svgs_match_regenerated_ones
    Dewasm::Merman::ExampleSvgs::EXAMPLES.each do |path, text|
      committed = File.read(File.join(Dewasm::Merman::ExampleSvgs::ROOT, path))

      assert_equal Dewasm::Merman::ExampleSvgs.render(text),
                   committed,
                   "#{path} is stale; run `rake example_svgs`"
    end
  end

  def test_readme_shows_each_example_svg
    readme = File.read(File.join(Dewasm::Merman::ExampleSvgs::ROOT, "README.md"))

    Dewasm::Merman::ExampleSvgs::EXAMPLES.each_key do |path|
      assert_includes readme, "(#{path})", "README.md does not display #{path}"
    end
  end
end
