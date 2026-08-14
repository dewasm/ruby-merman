# frozen_string_literal: true

require "date"
require "minitest/autorun"

require "dewasm/merman"

# Runs a block with the snapshot file replaced by the given bytes, or absent when
# they are nil, which is what a checkout whose build has not run looks like.
module WithSnapshotFile
  def with_snapshot_file(bytes)
    path = Dewasm::Merman::Snapshot::PATH
    hidden = "#{path}.hidden"
    File.rename(path, hidden)
    File.binwrite(path, bytes) if bytes
    Dewasm::Merman::Snapshot.forget
    yield
  ensure
    File.unlink(path) if File.exist?(path)
    File.rename(hidden, path)
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
