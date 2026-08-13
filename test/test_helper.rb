# frozen_string_literal: true

require "date"
require "minitest/autorun"

require "dewasm/merman"

module Diagrams
  FLOWCHART = "flowchart TD\n  A[Start] --> B[Done]"
  SEQUENCE = "sequenceDiagram\n  Alice->>Bob: Hi\n  Bob-->>Alice: Hello"
  PIE = "pie title Pets\n  \"Dogs\" : 3\n  \"Cats\" : 2"
  CLASS = "classDiagram\n  Animal <|-- Dog"
  STATE = "stateDiagram-v2\n  [*] --> Still\n  Still --> [*]"
  GANTT = "gantt\n  title Plan\n  dateFormat YYYY-MM-DD\n  section Work\n  Task :a1, 2024-01-01, 30d"
  MINDMAP = "mindmap\n  root((core))\n    A\n    B"
end
