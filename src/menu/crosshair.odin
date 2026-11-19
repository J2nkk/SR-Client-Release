package menu

import "core:fmt"
import "core:math"
import "core:strings"
import clay "../third_party/clay"

Crosshair_Type :: enum { PRECISION, IMAGE }
Crosshair_Control :: enum { OPACITY, SHADOW, THICKNESS, SIZE, GAP, IMAGE_WIDTH, IMAGE_HEIGHT }
Crosshair_Toggle :: enum { CUSTOM_OPACITY, ALWAYS_SHOW, DOT }
Crosshair_Settings :: struct {
	kind: Crosshair_Type,
	values: [Crosshair_Control]f32,
	toggles: [Crosshair_Toggle]bool,
	color, shadow_color: u32,
	// Image crosshair: a web link (like Krunker's crosshairImage) or a file path.
	image_url: string,
}
DEFAULT_CROSSHAIR_SETTINGS :: Crosshair_Settings{
	values={.OPACITY=1, .SHADOW=1, .THICKNESS=2, .SIZE=16, .GAP=0, .IMAGE_WIDTH=32, .IMAGE_HEIGHT=32},
	toggles={.CUSTOM_OPACITY=false, .ALWAYS_SHOW=false, .DOT=true}, color=0xffffff,
}
CROSSHAIR_IMAGE_URL_MAX :: 4096
// Official desktop Precision ranges (5fHFc).
CROSSHAIR_LIMITS := [Crosshair_Control][2]f32{.OPACITY={0,1}, .SHADOW={0,3}, .THICKNESS={0,100}, .SIZE={0,100}, .GAP={-100,100}, .IMAGE_WIDTH={1,512}, .IMAGE_HEIGHT={1,512}}
// Krunker steps thickness/length by 0.5 and gap by 1 over 0-100 / ±100 ranges,
// which puts the usual values (thickness 1-4, size 5-20) in a few percent of
// the bar. SR Client keeps the ranges but uses finer steps and curved sliders.
CROSSHAIR_STEPS := [Crosshair_Control]f32{.OPACITY=0.1, .SHADOW=0.1, .THICKNESS=0.1, .SIZE=0.1, .GAP=0.5, .IMAGE_WIDTH=1, .IMAGE_HEIGHT=1}
CROSSHAIR_CURVES := [Crosshair_Control]f32{.OPACITY=1, .SHADOW=1, .THICKNESS=2, .SIZE=2, .GAP=2, .IMAGE_WIDTH=2, .IMAGE_HEIGHT=2}
CROSSHAIR_LABELS := [Crosshair_Control]string{.OPACITY="Custom opacity", .SHADOW="Shadow thickness", .THICKNESS="Thickness", .SIZE="Size", .GAP="Gap", .IMAGE_WIDTH="Image width", .IMAGE_HEIGHT="Image height"}
CROSSHAIR_IDS := [Crosshair_Control]string{.OPACITY="CrosshairOpacity", .SHADOW="CrosshairShadow", .THICKNESS="CrosshairThickness", .SIZE="CrosshairSize", .GAP="CrosshairGap", .IMAGE_WIDTH="CrosshairImageWidth", .IMAGE_HEIGHT="CrosshairImageHeight"}

crosshair_settings_validate :: proc(settings: Crosshair_Settings) -> Crosshair_Settings {
	if settings == (Crosshair_Settings{}) { return DEFAULT_CROSSHAIR_SETTINGS }
	result := settings
	defaults := DEFAULT_CROSSHAIR_SETTINGS
	if result.kind != .IMAGE { result.kind = .PRECISION }
	if len(result.image_url) > CROSSHAIR_IMAGE_URL_MAX { result.image_url = "" }
	for control in Crosshair_Control {
		value := result.values[control]
		if math.is_nan(value) || math.is_inf(value) { value = defaults.values[control] }
		// Settings saved before image crosshairs existed have no image size.
		if (control == .IMAGE_WIDTH || control == .IMAGE_HEIGHT) && value <= 0 { value = defaults.values[control] }
		result.values[control] = clamp(value, CROSSHAIR_LIMITS[control][0], CROSSHAIR_LIMITS[control][1])
	}
	result.color &= 0xffffff
	result.shadow_color &= 0xffffff
	return result
}

// Rectangles relative to the center, shared by the HUD and menu preview.
// The official helper scales thickness/length by 19/10 and adds 3 to gap.
crosshair_geometry :: proc(settings: Crosshair_Settings) -> (boxes: [5]clay.BoundingBox, count: int) {
	t := settings.values[.THICKNESS]*1.9
	l := settings.values[.SIZE]*1.9
	g := t*0.5 + settings.values[.GAP] + 3
	if t <= 0 { return }
	if settings.toggles[.DOT] { boxes[count] = {-t*0.5, -t*0.5, t, t}; count += 1 }
	if l <= 0 { return }
	boxes[count] = {-t*0.5, -g-l, t, l}; count += 1
	boxes[count] = {-t*0.5, g, t, l}; count += 1
	boxes[count] = {-g-l, -t*0.5, l, t}; count += 1
	boxes[count] = {g, -t*0.5, l, t}; count += 1
	return
}

crosshair_opacity :: proc(settings: Crosshair_Settings, normal_opacity: f32) -> f32 {
	if settings.toggles[.CUSTOM_OPACITY] { return settings.values[.OPACITY] }
	if settings.toggles[.ALWAYS_SHOW] { return 1 }
	return clamp(normal_opacity, 0, 1)
}

Crosshair_Preview :: struct { settings: Crosshair_Settings, hitmarker: Hitmarker_Settings, scale: f32 }
settings_crosshair_preview :: proc(state: ^State) {
	s := state.scale
	state.crosshair_preview = {state.settings_draft.crosshair, state.settings_draft.hitmarker, s}
	if clay.UI()({layout={sizing={width=clay.SizingGrow()}, layoutDirection=.TopToBottom, padding={left=u16(24*s), right=u16(24*s)}, childGap=u16(8*s)}}) {
		// One line: the sidebar is too narrow for a longer label, which wrapped
		// under the preview box.
		text("Crosshair preview", 16, s, SETTINGS_MUTED)
		// Clay emits a custom command before an element's own background.
		// Keep the background on a parent so it cannot cover the reticle.
		if clay.UI()({layout={sizing={width=clay.SizingGrow(), height=clay.SizingFixed(124*s)}}, backgroundColor={65,75,82,255}, cornerRadius=clay.CornerRadiusAll(4*s)}) {
			if clay.UI(clay.ID("CrosshairPreview"))({layout={sizing={width=clay.SizingGrow(), height=clay.SizingGrow()}}, custom={customData=&state.crosshair_preview}}) {}
		}
	}
}

settings_crosshair :: proc(state: ^State) {
	s := state.scale
	settings_section(state, "Crosshair")
	if settings_search_show(state, "Crosshair type") {
		if clay.UI(clay.ID("CrosshairTypeRow"))(settings_row(state)) {
			settings_label("Type", s)
			spacer()
			settings_dropdown_field(state, state.settings_draft.crosshair.kind == .IMAGE ? "Image" : "Precision", "CrosshairType", .CROSSHAIR_TYPE)
		}
	}
	image := state.settings_draft.crosshair.kind == .IMAGE
	if image { settings_crosshair_image_row(state) }
	settings_toggle_row(state, "Use custom opacity", "CrosshairCustomOpacity", state.settings_draft.crosshair.toggles[.CUSTOM_OPACITY], {kind=.CROSSHAIR_TOGGLE, index=i32(Crosshair_Toggle.CUSTOM_OPACITY)})
	settings_slider(state, CROSSHAIR_LABELS[.OPACITY], CROSSHAIR_IDS[.OPACITY], state.settings_draft.crosshair.values[.OPACITY], 0, 1, {kind=.CROSSHAIR_VALUE, index=i32(Crosshair_Control.OPACITY)}, step=0.1)
	settings_toggle_row(state, "Always show", "CrosshairAlways", state.settings_draft.crosshair.toggles[.ALWAYS_SHOW], {kind=.CROSSHAIR_TOGGLE, index=i32(Crosshair_Toggle.ALWAYS_SHOW)})
	if !image {
		settings_crosshair_color(state, "Color", 1)
		settings_crosshair_color(state, "Shadow color", 2)
	}
	for control in Crosshair_Control {
		if control == .OPACITY { continue }
		if image != (control == .IMAGE_WIDTH || control == .IMAGE_HEIGHT) { continue }
		settings_slider(state, CROSSHAIR_LABELS[control], CROSSHAIR_IDS[control], state.settings_draft.crosshair.values[control], CROSSHAIR_LIMITS[control][0], CROSSHAIR_LIMITS[control][1], {kind=.CROSSHAIR_VALUE, index=i32(control)}, step=CROSSHAIR_STEPS[control], curve=CROSSHAIR_CURVES[control])
	}
	if !image { settings_toggle_row(state, "Dot", "CrosshairDot", state.settings_draft.crosshair.toggles[.DOT], {kind=.CROSSHAIR_TOGGLE, index=i32(Crosshair_Toggle.DOT)}) }
	note := "Always show keeps the crosshair when aiming. Custom opacity overrides its normal fade. Click a color to type or paste #RRGGBB."
	if image { note = "Copy an image link (for example right-click > Copy Link on Discord), then press Paste link. A file path to a PNG or JPG on your PC also works. Saved links load from the internet once and are then kept offline." }
	settings_note(state, state.color_invalid ? "Enter a six-digit color such as #00FF00. Escape discards the color edit." : note)
}

settings_crosshair_image_row :: proc(state: ^State) {
	if !settings_search_show(state, "Crosshair image") { return }
	s := state.scale
	url := state.settings_draft.crosshair.image_url
	if clay.UI(clay.ID("CrosshairImageRow"))(settings_row(state)) {
		settings_label("Image link", s)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childAlignment = {y = .Center}}}) {
			text(len(url) > 0 ? shorten(url, 34) : "No image set", 16, s, SETTINGS_MUTED)
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(150*s)}}}) { settings_button(state, "Paste link", "CrosshairImagePaste", {kind = .CROSSHAIR_IMAGE_PASTE}) }
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(110*s)}}}) { settings_button(state, "Clear", "CrosshairImageClear", {kind = .CROSSHAIR_IMAGE_CLEAR}, enabled = len(url) > 0) }
	}
}

settings_crosshair_color :: proc(state: ^State, label: string, field: i32) {
	if !settings_search_show(state, label) { return }
	s := state.scale
	id := clay.ID("CrosshairColor", u32(field))
	target := settings_color_value(&state.settings_draft, field)
	if target == nil { return }
	value := settings_color_shown(state.settings_draft, field, target^)
	editing := state.color_edit == field
	if clay.UI(clay.ID("CrosshairColorRow", u32(field)))(settings_row(state)) {
		settings_label(label, s)
		spacer()
		register(state, {id=id, action={kind=.CROSSHAIR_COLOR, index=field}, enabled=true})
		if clay.UI(id)({
			layout={sizing={width=clay.SizingFixed(360*s), height=clay.SizingFixed(48*s)}, padding={left=u16(12*s), right=u16(12*s)}, childGap=u16(16*s), childAlignment={y=.Center}},
			backgroundColor=editing && state.color_replace ? SETTINGS_ORANGE : clay.Color{231,229,235,255}, cornerRadius=clay.CornerRadiusAll(4*s),
			border={color=editing && state.color_invalid ? clay.Color{255,70,70,255} : state.focus == id.id ? WHITE : SETTINGS_LINE, width=clay.BorderOutside(editing || state.focus == id.id ? 2 : 1)},
		}) {
			if clay.UI()({layout={sizing={width=clay.SizingFixed(28*s), height=clay.SizingFixed(28*s)}}, backgroundColor={f32((value>>16)&255),f32((value>>8)&255),f32(value&255),255}, border={color=SETTINGS_LINE, width=clay.BorderOutside(1)}}) {}
			text(editing ? fmt.tprintf("%s|", string(state.color_buffer[:state.color_length])) : fmt.tprintf("#%06X", value), 20, s, SETTINGS_DARK)
		}
	}
}

crosshair_parse_color :: proc(text: string) -> (value: u32, ok: bool) {
	hex := strings.trim_space(text)
	if len(hex)>0 && hex[0]=='#' { hex = hex[1:] }
	if len(hex)!=6 { return }
	for c in hex {
		digit: u32
		if c>='0' && c<='9' { digit=u32(c-'0') } else if c>='a' && c<='f' { digit=u32(c-'a'+10) } else if c>='A' && c<='F' { digit=u32(c-'A'+10) } else { return 0, false }
		value = value*16+digit
	}
	return value, true
}

// The draft color an edit field names: 1 crosshair, 2 crosshair shadow, then
// HITMARKER_COLOR_FIELDS or DAMAGE_COLOR_FIELDS. Unknown fields are nil.
HEALTH_COLOR_FIELD_TEAM :: 8
HEALTH_COLOR_FIELD_ENEMY :: 9
HEALTH_COLOR_FIELD_HUD_HIGH :: 10
HEALTH_COLOR_FIELD_HUD_LOW :: 11

// The colour a field shows: health colours left at 0 show SR's own colour.
settings_color_shown :: proc(values: Settings_Values, field: i32, raw: u32) -> u32 {
	colors := health_colors(values.hud)
	switch field {
	case HEALTH_COLOR_FIELD_TEAM: return colors.team
	case HEALTH_COLOR_FIELD_ENEMY: return colors.enemy
	case HEALTH_COLOR_FIELD_HUD_HIGH: return colors.hud_high
	case HEALTH_COLOR_FIELD_HUD_LOW: return colors.hud_low
	}
	return raw
}

settings_color_value :: proc(values: ^Settings_Values, field: i32) -> ^u32 {
	switch field {
	case 1: return &values.crosshair.color
	case 2: return &values.crosshair.shadow_color
	case HEALTH_COLOR_FIELD_TEAM: return &values.hud.health_color_team
	case HEALTH_COLOR_FIELD_ENEMY: return &values.hud.health_color_enemy
	case HEALTH_COLOR_FIELD_HUD_HIGH: return &values.hud.hud_health_high
	case HEALTH_COLOR_FIELD_HUD_LOW: return &values.hud.hud_health_low
	}
	for color in Hitmarker_Color { if HITMARKER_COLOR_FIELDS[color] == field { return &values.hitmarker.colors[color] } }
	for color in Damage_Color { if DAMAGE_COLOR_FIELDS[color] == field { return &values.damage.colors[color] } }
	return nil
}

settings_color_begin :: proc(state: ^State, field: i32) {
	target := settings_color_value(&state.settings_draft, field)
	if target == nil { return }
	state.color_edit, state.color_invalid, state.color_replace = field, false, true
	state.color_length = copy(state.color_buffer[:], transmute([]u8)fmt.tprintf("#%06X", settings_color_shown(state.settings_draft, field, target^)))
	state.pressed = 0
}

settings_color_commit :: proc(state: ^State) -> bool {
	value, ok := crosshair_parse_color(string(state.color_buffer[:state.color_length]))
	if !ok { state.color_invalid = true; return false }
	// Health colours store 0 for "SR's own colour", so black is kept as 0x000001.
	if state.color_edit >= HEALTH_COLOR_FIELD_TEAM && state.color_edit <= HEALTH_COLOR_FIELD_HUD_LOW && value == 0 { value = 0x000001 }
	if target := settings_color_value(&state.settings_draft, state.color_edit); target != nil { target^ = value }
	state.color_edit, state.color_invalid = 0, false
	return true
}

settings_color_interact :: proc(state: ^State, input: Input) -> bool {
	if input.escape && !state.previous.escape { state.color_edit, state.color_invalid, state.pressed = 0, false, 0; return true }
	if input.clear_text { state.color_replace = true }
	if input.backspace && !state.previous.backspace {
		state.color_length = state.color_replace ? 0 : max(0, state.color_length-1)
		state.color_replace, state.color_invalid = false, false
	}
	for char in input.text {
		if char<32 || char>=127 || char=='`' { continue }
		if state.color_replace { state.color_length, state.color_replace = 0, false }
		if state.color_length<len(state.color_buffer) {
			state.color_buffer[state.color_length] = u8(char); state.color_length += 1
			state.color_invalid = false
		}
	}
	if input.enter && !state.previous.enter { settings_color_commit(state); return true }
	if input.tab && !state.previous.tab || input.down && !state.previous.down && !clay.PointerOver(clay.ID("CrosshairColor", u32(state.color_edit))) { return !settings_color_commit(state) }
	return true
}
