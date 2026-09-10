//! The wasm ABI that the Ruby side of dewasm-merman calls.
//!
//! Every rendering entry point takes a UTF-8 diagram text and a UTF-8 options JSON document and returns a status: 0 for a result, 1 for "not a recognized diagram" (upstream `Ok(None)`, no payload), 2 for an error whose message is the payload.
//! The options JSON mirrors merman's request model: operation-level fields at the top level, `svg` for `SvgRequest`, and `ascii` for `AsciiRequest` with its `options`, `resources`, and `viewport` parts.
//! `merman_diagram_types` takes nothing and returns the diagram type table rows as JSON.
//! The payload is read back with `merman_result_ptr` and `merman_result_len`.

use std::cell::RefCell;

use merman::ascii::{
    AsciiCharset, AsciiColorMode, AsciiColorTheme, AsciiDirection, AsciiLayoutProfile,
    AsciiRenderOptions, AsciiResourceLimitId, AsciiResourcePolicy, AsciiTrimPolicy,
    AsciiViewportPolicy, OverflowPolicy, TerminalWidthProfile,
};
use merman::resources::ResourceProfile;
use merman::runtime::RuntimePolicy;
use merman::svg::SvgPipeline;
use merman::time::CivilDate;
use merman::{
    AsciiRequest, Engine, OperationControl, ParseOptions, RenderOutput, RenderRequest, Renderer,
    SvgRequest,
};
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
    site_config: Option<Value>,
    parse_options: Option<String>,
    fixed_today: Option<String>,
    fixed_local_offset_minutes: Option<i32>,
    svg: SvgOptions,
    ascii: AsciiRequestOptions,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct SvgOptions {
    pipeline: Option<String>,
    diagram_id: Option<String>,
    viewbox_padding: Option<f64>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AsciiRequestOptions {
    options: AsciiOptions,
    resources: ResourceOptions,
    viewport: ViewportOptions,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct AsciiOptions {
    charset: Option<String>,
    terminal_width_profile: Option<String>,
    layout_profile: Option<String>,
    default_direction: Option<String>,
    color_mode: Option<String>,
    color_theme: Option<String>,
    box_border_padding: Option<usize>,
    graph_padding_x: Option<usize>,
    graph_padding_y: Option<usize>,
    flowchart_node_label_wrap_width: Option<usize>,
    sequence_participant_spacing: Option<usize>,
    sequence_message_spacing: Option<usize>,
    sequence_self_message_width: Option<usize>,
    sequence_mirror_actors: Option<bool>,
    xychart_vertical_plot_height: Option<usize>,
    xychart_category_band_width: Option<usize>,
    xychart_horizontal_plot_width: Option<usize>,
    relation_summary_diagnostics: Option<bool>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ResourceOptions {
    profile: Option<String>,
    max_grid_cells: Option<usize>,
    max_layout_work_units: Option<usize>,
    max_document_cells: Option<usize>,
    max_output_bytes: Option<usize>,
    max_grapheme_bytes: Option<usize>,
    max_nesting_depth: Option<usize>,
}

#[derive(Default, Deserialize)]
#[serde(default, deny_unknown_fields)]
struct ViewportOptions {
    max_width: Option<usize>,
    overflow: Option<String>,
    trim: Option<String>,
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

/// Returns `None` when neither fixed-time option is set.
///
/// The default runtime policy is the deterministic policy the engine already uses, so the returned policy differs from the default only in what the caller asked for.
fn runtime_policy(options: &Options) -> Result<Option<RuntimePolicy>, String> {
    if options.fixed_today.is_none() && options.fixed_local_offset_minutes.is_none() {
        return Ok(None);
    }
    let mut policy = RuntimePolicy::default();
    if let Some(offset) = options.fixed_local_offset_minutes {
        policy = policy
            .try_with_fixed_local_offset_minutes(offset)
            .map_err(|e| format!("invalid fixed_local_offset_minutes {offset}: {e}"))?;
    }
    if let Some(raw) = &options.fixed_today {
        let today = raw
            .parse::<CivilDate>()
            .map_err(|e| format!("invalid fixed_today {raw:?}: {e}"))?;
        policy = policy.with_fixed_today(Some(today));
    }
    Ok(Some(policy))
}

fn pipeline(name: &str) -> Result<SvgPipeline, String> {
    match name {
        "parity" => Ok(SvgPipeline::parity()),
        "readable" => Ok(SvgPipeline::readable()),
        "resvg_safe" => Ok(SvgPipeline::resvg_safe()),
        other => Err(format!("unknown pipeline {other:?}")),
    }
}

fn parse_options(name: &str) -> Result<ParseOptions, String> {
    match name {
        "strict" => Ok(ParseOptions::strict()),
        "lenient" => Ok(ParseOptions::lenient()),
        other => Err(format!("unknown parse_options {other:?}")),
    }
}

fn charset(name: &str) -> Result<AsciiCharset, String> {
    match name {
        "unicode" => Ok(AsciiCharset::Unicode),
        "ascii" => Ok(AsciiCharset::Ascii),
        other => Err(format!("unknown charset {other:?}")),
    }
}

fn terminal_width_profile(name: &str) -> Result<TerminalWidthProfile, String> {
    match name {
        "unicode" => Ok(TerminalWidthProfile::Unicode),
        "cjk" => Ok(TerminalWidthProfile::Cjk),
        other => Err(format!("unknown terminal_width_profile {other:?}")),
    }
}

fn layout_profile(name: &str) -> Result<AsciiLayoutProfile, String> {
    match name {
        "canonical" => Ok(AsciiLayoutProfile::Canonical),
        "compact" => Ok(AsciiLayoutProfile::Compact),
        other => Err(format!("unknown layout_profile {other:?}")),
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

fn resource_profile(name: &str) -> Result<ResourceProfile, String> {
    match name {
        "interactive" => Ok(ResourceProfile::Interactive),
        "constrained" => Ok(ResourceProfile::Constrained),
        "trusted_native" => Ok(ResourceProfile::TrustedNative),
        "unbounded_for_trusted_input" => Ok(ResourceProfile::UnboundedForTrustedInput),
        other => Err(format!("unknown resources profile {other:?}")),
    }
}

fn overflow(name: &str) -> Result<OverflowPolicy, String> {
    match name {
        "allow" => Ok(OverflowPolicy::Allow),
        "fallback" => Ok(OverflowPolicy::Fallback),
        "error" => Ok(OverflowPolicy::Error),
        other => Err(format!("unknown viewport overflow {other:?}")),
    }
}

fn trim(name: &str) -> Result<AsciiTrimPolicy, String> {
    match name {
        "preserve" => Ok(AsciiTrimPolicy::Preserve),
        "trim_trailing_spaces" => Ok(AsciiTrimPolicy::TrimTrailingSpaces),
        other => Err(format!("unknown viewport trim {other:?}")),
    }
}

fn ascii_options(options: &AsciiOptions) -> Result<AsciiRenderOptions, String> {
    let mut ascii = AsciiRenderOptions::default();
    if let Some(value) = &options.charset {
        ascii.charset = charset(value)?;
    }
    if let Some(value) = &options.terminal_width_profile {
        ascii.terminal_width_profile = terminal_width_profile(value)?;
    }
    if let Some(value) = &options.layout_profile {
        ascii.layout_profile = layout_profile(value)?;
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
    if let Some(value) = options.flowchart_node_label_wrap_width {
        ascii.flowchart_node_label_wrap_width = value;
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
    if let Some(value) = options.relation_summary_diagnostics {
        ascii.relation_summary_diagnostics = value;
    }
    Ok(ascii)
}

fn resource_policy(options: &ResourceOptions) -> Result<AsciiResourcePolicy, String> {
    let mut policy = AsciiResourcePolicy::default();
    if let Some(name) = &options.profile {
        policy = policy.with_profile(resource_profile(name)?);
    }
    let limits = [
        (AsciiResourceLimitId::MaxGridCells, options.max_grid_cells),
        (
            AsciiResourceLimitId::MaxLayoutWorkUnits,
            options.max_layout_work_units,
        ),
        (
            AsciiResourceLimitId::MaxDocumentCells,
            options.max_document_cells,
        ),
        (
            AsciiResourceLimitId::MaxOutputBytes,
            options.max_output_bytes,
        ),
        (
            AsciiResourceLimitId::MaxGraphemeBytes,
            options.max_grapheme_bytes,
        ),
        (
            AsciiResourceLimitId::MaxNestingDepth,
            options.max_nesting_depth,
        ),
    ];
    for (id, value) in limits {
        if let Some(value) = value {
            policy = policy
                .with_limit(id, value)
                .map_err(|e| format!("invalid resources {} {value}: {e}", id.as_str()))?;
        }
    }
    Ok(policy)
}

fn viewport_policy(options: &ViewportOptions) -> Result<AsciiViewportPolicy, String> {
    let mut viewport = AsciiViewportPolicy::default();
    viewport.max_width = options.max_width;
    if let Some(name) = &options.overflow {
        viewport.overflow = overflow(name)?;
    }
    if let Some(name) = &options.trim {
        viewport.trim = trim(name)?;
    }
    Ok(viewport)
}

fn ascii_request(options: &AsciiRequestOptions) -> Result<AsciiRequest, String> {
    Ok(AsciiRequest {
        options: ascii_options(&options.options)?,
        resources: resource_policy(&options.resources)?,
        viewport: viewport_policy(&options.viewport)?,
    })
}

fn engine(options: &Options) -> Result<Engine, String> {
    let mut engine = Engine::new();
    if let Some(site_config) = &options.site_config {
        engine = engine.with_site_config(merman_config(site_config.clone()));
    }
    if let Some(policy) = runtime_policy(options)? {
        engine = engine.with_runtime_policy(policy);
    }
    Ok(engine)
}

fn renderer(options: &Options) -> Result<Renderer, String> {
    let mut renderer = Renderer::new().with_engine(engine(options)?);
    if let Some(name) = &options.parse_options {
        renderer = renderer.with_parse_options(parse_options(name)?);
    }
    Ok(renderer)
}

fn merman_config(value: Value) -> merman::MermaidConfig {
    merman::MermaidConfig::from_value(value)
}

fn svg_request(options: &Options) -> Result<SvgRequest, String> {
    let mut request = SvgRequest::default();
    request.options.diagram_id = options.svg.diagram_id.clone();
    if let Some(value) = options.svg.viewbox_padding {
        request.options.viewbox_padding = value;
    }
    // An absent pipeline stays merman's `None` default: even the empty parity preset costs two
    // forbidden-character scans and a well-formedness validation over the whole SVG per render.
    if let Some(name) = &options.svg.pipeline {
        request.pipeline = Some(pipeline(name)?);
    }
    Ok(request)
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_render_svg(
    text_ptr: *const u8,
    text_len: u32,
    options_ptr: *const u8,
    options_len: u32,
) -> u32 {
    let input = match read_input(text_ptr, text_len, options_ptr, options_len) {
        Ok(input) => input,
        Err(message) => return error(message),
    };
    let renderer = match renderer(&input.options) {
        Ok(renderer) => renderer,
        Err(message) => return error(message),
    };
    let request = match svg_request(&input.options) {
        Ok(request) => request,
        Err(message) => return error(message),
    };
    match renderer.render(RenderRequest::svg(
        input.text,
        OperationControl::new(),
        request,
    )) {
        Ok(RenderOutput::Svg(Some(output))) => ok(output.into_parts().0),
        // An SVG request only produces `RenderOutput::Svg`; `None` is "not a recognized diagram".
        Ok(_) => none(),
        Err(e) => error(e),
    }
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
    let renderer = match renderer(&input.options) {
        Ok(renderer) => renderer,
        Err(message) => return error(message),
    };
    let request = match ascii_request(&input.options.ascii) {
        Ok(request) => request,
        Err(message) => return error(message),
    };
    match renderer.render(RenderRequest::ascii(
        input.text,
        OperationControl::new(),
        request,
    )) {
        Ok(RenderOutput::Ascii(Some(output))) => ok(output.into_text()),
        // An ASCII request only produces `RenderOutput::Ascii`; `None` is "not a recognized diagram".
        Ok(_) => none(),
        Err(e) => error(e),
    }
}

/// Declares the rows of the README's diagram type table: each row lists the header keywords a diagram text can open with.
///
/// The generated `diagram_type_row` match has no wildcard, so a merman update that adds a diagram type stops this build until the type gets a row here, a sample in `tools/diagram_types.rb`, and a regenerated README table.
macro_rules! diagram_type_table {
    ($($variant:ident => [$($header:literal),+]),+ $(,)?) => {
        static DIAGRAM_TYPE_ROWS: &[&[&str]] = &[$(&[$($header),+]),+];

        #[expect(dead_code, reason = "the exhaustive match is the completeness check")]
        fn diagram_type_row(model: &merman::RenderSemanticModel) -> &'static [&'static str] {
            use merman::RenderSemanticModel as Model;
            match model {
                // Error and CustomJson are merman-internal render paths, not diagram types a user writes.
                Model::Error(_) | Model::CustomJson(_) => &[],
                $(Model::$variant(_) => &[$($header),+]),+
            }
        }
    };
}

diagram_type_table! {
    Architecture => ["architecture-beta"],
    Block => ["block-beta"],
    C4 => ["C4Context", "C4Container", "C4Component", "C4Dynamic", "C4Deployment"],
    Class => ["classDiagram"],
    Cynefin => ["cynefin-beta"],
    Er => ["erDiagram"],
    EventModeling => ["eventmodeling"],
    Flowchart => ["flowchart"],
    Gantt => ["gantt"],
    GitGraph => ["gitGraph"],
    Info => ["info"],
    Ishikawa => ["ishikawa-beta"],
    Journey => ["journey"],
    Kanban => ["kanban"],
    Mindmap => ["mindmap"],
    Packet => ["packet-beta"],
    Pie => ["pie"],
    QuadrantChart => ["quadrantChart"],
    Radar => ["radar-beta"],
    Railroad => ["railroad-beta", "railroad-ebnf-beta", "railroad-abnf-beta", "railroad-peg-beta"],
    Requirement => ["requirementDiagram"],
    Sankey => ["sankey-beta"],
    Sequence => ["sequenceDiagram"],
    State => ["stateDiagram-v2"],
    Timeline => ["timeline"],
    Treemap => ["treemap-beta"],
    TreeView => ["treeView-beta"],
    Venn => ["venn-beta"],
    Wardley => ["wardley-beta"],
    XyChart => ["xychart-beta"],
    Zenuml => ["zenuml"],
}

#[unsafe(no_mangle)]
pub extern "C" fn merman_diagram_types() -> u32 {
    match serde_json::to_string(DIAGRAM_TYPE_ROWS) {
        Ok(json) => ok(json),
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
    let engine = match engine(&input.options) {
        Ok(engine) => engine,
        Err(message) => return error(message),
    };
    // merman makes undetectable text an error here, so this entry point has no "no diagram" status to report.
    match engine.parse_metadata_sync(input.text) {
        Ok(metadata) => {
            let payload = json!({
                "diagram_type": metadata.diagram_type,
                "config": metadata.config.as_value(),
                "effective_config": metadata.effective_config.as_value(),
                "title": metadata.title,
            });
            ok(payload.to_string())
        }
        Err(e) => error(e),
    }
}
