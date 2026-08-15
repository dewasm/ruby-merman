# dewasm-merman

**Mermaid** diagrams rendered in **pure Ruby**.

The renderer is [merman](https://github.com/Latias94/merman), a headless Rust implementation of Mermaid, compiled to `wasm32-wasip1` and converted to Ruby source by [dewasm](https://github.com/dewasm/dewasm).
There is *no browser*, *no native extension*, and *no wasm runtime* involved: the gem is Ruby code that a stock `ruby` executes.

The gem is built from merman `0.8.0-alpha.5` on crates.io, pinned in `wasm/Cargo.toml` and surfaced as `Dewasm::Merman::MERMAN_VERSION`.
Two cargo features are enabled: `complete-svg` and `ascii`.

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
The table maps each function to the merman API it wraps.

| Ruby | merman |
| --- | --- |
| `Dewasm::Merman.render_svg(text, **options)` | `HeadlessRenderer::render_svg_sync` |
| `Dewasm::Merman.render_svg_readable(text, **options)` | `HeadlessRenderer::render_svg_readable_sync` |
| `Dewasm::Merman.render_svg_resvg_safe(text, **options)` | `HeadlessRenderer::render_resvg_compatible_svg_sync` |
| `Dewasm::Merman.render_ascii(text, **options)` | `HeadlessAsciiRenderer::render_ascii_sync` |
| `Dewasm::Merman.parse_metadata(text, **options)` | `HeadlessRenderer::parse_metadata_sync` |

Options on the three SVG functions (`render_svg`, `render_svg_readable`, and `render_svg_resvg_safe`):

| Option | Default | merman |
| --- | --- | --- |
| `site_config:` | `nil` | `with_site_config`, a Hash carried as JSON |
| `diagram_id:` | `nil` | `with_diagram_id` |
| `deterministic_text_measurer:` | `false` | `with_deterministic_text_measurer` |
| `random:` | `Random` | the source of the render's hash seed |

`parse_metadata` takes `site_config:` and `random:`.

Options on `render_ascii`:

| Option | Default | merman |
| --- | --- | --- |
| `charset:` | `:unicode` | `AsciiRenderOptions#charset`, `:unicode` or `:ascii` |
| `strict_parsing:` | `nil` | `nil` keeps merman's own parse default; `with_strict_parsing` when true, `with_lenient_parsing` when false |
| `fixed_today:` | `nil` | `RuntimePolicy#with_fixed_today`, a `Date` |
| `fixed_local_offset_minutes:` | `nil` | `RuntimePolicy#try_with_fixed_local_offset_minutes` |
| `site_config:` | `nil` | `with_site_config` |
| `random:` | `Random` | the source of the render's hash seed |

`render_ascii` also takes the remaining `AsciiRenderOptions` fields as keywords, each with merman's default:

- `default_direction:` (`:left_right` or `:top_down`),
- `color_mode:` (`:plain`, `:ansi16`, `:ansi256`, `:true_color`, `:html`),
- `color_theme:` (`:light` or `:dark`),
- `box_border_padding:`,
- `graph_padding_x:`, `graph_padding_y:`,
- `sequence_participant_spacing:`, `sequence_message_spacing:`, `sequence_self_message_width:`, `sequence_mirror_actors:`,
- `xychart_vertical_plot_height:`, `xychart_category_band_width:`, `xychart_horizontal_plot_width:`,
- `max_grid_cells:`,
- `relation_summary_diagnostics:`.

An unknown keyword raises `ArgumentError`.

`random:` accepts anything that responds to `bytes(n)` and returns that many bytes.
It supplies the hash seed the render starts from, which merman's hash maps derive their own seeds from.
No output in this build depends on it: two renders of the same text with different seeds agree byte for byte.

Errors from merman are raised as `Dewasm::Merman::Error` carrying merman's message, for example `Diagram parse error (flowchart-v2): Unexpected character at 15` or `` ASCII rendering does not support diagram type `pie` ``.
Text whose diagram type merman cannot detect is one of those errors (`No diagram type detected matching given configuration for text: ...`), not `nil`.
The functions return `nil` only where merman itself returns "no diagram" without an error, which in this build's feature set does not occur for text input.

## How it is built

`wasm/` is a small Rust crate that wraps merman behind a flat wasm ABI: `merman_alloc`, `merman_result_ptr`, `merman_result_len`, and one entry point per function taking a text pointer and an options JSON pointer and returning a status.
One more entry point, `merman_diagram_types`, takes nothing and returns the rows of the diagram type table above, which `rake diagram_types` and the tests read.
It is compiled to `wasm32-wasip1`, post-processed with `wasm-opt -Oz`, and converted to Ruby by dewasm at the revision recorded in `DEWASM_REVISION`, in library mode with `--no-default-wasi`.
That flag leaves the WASI imports to the embedder, so the generated file carries no WASI implementation at all.

Neither build product is committed: `lib/dewasm/merman/wasm_module.rb` and `lib/dewasm/merman/snapshot.bin.gz` are produced by the build and shipped in the gem.
The initialization harness in `tools/snapshot_util.rb`, which the tests share with the build, supplies the few imports merman's initialization asks for: a recorded seed, the clocks, an empty environment, and standard error for a panic message.
It stays out of the gem, which supplies stubs that raise instead.

`wasm/Cargo.lock` is committed because merman's sibling crates publish alpha versions that move independently, and a mixed set does not compile.

## Snapshot

merman builds its font metrics table and its theme configuration on the first render of an instance, and that work costs far more than the render itself.
The build does one render and ships the state it leaves behind as `snapshot.bin.gz`: the module's linear memory and its one mutable global, which is all the wasm module has, so a restored instance renders exactly what a freshly initialized one renders.
Every function is a one-shot module function: it creates an instance, restores that snapshot into it, injects a fresh hash seed, renders, and returns.
Nothing is retained between calls, so no linear memory is held after a call returns and there is no mutable state to synchronize; the snapshot itself is read once per process and only ever copied from.
A missing snapshot file, or one of another version, is an error asking for `rake generate`: there is no second path that would render the same output more slowly.

A restored instance must not keep the hash seed merman drew while initializing, so every render writes bytes from its `random:` source over it and hashes with a seed of its own while the tables built around the old one keep working.
The build finds that offset by searching for the exact seed bytes it handed out and insisting on exactly one match, so a toolchain that moves the seed elsewhere stops the build instead of shipping instances that share one seed.

The imports the wasm module declares are all resolved to stubs that raise `Dewasm::Merman::Error`, and none of them fires while rendering: a render reads no clock, no environment, no file, and no operating system randomness, so it reaches nothing outside the artifact.

## Size, memory, and speed

<!-- measurements:begin -->
Measured on macOS 26.5.2, Apple M1 Pro, Ruby 4.0.4, rendering a two-node flowchart.

| Quantity | Value |
| --- | --- |
| `wasm/merman.wasm` after `wasm-opt -Oz` | 11.8 MB |
| Generated `wasm_module.rb` | 48.6 MB |
| Shipped `snapshot.bin.gz` | 2.7 MB |
| Packaged `.gem` | 9.5 MB |
| `require "dewasm/merman"` | 3.7 s |
| Resident memory after `require` | 1125.0 MB |
| One module instantiation | 29 ms |
| `render_svg`, flowchart | 56 ms |
| `render_svg`, sequence diagram | 69 ms |
| `render_svg`, railroad diagram | 58 ms |
| `render_ascii`, flowchart | 41 ms |
| `parse_metadata` | 85 ms |
<!-- measurements:end -->

> [!IMPORTANT]
> Loading this gem costs **over a gigabyte of resident memory** and several seconds, paid once per process.

The rows fall into three groups.
The first ones are what ships: the wasm module, the Ruby source dewasm generates from it, the state snapshot, and the packaged gem.
The next two are that load cost, in time and in resident memory.
The rest are per-call costs, one module instantiation and one call of each function.

Three facts hold whatever the magnitudes are.
Resident memory after `require` is dominated by the instruction sequences of the loaded code, not by rendering, so it does not grow with the number of calls.
Instantiation is a small part of a one-shot render, so the API that instantiates per call costs little over one that reuses an instance, and it keeps no wasm memory alive between calls.
Turning merman features off buys size but not speed: a build of the same release with only the `svg` feature produces a smaller wasm module and the same time per render, and it pays for that size with the diagram types it drops.

The numbers move with the pinned merman version and with the dewasm revision used to generate the module, so rerun `rake measure` after changing either.

If those sizes or that resident memory rule this gem out, [dewasm-pozeiden](https://github.com/dewasm/ruby-pozeiden) is a much smaller Mermaid renderer, but covers fewer diagram types.

## Tasks

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
They are rendered with `render_svg_resvg_safe`, whose output displays as an image without `foreignObject` support.
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

## License

This repository's own code is MIT: see `LICENSE`.

merman is dual licensed under MIT or Apache-2.0, and this gem takes it under MIT: see `LICENSE-MERMAN`.
The gem also ships merman's `THIRD_PARTY_NOTICES-MERMAN.md`, upstream's inventory of the projects merman derives from (Mermaid itself among them).
That inventory covers every upstream artifact; this gem contains only the `complete-svg` and `ascii` feature closure.

merman is not affiliated with or endorsed by Mermaid.
