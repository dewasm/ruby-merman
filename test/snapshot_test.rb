# frozen_string_literal: true

require "zlib"

require "test_helper"
require_relative "../tools/priming"

# The snapshot restores the state merman builds while initializing into every
# fresh instance, so a restored render must produce what a freshly initialized
# instance produces.
class SnapshotTest < Minitest::Test
  include WithSnapshotFile

  Priming = Dewasm::Merman::Priming
  Snapshot = Dewasm::Merman::Snapshot

  def test_render_svg_matches_a_freshly_initialized_instance
    assert_equal Priming.render_svg(Diagrams::FLOWCHART),
                 Dewasm::Merman.render_svg(Diagrams::FLOWCHART)
  end

  def test_render_ascii_matches_a_freshly_initialized_instance
    assert_equal Priming.render_ascii(Diagrams::SEQUENCE),
                 Dewasm::Merman.render_ascii(Diagrams::SEQUENCE)
  end

  def test_render_svg_railroad_matches_a_freshly_initialized_instance
    assert_equal Priming.render_svg(Diagrams::RAILROAD),
                 Dewasm::Merman.render_svg(Diagrams::RAILROAD)
  end

  def test_parse_metadata_matches_a_freshly_initialized_instance
    assert_equal Priming.parse_metadata(Diagrams::PIE),
                 Dewasm::Merman.parse_metadata(Diagrams::PIE)
  end

  # Each instance renders with a hash seed of its own, and the seed reaches no
  # output: the two renders agree byte for byte.
  def test_each_render_gets_its_own_hash_seed
    first_svg, first_seed = render_with_seed(Random.new(1))
    second_svg, second_seed = render_with_seed(Random.new(2))

    assert_equal first_svg, second_svg
    refute_equal first_seed, second_seed
  end

  def test_a_snapshot_of_another_version_is_rejected
    header = ["DWMS", 1, 0, 0, 0].pack("a4CL<L<Q<")
    with_snapshot_file(Zlib::Deflate.deflate(header)) do
      error = assert_raises(Dewasm::Merman::Error) do
        Dewasm::Merman.render_svg(Diagrams::FLOWCHART)
      end

      assert_includes error.message, "is not a version #{Snapshot::VERSION} snapshot"
    end
  end

  def test_a_missing_snapshot_asks_for_rake_generate
    with_snapshot_file(nil) do
      error = assert_raises(Dewasm::Merman::Error) do
        Dewasm::Merman.render_svg(Diagrams::FLOWCHART)
      end

      assert_includes error.message, "run `rake generate`"
    end
  end

  private

  # Renders on an instance the test holds, so that the injected seed can be read
  # back out of its memory.
  def render_with_seed(random)
    instance = Dewasm::Merman.send(:restored_instance, random)
    seed = instance.memory.buffer.get_string(Snapshot.seed_offset, Snapshot::SEED_SIZE)
    svg = Dewasm::Merman.send(:run, instance, "merman_render_svg", Diagrams::FLOWCHART,
                              Dewasm::Merman.send(:svg_options, nil, nil, false))
    [svg, seed]
  end
end
