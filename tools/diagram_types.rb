# frozen_string_literal: true

# Verifies the diagram type table against the built module and rewrites it between the diagram-types markers in README.md.
# The rows come from the module's merman_diagram_types export, so the table cannot drift from the wasm side, and every cell is the result of rendering that row's samples.

lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "json"

require "dewasm/merman"

module Dewasm
  module Merman
    module DiagramTypes
      README = File.expand_path("../README.md", __dir__)
      BEGIN_MARKER = "<!-- diagram-types:begin -->"
      END_MARKER = "<!-- diagram-types:end -->"

      # One minimal sample per header keyword, with the diagram type id merman detects for it.
      SAMPLES = {
        "architecture-beta" => [
          "architecture",
          "architecture-beta\n  group api(cloud)[API]\n  service db(database)[Database] in api\n"
        ],
        "block-beta" => ["block", "block-beta\n  a b\n"],
        "C4Context" => ["c4", "C4Context\n  Person(a, \"A\")\n"],
        "C4Container" => ["c4", "C4Container\n  Person(a, \"A\")\n"],
        "C4Component" => ["c4", "C4Component\n  Person(a, \"A\")\n"],
        "C4Dynamic" => ["c4", "C4Dynamic\n  Person(a, \"A\")\n"],
        "C4Deployment" => ["c4", "C4Deployment\n  Person(a, \"A\")\n"],
        "classDiagram" => ["classDiagram", "classDiagram\n  class Animal\n"],
        "cynefin-beta" => ["cynefin", "cynefin-beta\ncomplex\n\"Probe\"\n"],
        "erDiagram" => ["er", "erDiagram\n  CUSTOMER ||--o{ ORDER : places\n"],
        "eventmodeling" => ["eventmodeling", "eventmodeling\ntf 01 cmd AddItem { productId: 7 }\n"],
        "flowchart" => ["flowchart-v2", "flowchart TD\n  A[Start] --> B[Done]\n"],
        "gantt" => [
          "gantt",
          "gantt\n  title Plan\n  dateFormat YYYY-MM-DD\n  section Work\n  Task :a1, 2024-01-01, 1d\n"
        ],
        "gitGraph" => ["gitGraph", "gitGraph\n  commit\n"],
        "info" => ["info", "info\n"],
        "ishikawa-beta" => [
          "ishikawa",
          "ishikawa-beta\n    Blurry Photo\n        Process\n            Out of focus\n"
        ],
        "journey" => ["journey", "journey\n  title Day\n  section Work\n    Code: 5: Me\n"],
        "kanban" => ["kanban", "kanban\n  backlog[Backlog]\n    task1[Task]\n"],
        "mindmap" => ["mindmap", "mindmap\n  root((core))\n"],
        "packet-beta" => ["packet", "packet-beta\n  0-15: \"Field\"\n"],
        "pie" => ["pie", "pie title Pets\n  \"Dogs\" : 3\n"],
        "quadrantChart" => [
          "quadrantChart",
          "quadrantChart\n  title Focus\n  x-axis Low --> High\n  y-axis Low --> High\n  A: [0.3, 0.6]\n"
        ],
        "radar-beta" => ["radar", "radar-beta\naxis A,B,C\ncurve mycurve{1,2,3}\n"],
        "railroad-beta" => [
          "railroad",
          "railroad-beta\nexpr = sequence(nonterminal(\"term\"), zeroOrMore(terminal(\"+\"))) ;\n"
        ],
        "railroad-ebnf-beta" => ["railroadEbnf", "railroad-ebnf-beta\nexpr = \"a\" ;\n"],
        "railroad-abnf-beta" => ["railroadAbnf", "railroad-abnf-beta\nexpr = \"a\" ;\n"],
        "railroad-peg-beta" => ["railroadPeg", "railroad-peg-beta\nexpr <- \"a\" ;\n"],
        "requirementDiagram" => ["requirement", <<~MERMAID],
            requirementDiagram
              requirement r {
                id: 1
                text: t
                risk: low
                verifymethod: test
              }
              element e {
                type: sim
              }
              e - satisfies -> r
          MERMAID
        "sankey-beta" => ["sankey", "sankey-beta\n\nA,B,10\n"],
        "sequenceDiagram" => ["sequence", "sequenceDiagram\n  Alice->>Bob: Hi\n"],
        "stateDiagram-v2" => ["stateDiagram", "stateDiagram-v2\n  [*] --> Idle\n"],
        "timeline" => ["timeline", "timeline\n  title History\n  2024 : event\n"],
        "treemap-beta" => ["treemap", "treemap-beta\n\"Root\"\n  \"Leaf\": 42\n"],
        "treeView-beta" => ["treeView", "treeView-beta\n\"Root\"\n    \"Child\"\n"],
        "venn-beta" => ["venn", "venn-beta\n  set A\n  set B\n  union A,B\n"],
        "wardley-beta" => [
          "wardley",
          "wardley-beta\ntitle Map\ncomponent Cup of Tea [0.79, 0.61]\n"
        ],
        "xychart-beta" => ["xychart", "xychart-beta\n  x-axis [a, b]\n  bar [1, 2]\n"],
        "zenuml" => ["zenuml", "zenuml\n@Starter(A)\nB.call()\n"]
      }.freeze

      module_function

      # The rows the wasm module exports: each row is the list of header keywords sharing one table line.
      def rows
        instance = WasmModule.new(IMPORTS)
        Snapshot.restore(instance, Random)
        status = instance.invoke("merman_diagram_types")
        length = instance.invoke("merman_result_len")
        payload =
          if length.zero?
            +""
          else
            instance
              .memory
              .buffer
              .get_string(instance.invoke("merman_result_ptr"), length)
              .force_encoding(Encoding::UTF_8)
          end
        raise Error, payload unless status.zero?

        JSON.parse(payload)
      end

      # The table between the markers.
      # The SVG column is uniformly checked because check_sample refuses a sample that does not render, so a type that lost SVG support stops the rewrite instead of silently losing its mark.
      def block
        lines =
          rows.map do |row|
            row.each { |header| check_sample(header) }
            ascii = row.map { |header| ascii_supported?(header) }.uniq
            unless ascii.size == 1
              raise "the headers of row #{row.inspect} disagree on ASCII support"
            end

            label = row.map { |header| "`#{header}`" }.join(", ")
            "| #{label} | ✓ | #{ascii.first ? "✓" : "—"} |"
          end
        ["| Diagram type | SVG | ASCII |", "| --- | :-: | :-: |", *lines].join("\n")
      end

      def rewrite_readme
        check_samples_cover_rows
        text = File.read(README)
        pattern = /^#{Regexp.escape(BEGIN_MARKER)}\n.*?^#{Regexp.escape(END_MARKER)}$/m
        unless text.match?(pattern)
          raise "#{README} has no #{BEGIN_MARKER} ... #{END_MARKER} block to rewrite"
        end

        replacement = "#{BEGIN_MARKER}\n#{block}\n#{END_MARKER}"
        File.write(README, text.sub(pattern) { replacement })
      end

      def check_samples_cover_rows
        headers = rows.flatten
        missing = headers - SAMPLES.keys
        extra = SAMPLES.keys - headers
        return if missing.empty? && extra.empty?

        raise "SAMPLES is out of step with the module's diagram type rows: " \
                "missing #{missing.inspect}, extra #{extra.inspect}"
      end

      # Confirms the sample exercises the intended diagram type and renders to SVG.
      def check_sample(header)
        detected, text = SAMPLES.fetch(header)
        reported = Merman.parse_metadata(text)["diagram_type"]
        unless reported == detected
          raise "the sample for #{header} was detected as #{reported}, expected #{detected}"
        end

        svg = Merman.render_svg(text)
        raise "the sample for #{header} did not render an SVG element" unless svg&.include?("<svg")
      end

      # True when render_ascii accepts the sample, false when it refuses the diagram type; any other error is a broken sample and raises.
      def ascii_supported?(header)
        Merman.render_ascii(SAMPLES.fetch(header).last)
        true
      rescue Error => e
        raise unless e.message.include?("does not support diagram type")

        false
      end
    end
  end
end

Dewasm::Merman::DiagramTypes.rewrite_readme if $PROGRAM_NAME == __FILE__
