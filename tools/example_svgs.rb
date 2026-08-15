# frozen_string_literal: true

# Renders the README's example diagrams and writes them under examples/, where the README displays them as images.
# The render is render_svg_resvg_safe because its output has no foreignObject, which image contexts such as GitHub's README display may not support.

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "dewasm/merman"

module Dewasm
  module Merman
    module ExampleSvgs
      ROOT = File.expand_path("..", __dir__)

      # The diagram texts of the README's examples, keyed by the image path the README shows.
      EXAMPLES = {
        "examples/flowchart.svg" =>
          "flowchart LR\n  A[Commit] --> B{CI passes?}\n  B -->|Yes| C[Merge]\n  B -->|No| D[Fix]\n  D --> A\n",
        "examples/railroad.svg" =>
          "railroad-ebnf-beta\nexpr = term , { \"+\" , term } ;\n" \
            "term = factor , { \"*\" , factor } ;\nfactor = number | \"(\" , expr , \")\" ;\n"
      }.freeze

      module_function

      def render(text)
        Merman.render_svg_resvg_safe(text)
      end

      def write_all
        EXAMPLES.each { |path, text| File.write(File.join(ROOT, path), render(text)) }
      end
    end
  end
end

Dewasm::Merman::ExampleSvgs.write_all if $PROGRAM_NAME == __FILE__
