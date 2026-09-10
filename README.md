# dewasm-merman

[![Test](https://github.com/dewasm/ruby-merman/actions/workflows/test.yml/badge.svg)](https://github.com/dewasm/ruby-merman/actions/workflows/test.yml)
[![Gem](https://img.shields.io/gem/v/dewasm-merman)](https://rubygems.org/gems/dewasm-merman)

**Mermaid** diagrams rendered in **pure Ruby**.

The renderer is [merman](https://github.com/Latias94/merman), a headless Rust implementation of Mermaid, compiled to `wasm32-wasip1` and converted to Ruby source by [dewasm](https://github.com/dewasm/dewasm).
There is *no browser*, *no native extension*, and *no wasm runtime* involved: the gem is Ruby code that a stock `ruby` executes.

The gem is built from merman `0.8.0-alpha.6` on crates.io.
Two cargo features are enabled: `complete-svg-elk` and `ascii`.

## Install

```console
$ gem install dewasm-merman
```

Or in `Gemfile`:

```ruby
gem "dewasm-merman"
```

Ruby 3.4 or newer is required, because the converted module stores WebAssembly linear memory in an `IO::Buffer`.

## Usage

```ruby
require "dewasm/merman"

svg = Dewasm::Merman.render_svg(<<~MERMAID)
  flowchart LR
    A[Commit] --> B{CI passes?}
    B -->|Yes| C[Merge]
    B -->|No| D[Fix]
    D --> A
MERMAID

File.write("flowchart.svg", svg)
```

![The example flowchart rendered to SVG](examples/flowchart.svg)

Railroad grammar diagrams render the same way:

```ruby
svg = Dewasm::Merman.render_svg(<<~MERMAID)
  railroad-ebnf-beta
  expr = term , { "+" , term } ;
  term = factor , { "*" , factor } ;
  factor = number | "(" , expr , ")" ;
MERMAID
```

![The example railroad diagram rendered to SVG](examples/railroad.svg)

Terminal text instead of SVG:

```ruby
puts Dewasm::Merman.render_ascii(<<~MERMAID)
  flowchart LR
    A[Start] --> B[Done]
MERMAID
```

```
┌───────┐     ┌──────┐
│       │     │      │
│ Start ├────►│ Done │
│       │     │      │
└───────┘     └──────┘
```

```ruby
puts Dewasm::Merman.render_ascii(<<~MERMAID, charset: :ascii)
  flowchart TD
    A[Start] --> B[Done]
MERMAID
```

```
+-------+
|       |
| Start |
|       |
+-------+
    |
    |
    |
    |
    v
+-------+
|       |
|  Done |
|       |
+-------+
```

## Diagram types

The enabled features are merman's full SVG capability set: the Cytoscape and ELK layout engines and the RaTeX math backend are all compiled in, so no diagram type and no `layout:` or `$$...$$` construct is turned off by the feature selection.
`render_ascii` covers the subset merman renders as terminal text; asking it for a type without a check in the ASCII column raises `Dewasm::Merman::Error`.
Each row names the keyword the diagram text opens with.

<!-- diagram-types:begin -->
| Diagram type | SVG | ASCII |
| --- | :-: | :-: |
| `architecture-beta` | ✓ | — |
| `block-beta` | ✓ | — |
| `C4Context`, `C4Container`, `C4Component`, `C4Dynamic`, `C4Deployment` | ✓ | — |
| `classDiagram` | ✓ | ✓ |
| `cynefin-beta` | ✓ | — |
| `erDiagram` | ✓ | ✓ |
| `eventmodeling` | ✓ | — |
| `flowchart` | ✓ | ✓ |
| `gantt` | ✓ | ✓ |
| `gitGraph` | ✓ | ✓ |
| `info` | ✓ | — |
| `ishikawa-beta` | ✓ | — |
| `journey` | ✓ | ✓ |
| `kanban` | ✓ | ✓ |
| `mindmap` | ✓ | ✓ |
| `packet-beta` | ✓ | ✓ |
| `pie` | ✓ | — |
| `quadrantChart` | ✓ | — |
| `radar-beta` | ✓ | — |
| `railroad-beta`, `railroad-ebnf-beta`, `railroad-abnf-beta`, `railroad-peg-beta` | ✓ | — |
| `requirementDiagram` | ✓ | — |
| `sankey-beta` | ✓ | — |
| `sequenceDiagram` | ✓ | ✓ |
| `stateDiagram-v2` | ✓ | ✓ |
| `timeline` | ✓ | ✓ |
| `treemap-beta` | ✓ | — |
| `treeView-beta` | ✓ | ✓ |
| `venn-beta` | ✓ | — |
| `wardley-beta` | ✓ | — |
| `xychart-beta` | ✓ | ✓ |
| `zenuml` | ✓ | — |
<!-- diagram-types:end -->

Diagram metadata, mirroring Mermaid's `mermaidAPI.parse()` return shape:

```ruby
metadata = Dewasm::Merman.parse_metadata(<<~MERMAID)
  ---
  title: My Chart
  ---
  pie title Pets
    "Dogs" : 3
MERMAID

metadata["diagram_type"]               # => "pie"
metadata["title"]                      # => "My Chart"
metadata["config"]                     # => {} (front-matter and directive overrides)
metadata["effective_config"]["theme"]  # => "default"
```

Mermaid site configuration is a Hash, serialized to JSON and applied as merman's site config:

```ruby
svg = Dewasm::Merman.render_svg(<<~MERMAID, site_config: { "theme" => "dark" })
  flowchart TD
    A --> B
MERMAID
```

## API

A single call renders the given diagram text to SVG or to terminal text.
The functions and their keyword groups mirror merman's request model.

| Ruby | merman |
| --- | --- |
| `Dewasm::Merman.render_svg(text, **options)` | `Renderer::render` with `RenderRequest::svg` |
| `Dewasm::Merman.render_ascii(text, **options)` | `Renderer::render` with `RenderRequest::ascii` |
| `Dewasm::Merman.parse_metadata(text, **options)` | `Engine::parse_metadata_sync` |

Options shared by `render_svg` and `render_ascii`, carrying the operation-level merman APIs:

| Option | Default | merman |
| --- | --- | --- |
| `site_config:` | `nil` | `Engine#with_site_config`, a Hash carried as JSON |
| `parse_options:` | `nil` | `ParseOptions`: `:strict` or `:lenient`; `nil` keeps merman's own default |
| `fixed_today:` | `nil` | `RuntimePolicy#with_fixed_today`, a `Date` |
| `fixed_local_offset_minutes:` | `nil` | `RuntimePolicy#try_with_fixed_local_offset_minutes` |
| `random:` | `Random` | the source of the render's hash seed |

Options on `render_svg`, mirroring `SvgRequest`:

| Option | Default | merman |
| --- | --- | --- |
| `pipeline:` | `:parity` | `SvgPipeline`: `:parity`, `:readable` (`<text>` fallbacks for `<foreignObject>` labels), or `:resvg_safe` (restricted to what usvg, resvg, and raster converters accept) |
| `diagram_id:` | `nil` | `SvgRenderOptions#diagram_id` |
| `viewbox_padding:` | merman's default | `SvgRenderOptions#viewbox_padding` |

Options on `render_ascii`, mirroring the three parts of `AsciiRequest`:

| Option | merman |
| --- | --- |
| the `AsciiRenderOptions` keywords below | `AsciiRequest#options` |
| `resources:`, a Hash | `AsciiRequest#resources`, an `AsciiResourcePolicy` |
| `viewport:`, a Hash | `AsciiRequest#viewport`, an `AsciiViewportPolicy` |

The `AsciiRenderOptions` fields come as keywords, each with merman's default:

- `charset:` (`:unicode` or `:ascii`),
- `terminal_width_profile:` (`:unicode` or `:cjk`),
- `layout_profile:` (`:canonical` or `:compact`),
- `default_direction:` (`:left_right` or `:top_down`),
- `color_mode:` (`:plain`, `:ansi16`, `:ansi256`, `:true_color`, `:html`),
- `color_theme:` (`:light` or `:dark`),
- `box_border_padding:`,
- `graph_padding_x:`, `graph_padding_y:`,
- `flowchart_node_label_wrap_width:`,
- `sequence_participant_spacing:`, `sequence_message_spacing:`, `sequence_self_message_width:`, `sequence_mirror_actors:`,
- `xychart_vertical_plot_height:`, `xychart_category_band_width:`, `xychart_horizontal_plot_width:`,
- `relation_summary_diagnostics:`.

The `resources:` Hash selects a profile and overrides individual limits, each with merman's default:

- `profile:` (`:interactive`, `:constrained`, `:trusted_native`, or `:unbounded_for_trusted_input`),
- `max_grid_cells:`, `max_layout_work_units:`, `max_document_cells:`, `max_output_bytes:`, `max_grapheme_bytes:`, `max_nesting_depth:`.

The `viewport:` Hash carries the `AsciiViewportPolicy` fields, each with merman's default:

- `max_width:`,
- `overflow:` (`:allow`, `:fallback`, or `:error`),
- `trim:` (`:preserve` or `:trim_trailing_spaces`).

`parse_metadata` takes `site_config:` and `random:`.

Errors from merman are raised as `Dewasm::Merman::Error` carrying merman's message, for example `Diagram parse error (flowchart-v2): Unexpected character at 15` or `` ASCII rendering does not support diagram type `pie` ``.

## How it is built

`wasm/` is a small Rust crate that wraps merman behind a flat wasm ABI.
It is compiled to `wasm32-wasip1`, post-processed with `wasm-opt`, and converted to Ruby by `dewasm`.

Neither build product is committed: `lib/dewasm/merman/wasm_module.rb` and `lib/dewasm/merman/snapshot.bin.gz` are produced by the build and shipped in the gem.

## Snapshot

merman spends a few seconds initializing internal data before its first render.
The gem avoids that cost by computing the initialized memory ahead of time and shipping it as `snapshot.bin.gz`, which each render restores instead of running the initialization.

## Size, memory, and speed

<!-- measurements:begin -->
Measured on macOS 26.6.2, Apple M1 Pro, Ruby 4.0.4, rendering a two-node flowchart.

| Quantity | Value |
| --- | --- |
| `wasm/merman.wasm` after `wasm-opt -Oz` | 11.3 MB |
| Generated `wasm_module.rb` | 49.0 MB |
| Shipped `snapshot.bin.gz` | 1.3 MB |
| Packaged `.gem` | 8.5 MB |
| `require "dewasm/merman"` | 3.8 s |
| Resident memory after `require` | 1148.6 MB |
| One module instantiation | 17 ms |
| `render_svg`, flowchart | 141 ms |
| `render_svg`, sequence diagram | 205 ms |
| `render_svg`, railroad diagram | 81 ms |
| `render_ascii`, flowchart | 114 ms |
| `parse_metadata` | 80 ms |
<!-- measurements:end -->

The numbers move with the pinned merman version and with the dewasm revision used to generate the module, so rerun `rake measure` after changing either.

> [!IMPORTANT]
> Loading this gem costs **~1 GB of resident memory** and several seconds.
>
> If those sizes or that resident memory rule this gem out, [dewasm-pozeiden](https://github.com/dewasm/ruby-pozeiden) is a much smaller Mermaid renderer, but covers fewer diagram types.

## Tasks

<details>

The Rakefile drives everything, and each task depends on the ones before it, so running a later task runs what it needs first.
From a clean checkout `rake test` is enough; the individual tasks are useful when only one step is in question.

### `rake wasm:build`

```console
$ rake wasm:build
```

Compiles `wasm/` and post-processes it into `wasm/merman.wasm`.
It needs the `wasm32-wasip1` Rust target (`rustup target add wasm32-wasip1`) and `wasm-opt` from Binaryen.

### `rake generate`

```console
$ rake generate
```

Converts that module into the Ruby the gem ships, and captures the state snapshot that ships with it.
It needs a dewasm binary, its path in `DEWASM_BIN`.

### `rake test`

```console
$ rake test
```

Runs `test/` against the generated module and the captured snapshot.
It needs `rake generate`.

### `rake measure`

```console
$ rake measure
```

Refreshes the measurements table in `README.md` with numbers from this machine.
It needs `rake generate`, and a built gem in the checkout for the `.gem` row.

### `rake diagram_types`

```console
$ rake diagram_types
```

Rewrites the diagram type table in `README.md` from the rows the wasm module exports and a render of each row's samples.
The test suite fails when the table no longer matches what this task writes.
It needs `rake generate`.

### `rake example_svgs`

```console
$ rake example_svgs
```

Rewrites the SVG files under `examples/` from the README's example diagrams.
They are rendered with the `:resvg_safe` pipeline, whose output displays as an image without `foreignObject` support.
The test suite fails when a committed SVG no longer matches what this task writes.
It needs `rake generate`.

### `rake build`

```console
$ rake build
```

Packages the gem.
It needs `rake generate`.

### `rake clean`

```console
$ rake clean
```

Removes the build products and `wasm/target`.
It needs nothing.

</details>

## License

This repository's own code is MIT: see `LICENSE`.

merman is dual licensed under MIT or Apache-2.0, and this gem takes it under MIT: see `LICENSE-MERMAN`.
The gem also ships merman's `THIRD_PARTY_NOTICES-MERMAN.md`, upstream's inventory of the projects merman derives from (Mermaid itself among them).
That inventory covers every upstream artifact; this gem contains only the `complete-svg-elk` and `ascii` feature closure.

merman is not affiliated with or endorsed by Mermaid.
