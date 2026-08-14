# frozen_string_literal: true

require "date"
require "minitest/autorun"

require "dewasm/merman"

# Runs a block with the snapshot file absent, which is the path a checkout whose
# snapshot has not been built takes.
module WithoutSnapshot
  def without_snapshot
    path = Dewasm::Merman::Snapshot::PATH
    hidden = "#{path}.hidden"
    File.rename(path, hidden) if File.exist?(path)
    Dewasm::Merman::Snapshot.forget
    yield
  ensure
    File.rename(hidden, path) if File.exist?(hidden)
    Dewasm::Merman::Snapshot.forget
  end
end

module Diagrams
  FLOWCHART = "flowchart TD\n  A[Start] --> B[Done]"
  SEQUENCE = "sequenceDiagram\n  Alice->>Bob: Hi\n  Bob-->>Alice: Hello"
  PIE = "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2"
  CLASS = "classDiagram\n  Animal <|-- Dog"
  STATE = "stateDiagram-v2\n  [*] --> Still\n  Still --> [*]"
  GANTT = "gantt\n  title Plan\n  dateFormat YYYY-MM-DD\n  section Work\n  Task :a1, 2024-01-01, 30d"
  MINDMAP = "mindmap\n  root((core))\n    A\n    B"
  RAILROAD = <<~RAILROAD
    railroad-beta
    accTitle: Expression grammar
    expr = sequence(nonterminal("term"), optional(special("guard")), zeroOrMore(terminal("+"))) ;
  RAILROAD
  RAILROAD_EBNF = <<~EBNF
    railroad-ebnf-beta
    expr = term , { "+" , term } ;
    term = "a" | "b" ;
  EBNF
end
