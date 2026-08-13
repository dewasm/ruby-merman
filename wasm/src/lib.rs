//! The wasm ABI that the Ruby side of dewasm-merman calls.
//!
//! Every entry point takes a UTF-8 diagram text and a UTF-8 options JSON document
//! and returns a status: 0 for a result, 1 for "not a recognized diagram"
//! (upstream `Ok(None)`, no payload), 2 for an error whose message is the payload.
//! The payload is read back with `merman_result_ptr` and `merman_result_len`.

use std::cell::RefCell;

use merman::ascii::{
    AsciiCharset, AsciiColorMode, AsciiColorTheme, AsciiDirection, AsciiRenderOptions,
    HeadlessAsciiRenderer,
};
use merman::render::HeadlessRenderer;
use serde::Deserialize;
use serde_json::{Value, json};

const STATUS_OK: u32 = 0;
const STATUS_NONE: u32 = 1;
const STATUS_ERROR: u32 = 2;

thread_local! {
    static RESULT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_alloc(len: u32) -> *mut u8 {
    let mut buf = Vec::<u8>::with_capacity(len as usize);
    let ptr = buf.as_mut_ptr();
    std::mem::forget(buf);
    ptr
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_result_ptr() -> *const u8 {
    RESULT.with(|r| r.borrow().as_ptr())
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_result_len() -> u32 {
    RESULT.with(|r| r.borrow().len() as u32)
}

fn set_result(bytes: Vec<u8>, status: u32) -> u32 {
    RESULT.with(|r| *r.borrow_mut() = bytes);
    status
}

fn ok(payload: String) -> u32 {
    set_result(payload.into_bytes(), STATUS_OK)
}

fn none() -> u32 {
    set_result(Vec::new(), STATUS_NONE)
}

fn error(message: impl std::fmt::Display) -> u32 {
    set_result(message.to_string().into_bytes(), STATUS_ERROR)
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct Options {
    diagram_id: Option<String>,
    deterministic_text_measurer: bool,
    site_config: Option<Value>,
    strict_parsing: Option<bool>,
    fixed_today: Option<String>,
    fixed_local_offset_minutes: Option<i32>,
    ascii: AsciiOptions,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AsciiOptions {
    charset: Option<String>,
    default_direction: Option<String>,
    color_mode: Option<String>,
    color_theme: Option<String>,
    box_border_padding: Option<usize>,
    graph_padding_x: Option<usize>,
    graph_padding_y: Option<usize>,
    sequence_participant_spacing: Option<usize>,
    sequence_message_spacing: Option<usize>,
    sequence_self_message_width: Option<usize>,
    sequence_mirror_actors: Option<bool>,
    xychart_vertical_plot_height: Option<usize>,
    xychart_category_band_width: Option<usize>,
    xychart_horizontal_plot_width: Option<usize>,
    max_grid_cells: Option<usize>,
    relation_summary_diagnostics: Option<bool>,
}

struct Input<'a> {
    text: &'a str,
    options: Options,
}

fn slice<'a>(ptr: *const u8, len: u32) -> &'a [u8] {
    if ptr.is_null() || len == 0 {
        return &[];
    }
    unsafe { std::slice::from_raw_parts(ptr, len as usize) }
}

fn read_input<'a>(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> Result<Input<'a>, String> {
    let text = std::str::from_utf8(slice(text_ptr, text_len))
        .map_err(|e| format!("diagram text is not valid UTF-8: {e}"))?;
    let options_json = std::str::from_utf8(slice(options_ptr, options_len))
        .map_err(|e| format!("options JSON is not valid UTF-8: {e}"))?;
    let options = if options_json.trim().is_empty() {
        Options::default()
    } else {
        serde_json::from_str(options_json).map_err(|e| format!("invalid options JSON: {e}"))?
    };
    Ok(Input { text, options })
}

fn fixed_today(options: &Options) -> Result<Option<chrono::NaiveDate>, String> {
    match &options.fixed_today {
        None => Ok(None),
        Some(raw) => chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d")
            .map(Some)
            .map_err(|e| format!("invalid fixed_today {raw:?}: {e}")),
    }
}

fn charset(name: &str) -> Result<AsciiCharset, String> {
    match name {
        "unicode" => Ok(AsciiCharset::Unicode),
        "ascii" => Ok(AsciiCharset::Ascii),
        other => Err(format!("unknown charset {other:?}")),
    }
}

fn direction(name: &str) -> Result<AsciiDirection, String> {
    match name {
        "left_right" => Ok(AsciiDirection::LeftRight),
        "top_down" => Ok(AsciiDirection::TopDown),
        other => Err(format!("unknown default_direction {other:?}")),
    }
}

fn color_mode(name: &str) -> Result<AsciiColorMode, String> {
    match name {
        "plain" => Ok(AsciiColorMode::Plain),
        "auto" => Ok(AsciiColorMode::Auto),
        "ansi16" => Ok(AsciiColorMode::Ansi16),
        "ansi256" => Ok(AsciiColorMode::Ansi256),
        "true_color" => Ok(AsciiColorMode::TrueColor),
        "html" => Ok(AsciiColorMode::Html),
        other => Err(format!("unknown color_mode {other:?}")),
    }
}

fn color_theme(name: &str) -> Result<AsciiColorTheme, String> {
    match name {
        "light" => Ok(AsciiColorTheme::default_light()),
        "dark" => Ok(AsciiColorTheme::default_dark()),
        other => Err(format!("unknown color_theme {other:?}")),
    }
}

fn ascii_options(options: &AsciiOptions) -> Result<AsciiRenderOptions, String> {
    let mut ascii = AsciiRenderOptions::default();
    if let Some(value) = &options.charset {
        ascii.charset = charset(value)?;
    }
    if let Some(value) = &options.default_direction {
        ascii.default_direction = direction(value)?;
    }
    if let Some(value) = &options.color_mode {
        ascii.color_mode = color_mode(value)?;
    }
    if let Some(value) = &options.color_theme {
        ascii.color_theme = color_theme(value)?;
    }
    if let Some(value) = options.box_border_padding {
        ascii.box_border_padding = value;
    }
    if let Some(value) = options.graph_padding_x {
        ascii.graph_padding_x = value;
    }
    if let Some(value) = options.graph_padding_y {
        ascii.graph_padding_y = value;
    }
    if let Some(value) = options.sequence_participant_spacing {
        ascii.sequence_participant_spacing = value;
    }
    if let Some(value) = options.sequence_message_spacing {
        ascii.sequence_message_spacing = value;
    }
    if let Some(value) = options.sequence_self_message_width {
        ascii.sequence_self_message_width = value;
    }
    if let Some(value) = options.sequence_mirror_actors {
        ascii.sequence_mirror_actors = value;
    }
    if let Some(value) = options.xychart_vertical_plot_height {
        ascii.xychart_vertical_plot_height = value;
    }
    if let Some(value) = options.xychart_category_band_width {
        ascii.xychart_category_band_width = value;
    }
    if let Some(value) = options.xychart_horizontal_plot_width {
        ascii.xychart_horizontal_plot_width = value;
    }
    if let Some(value) = options.max_grid_cells {
        ascii.max_grid_cells = value;
    }
    if let Some(value) = options.relation_summary_diagnostics {
        ascii.relation_summary_diagnostics = value;
    }
    Ok(ascii)
}

fn svg_renderer(options: &Options) -> Result<HeadlessRenderer, String> {
    let mut renderer = HeadlessRenderer::new();
    if let Some(site_config) = &options.site_config {
        renderer = renderer.with_site_config(merman_config(site_config.clone()));
    }
    if let Some(diagram_id) = &options.diagram_id {
        renderer = renderer.with_diagram_id(diagram_id);
    }
    if options.deterministic_text_measurer {
        renderer = renderer.with_deterministic_text_measurer();
    }
    renderer = match options.strict_parsing {
        Some(true) => renderer.with_strict_parsing(),
        Some(false) => renderer.with_lenient_parsing(),
        None => renderer,
    };
    if let Some(today) = fixed_today(options)? {
        renderer = renderer.with_fixed_today(Some(today));
    }
    if let Some(offset) = options.fixed_local_offset_minutes {
        renderer = renderer.with_fixed_local_offset_minutes(Some(offset));
    }
    Ok(renderer)
}

fn ascii_renderer(options: &Options) -> Result<HeadlessAsciiRenderer, String> {
    let mut renderer = HeadlessAsciiRenderer::new();
    if let Some(site_config) = &options.site_config {
        renderer = renderer.with_site_config(merman_config(site_config.clone()));
    }
    renderer = match options.strict_parsing {
        Some(true) => renderer.with_strict_parsing(),
        Some(false) => renderer.with_lenient_parsing(),
        None => renderer,
    };
    if let Some(today) = fixed_today(options)? {
        renderer = renderer.with_fixed_today(Some(today));
    }
    if let Some(offset) = options.fixed_local_offset_minutes {
        renderer = renderer.with_fixed_local_offset_minutes(Some(offset));
    }
    Ok(renderer.with_ascii_options(ascii_options(&options.ascii)?))
}

fn merman_config(value: Value) -> merman::MermaidConfig {
    merman::MermaidConfig::from_value(value)
}

fn run_svg(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
    render: fn(&HeadlessRenderer, &str) -> merman::render::Result<Option<String>>,
) -> u32 {
    let input = match read_input(text_ptr, text_len, options_ptr, options_len) {
        Ok(input) => input,
        Err(message) => return error(message),
    };
    let renderer = match svg_renderer(&input.options) {
        Ok(renderer) => renderer,
        Err(message) => return error(message),
    };
    match render(&renderer, input.text) {
        Ok(Some(svg)) => ok(svg),
        Ok(None) => none(),
        Err(e) => error(e),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_render_svg(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    run_svg(
        text_ptr,
        text_len,
        options_ptr,
        options_len,
        HeadlessRenderer::render_svg_sync,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_render_svg_readable(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    run_svg(
        text_ptr,
        text_len,
        options_ptr,
        options_len,
        HeadlessRenderer::render_svg_readable_sync,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_render_svg_resvg_safe(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    run_svg(
        text_ptr,
        text_len,
        options_ptr,
        options_len,
        HeadlessRenderer::render_svg_resvg_safe_sync,
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_render_ascii(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    let input = match read_input(text_ptr, text_len, options_ptr, options_len) {
        Ok(input) => input,
        Err(message) => return error(message),
    };
    let renderer = match ascii_renderer(&input.options) {
        Ok(renderer) => renderer,
        Err(message) => return error(message),
    };
    match renderer.render_ascii_sync(input.text) {
        Ok(Some(text)) => ok(text),
        Ok(None) => none(),
        Err(e) => error(e),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_parse_metadata(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    let input = match read_input(text_ptr, text_len, options_ptr, options_len) {
        Ok(input) => input,
        Err(message) => return error(message),
    };
    let renderer = match svg_renderer(&input.options) {
        Ok(renderer) => renderer,
        Err(message) => return error(message),
    };
    match renderer.parse_metadata_sync(input.text) {
        Ok(Some(metadata)) => {
            let payload = json!({
                "diagram_type": metadata.diagram_type,
                "config": metadata.config.as_value(),
                "effective_config": metadata.effective_config.as_value(),
                "title": metadata.title,
            });
            ok(payload.to_string())
        }
        Ok(None) => none(),
        Err(e) => error(e),
    }
}
