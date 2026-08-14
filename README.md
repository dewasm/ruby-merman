# dewasm-merman

**Mermaid** diagrams rendered in **pure Ruby**.

The renderer is [merman](https://github.com/Latias94/merman), a headless Rust implementation of Mermaid, compiled to `wasm32-wasip1` and converted to Ruby source by [dewasm](https://github.com/dewasm/dewasm).
There is *no browser*, *no native extension*, and *no wasm runtime* involved: the gem is Ruby code that a stock `ruby` executes.

## Install

```console
$ gem install dewasm-merman
```

Or in `Gemfile`:

```ruby
gem "dewasm-merman"
```

## Usage

```ruby
require "dewasm/merman"

svg = Dewasm::Merman.render_svg(<<~MERMAID)
  flowchart TD
    A[Start] --> B[Done]
MERMAID

File.write("flowchart.svg", svg)
```

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

The build enables merman's `complete-svg` and `ascii` features, which is merman's full SVG capability set: the Cytoscape and ELK layout engines and the RaTeX math backend are all compiled in, so no diagram type and no `layout:` or `$$...$$` construct is turned off by the feature selection.
`render_ascii` covers the subset merman renders as terminal text; asking it for another type raises `Dewasm::Merman::Error`.

Railroad grammar diagrams take one of four dialect headers: `railroad-beta` for merman's own grammar function syntax, `railroad-ebnf-beta` for EBNF, `railroad-abnf-beta` for ABNF, and `railroad-peg-beta` for PEG.

```ruby
svg = Dewasm::Merman.render_svg(<<~MERMAID)
  railroad-beta
  expr = sequence(nonterminal("term"), zeroOrMore(terminal("+"))) ;
MERMAID
```

The result carries `aria-roledescription="railroad"` and the `railroad-rule`, `railroad-nonterminal`, and `railroad-terminal` classes that Mermaid's own railroad output uses.

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

Reproducible output, for snapshot tests:

```ruby
svg = Dewasm::Merman.render_svg(text, deterministic_text_measurer: true, random: Random.new(42))
```

## API

Every function is a one-shot module function: it creates a wasm module instance, restores the shipped state snapshot into it, injects a fresh hash seed, renders, and returns.
No instance is retained between calls, so no linear memory is held after a call returns and there is no mutable state to synchronize.
The snapshot itself is read once per process and only ever copied from.

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

## Requirements

Ruby 3.4 or newer: the generated runtime represents wasm linear memory as an `IO::Buffer`.
No other gems are needed at run time.

## How it is built

Three steps, all driven by the Rakefile in this repository.
None of the build products is committed: `lib/dewasm/merman/wasm_module.rb` and `lib/dewasm/merman/snapshot.bin.gz` are produced during the build and shipped in the gem.

1. `rake wasm:build` compiles `wasm/`, a small Rust crate that wraps merman behind a flat wasm ABI (`merman_alloc`, `merman_result_ptr`, `merman_result_len`, and one entry point per function taking a text pointer and an options JSON pointer, returning a status), and post-processes it with `wasm-opt -Oz`.
2. `rake generate` runs dewasm over that module: `dewasm wasm/merman.wasm --target ruby --mode library --no-default-wasi --module-name Dewasm::Merman::WasmModule -o lib/dewasm/merman/wasm_module.rb`.
3. The same task then runs `tools/prime_snapshot.rb`, which instantiates the generated module, renders one small flowchart so that merman's initialization runs, and writes the resulting state to `lib/dewasm/merman/snapshot.bin.gz`.

`--no-default-wasi` leaves the WASI imports to the embedder, so the generated file carries no WASI implementation at all.
The priming harness in `tools/priming.rb`, which the tests share with the build, supplies the few imports merman's initialization asks for: a recorded seed, the clocks, an empty environment, and standard error for a panic message.
It stays out of the gem, which supplies stubs that raise instead.

To regenerate from a clean checkout:

```console
$ rake wasm:build
$ rake generate
$ rake test
```

`rake wasm:build` needs the `wasm32-wasip1` Rust target (`rustup target add wasm32-wasip1`) and `wasm-opt` from Binaryen.
`rake generate` needs a dewasm binary; the path comes from the `DEWASM_BIN` environment variable.
The dewasm revision these instructions were verified against is recorded in `DEWASM_REVISION`.

The merman version is pinned exactly in `wasm/Cargo.toml` and surfaced as `Dewasm::Merman::MERMAN_VERSION`.
`wasm/Cargo.lock` is committed because merman's sibling crates publish alpha versions that move independently, and a mixed set does not compile.

## Size, memory, and speed

The table below is generated by `rake measure`, which measures on the machine it runs on and rewrites the block between the `measurements` markers in this file.
It depends on the build products, so it runs `rake generate` first; the `.gem` row appears only when a built gem is present in the checkout.
Each timing is a warmup call followed by the median of three measured runs.
The sizes come from `File.size`, and the resident memory from `ps` on a child process that has just required the module.

<!-- measurements:begin -->
Measured on macOS 26.5.2, Apple M1 Pro, Ruby 4.0.4, rendering a two-node flowchart.

| Quantity | Value |
| --- | --- |
| `wasm/merman.wasm` after `wasm-opt -Oz` | 11.8 MB |
| Generated `wasm_module.rb` | 48.6 MB |
| Shipped `snapshot.bin.gz` | 2.7 MB |
| Packaged `.gem` | 9.5 MB |
| `require "dewasm/merman"` | 4.7 s |
| Resident memory after `require` | 1125.9 MB |
| One module instantiation | 38 ms |
| `render_svg`, flowchart | 74 ms |
| `render_svg`, sequence diagram | 87 ms |
| `render_svg`, railroad diagram | 77 ms |
| `render_ascii`, flowchart | 53 ms |
| `parse_metadata` | 113 ms |
<!-- measurements:end -->

The rows fall into three groups.
The first ones are what ships: the wasm module, the Ruby source dewasm generates from it, the state snapshot, and the packaged gem.
The next two are the one-time cost of loading that source, in time and in resident memory.
The rest are per-call costs, one module instantiation and one call of each function.

The snapshot is what keeps a render from paying merman's initialization.
merman builds its font metrics table and its theme configuration on the first render of an instance, and that work costs far more than the render itself.
The build does one render, captures the module state it leaves behind, and ships it as `snapshot.bin.gz`; each call restores that state into its fresh instance instead of building it again, so the initialization is paid once at build time rather than on every render.
The state is the module's linear memory and its one mutable global, which is all the wasm module has, so a restored instance renders exactly what a freshly initialized one renders.
A missing snapshot file, or one of another version, is an error asking for `rake generate`: there is no second path that would render the same output more slowly.

The one thing a restored instance must not share with every other instance is the hash seed merman drew while initializing.
The build records where in memory that seed sits, and every render writes bytes from its `random:` source over it, so each render hashes with a seed of its own while the tables built around the old one keep working.
Recording the offset is a search for the exact bytes the build handed out, and it insists on finding them in exactly one place, so a toolchain that moves the seed elsewhere stops the build instead of shipping instances that share one seed.

The artifact therefore contains no WASI implementation and reaches nothing outside itself while rendering.
The imports the wasm module declares are all resolved to stubs that raise `Dewasm::Merman::Error`, and none of them fires: rendering reads no clock, no environment, no file, and no operating system randomness.

Three facts hold whatever the magnitudes are.
Resident memory after `require` is dominated by the instruction sequences of the loaded code, not by rendering, so it is paid once and does not grow with the number of calls.
Instantiation is a small part of a one-shot render, so the API that instantiates per call costs little over one that reuses an instance, and it keeps no wasm memory alive between calls.
Turning merman features off buys size but not speed: a build of the same release with only the `svg` feature produces a smaller wasm module and the same time per render, and it pays for that size with the diagram types it drops.

The numbers move with the merman version pinned in `wasm/Cargo.toml` and with the dewasm revision used to generate the module, so rerun `rake measure` after changing either.

## License

This repository's own code is MIT: see `LICENSE`.

merman is dual licensed under MIT or Apache-2.0, and this gem takes it under MIT: see `LICENSE-MERMAN`.
The gem also ships merman's `THIRD_PARTY_NOTICES-MERMAN.md`, upstream's inventory of the projects merman derives from (Mermaid itself among them).
That inventory covers every upstream artifact; this gem contains only the `complete-svg` and `ascii` feature closure.

merman is not affiliated with or endorsed by Mermaid.
