# dewasm-merman

Mermaid diagrams rendered in pure Ruby.
The renderer is [merman](https://github.com/Latias94/merman), a headless Rust implementation of Mermaid, compiled to `wasm32-wasip1` and converted to Ruby source by [dewasm](https://github.com/dewasm/dewasm).
There is no browser, no native extension, and no wasm runtime involved: the gem is Ruby code that a stock `ruby` executes.

## Install

```console
$ gem install dewasm-merman
```

Or in a Gemfile:

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
puts Dewasm::Merman.render_ascii("flowchart LR\n  A[Start] --> B[Done]")
```

```
┌───────┐     ┌──────┐
│       │     │      │
│ Start ├────►│ Done │
│       │     │      │
└───────┘     └──────┘
```

```ruby
puts Dewasm::Merman.render_ascii("flowchart TD\n  A[Start] --> B[Done]", charset: :ascii)
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

Diagram metadata, mirroring Mermaid's `mermaidAPI.parse()` return shape:

```ruby
metadata = Dewasm::Merman.parse_metadata("---\ntitle: My Chart\n---\npie title Pets\n  \"Dogs\" : 3\n")
metadata["diagram_type"]   # => "pie"
metadata["title"]          # => "My Chart"
metadata["config"]         # => {} (front-matter and directive overrides)
metadata["effective_config"]["theme"]  # => "default"
```

Mermaid site configuration is a Hash, serialized to JSON and applied as merman's site config:

```ruby
svg = Dewasm::Merman.render_svg("flowchart TD\n  A --> B", site_config: { "theme" => "dark" })
```

Reproducible output, for snapshot tests:

```ruby
svg = Dewasm::Merman.render_svg(text, deterministic_text_measurer: true, random: Random.new(42))
```

## API

Every function is a one-shot module function: it creates a wasm module instance, renders, and returns.
Nothing is retained between calls, so no linear memory is held after a call returns and there is no shared state to synchronize.

| Ruby | merman |
| --- | --- |
| `Dewasm::Merman.render_svg(text, **options)` | `HeadlessRenderer::render_svg_sync` |
| `Dewasm::Merman.render_svg_readable(text, **options)` | `HeadlessRenderer::render_svg_readable_sync` |
| `Dewasm::Merman.render_svg_resvg_safe(text, **options)` | `HeadlessRenderer::render_svg_resvg_safe_sync` |
| `Dewasm::Merman.render_ascii(text, **options)` | `HeadlessAsciiRenderer::render_ascii_sync` |
| `Dewasm::Merman.parse_metadata(text, **options)` | `HeadlessRenderer::parse_metadata_sync` |

Options on the three SVG functions:

| Option | Default | merman |
| --- | --- | --- |
| `site_config:` | `nil` | `with_site_config`, a Hash carried as JSON |
| `diagram_id:` | `nil` | `with_diagram_id` |
| `deterministic_text_measurer:` | `false` | `with_deterministic_text_measurer` |
| `random:` | `Random` | the source behind the WASI `random_get` import |

`parse_metadata` takes `site_config:` and `random:`.

Options on `render_ascii`:

| Option | Default | merman |
| --- | --- | --- |
| `charset:` | `:unicode` | `AsciiRenderOptions#charset`, `:unicode` or `:ascii` |
| `strict_parsing:` | `false` | `with_strict_parsing` when true, `with_lenient_parsing` when false |
| `fixed_today:` | `nil` | `with_fixed_today`, a `Date` |
| `fixed_local_offset_minutes:` | `nil` | `with_fixed_local_offset_minutes` |
| `site_config:` | `nil` | `with_site_config` |
| `random:` | `Random` | the source behind the WASI `random_get` import |

`render_ascii` also takes the remaining `AsciiRenderOptions` fields as keywords, each with merman's default: `default_direction:` (`:left_right` or `:top_down`), `color_mode:` (`:plain`, `:auto`, `:ansi16`, `:ansi256`, `:true_color`, `:html`), `color_theme:` (`:light` or `:dark`), `box_border_padding:`, `graph_padding_x:`, `graph_padding_y:`, `sequence_participant_spacing:`, `sequence_message_spacing:`, `sequence_self_message_width:`, `sequence_mirror_actors:`, `xychart_vertical_plot_height:`, `xychart_category_band_width:`, `xychart_horizontal_plot_width:`, `max_grid_cells:`, `relation_summary_diagnostics:`.
An unknown keyword raises `ArgumentError`.

`random:` accepts anything that responds to `bytes(n)` and returns that many bytes.
merman calls it once per render to seed a hash map, so a fixed source makes a render reproducible.

Errors from merman are raised as `Dewasm::Merman::Error` carrying merman's message, for example `Diagram parse error (flowchart-v2): Unexpected character at 15` or `ASCII rendering does not support diagram type \`pie\``.
Text whose diagram type merman cannot detect is one of those errors (`No diagram type detected matching given configuration for text: ...`), not `nil`.
The functions return `nil` only where merman itself returns "no diagram" without an error, which in this build's feature set does not occur for text input.

## Requirements

Ruby 3.4 or newer: the generated runtime represents wasm linear memory as an `IO::Buffer`.
No other gems are needed at run time.

## How it is built

Two steps, both driven by the Rakefile in this repository.
Neither the wasm module nor the generated Ruby is committed: `lib/dewasm/merman/wasm_module.rb` is produced during the build and shipped in the gem.

1. `rake wasm:build` compiles `wasm/`, a small Rust crate that wraps merman behind a flat wasm ABI (`merman_alloc`, `merman_result_ptr`, `merman_result_len`, and one entry point per function taking a text pointer and an options JSON pointer, returning a status), and post-processes it with `wasm-opt -Oz`.
2. `rake generate` runs dewasm over that module: `dewasm wasm/merman.wasm --target ruby --mode library --module-name Dewasm::Merman::WasmModule -o lib/dewasm/merman/wasm_module.rb`.

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

Measured on an Apple M-series machine with Ruby 4.0.4, rendering a two-node flowchart.

| Quantity | Value |
| --- | --- |
| `wasm/merman.wasm` after `wasm-opt -Oz` | 5.3 MB |
| Generated `wasm_module.rb` | 26 MB |
| Packaged `.gem` | 3.6 MB |
| `require "dewasm/merman"` | 1.6 s |
| Resident memory after `require` | 609 MB |
| One module instantiation | 7.6 ms |
| `render_svg`, flowchart | 308 ms |
| `render_svg`, sequence diagram | 308 ms |
| `render_ascii`, flowchart | 285 ms |
| `parse_metadata` | 327 ms |

The cost that dominates is loading 26 MB of Ruby: the `require` takes over a second and the resulting instruction sequences account for nearly all of the resident memory.
Rendering itself is a few hundred milliseconds and instantiation is a small part of it, so the one-shot API costs little over reusing an instance while keeping no wasm memory alive between calls.

## License

This repository's own code is MIT: see `LICENSE`.

merman is dual licensed under MIT or Apache-2.0, and this gem takes it under MIT: see `LICENSE-MERMAN`.
The gem also ships merman's `THIRD_PARTY_NOTICES-MERMAN.md`, upstream's inventory of the projects merman derives from (Mermaid itself among them).
That inventory covers every upstream artifact; this gem contains only the `render` and `ascii` feature closure.

merman is not affiliated with or endorsed by Mermaid.
