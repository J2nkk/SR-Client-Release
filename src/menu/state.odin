package menu

import "core:fmt"
import "core:math"
import "base:runtime"
import clay "../third_party/clay"

Page :: enum { HOME, SETTINGS, CONTROLS, SESSION, CLASSES, LOADOUT, HOST, ACCOUNT }
Lobby_Presentation :: enum { STANDARD, COMPETITIVE }
// The client owns clipboard access and session changes. The menu emits actions
// and renders requested selections separately from confirmed lobby state.
Action_Kind :: enum { NONE, PLAY, QUIT, JOIN_LINK, LOGIN, CANCEL_JOIN, FORGET_BROWSER_SESSION, PASTE, COPY_INVITE, LEAVE_SESSION, LOCAL_PRACTICE, SELECT_TEAM, SELECT_CLASS, SELECT_SECONDARY, INSPECT_CLASS, EDIT_INVITE, DISPLAY_MODE, RESOLUTION, SENSITIVITY, FPS, AUDIO_VOLUME, SETTINGS_TAB, SETTINGS_SAVE, SETTINGS_CANCEL, BIND_KEY, UNBIND_KEY, HUD_TOGGLE, VSYNC, MONITOR, SETTINGS_DROPDOWN, RESOLUTION_SELECT, VISUAL_VALUE, VISUAL_TOGGLE, VISUAL_RESET, TEXTURE_FILTER, ANISOTROPY, QUALITY_TOGGLE, LIGHTING, SHADOW_QUALITY, SETTINGS_NUMBER, FOV, ADVANCED_SENSITIVITY, INVERT_MOUSE, VIEWMODEL_VALUE, VIEWMODEL_TOGGLE, TRAILS_TOGGLE, CROSSHAIR_TYPE, CROSSHAIR_VALUE, CROSSHAIR_TOGGLE, CROSSHAIR_COLOR, SETTINGS_IMPORT_OPEN, SETTINGS_IMPORT, SETTINGS_EXPORT, SETTINGS_RESET_OPEN, SETTINGS_RESET, SETTINGS_RESET_CLOSE, SETTINGS_SEARCH, MENU_FPS_LIMIT, NIGHT_STRENGTH, KILL_FEED_LIMIT, HITMARKER_VALUE, HITMARKER_TOGGLE, DAMAGE_VALUE, DAMAGE_TOGGLE, MODS_BROWSE, MODS_REMOVE, MODS_PASTE, CROSSHAIR_IMAGE_PASTE, CROSSHAIR_IMAGE_CLEAR, HUD_SCALE, GAME_FPS_LIMIT, IMPORT_PART, FPS_UPDATE_RATE, HOST_GAME, REFRESH, HITMARKER_IMAGE_PASTE, HITMARKER_IMAGE_CLEAR, HOST_TAB, HOST_MAP, HOST_VALUE, HOST_TOGGLE, HOST_TEAM_SIZE, HOST_CLASS_LIMIT, HOST_TEXT, HOST_CLOSE, HOST_START, DEFAULT_REGION, GRAPHICS_API, MSAA, VRR_CAP, INPUT_RATE, OBJECTIVE_OPACITY, SCOPE_VALUE, NET_MODE, LOGIN_SEND_CODE, LOGIN_CODE, LOGIN_FIELD, LOGIN_PASSWORD }
Action :: struct { kind: Action_Kind, index: i32, value: f32 }
// Krunker's tabs (General, Controls, Display, Render, Game, Sound) plus SR's
// own Experimental tab. The enum names predate the Krunker layout.
Settings_Tab :: enum { MAIN, INPUT, VIDEO, VISUALS, GAMEPLAY, AUDIO, EXPERIMENTAL }
Settings_Dropdown :: enum { NONE, DISPLAY_MODE, MONITOR, RESOLUTION, TEXTURE_FILTER, ANISOTROPY, CROSSHAIR_TYPE, MENU_FPS_LIMIT, LIGHTING, SHADOW_QUALITY, GAME_FPS_LIMIT, DEFAULT_REGION, MSAA, VRR_CAP, INPUT_RATE, NET_MODE }
// Stored as "hide" flags so settings files without a key keep the item shown;
// hide_ping inverts Krunker's showPing (default true) so the zero value matches.
// hide_kill_feed inverts Krunker's showKills; kill_feed_limit is feedLimit
// (1..10, default 8), with 0 (a file without the key) meaning the default.
HUD_Settings :: struct {
	hide_timer, hide_round_score, hide_game_score, hide_ping, hide_nametags, hide_healthbars: bool,
	hide_kill_feed: bool,
	kill_feed_limit: i32,
	// SR Client comp HUD. Off-by-default features use positive names so older
	// settings files (missing keys = false) keep the defaults.
	manual_respawn: bool,     // false = respawn automatically when allowed
	hide_enemy_counter: bool, // enemies-on-point counter
	hide_leaderboard: bool,   // Krunker's leaderboard, top right
	hide_chat: bool,          // chat and kill lines, bottom left
	// Settings > Experimental (kept here so it saves with the HUD flags).
	network_thread: bool,     // read the network on its own thread
	input_clock: bool,        // pre-0.51 Dev toggle, replaced by net_mode; kept so old files load
	net_mode: i32,            // Dev: how inputs go out, NET_MODE_LABELS; 0 (older files) = default (fixed clock)
	input_rate: i32,          // real inputs per second, one of INPUT_RATES; 0 (older files) = 360
	hud_scale: f32,           // pre-0.13 HUD size; replaced by ui_scale, kept so old files load
	// Krunker's UI Scale (scaleUI, 0.1..1, default 0.7); 0 (older files) = default.
	ui_scale: f32,
	ui_scaling_off: bool,     // Krunker's uiScaling off: the UI at 1:1 pixels
	classic_font: bool,       // the menu font in the HUD instead of Krunker's
	fps_limit: i32,           // in-game frame cap, GAME_FPS_LIMITS; 0 = unlimited
	vrr_cap: i32,             // VRR_CAP_LABELS: 0 Auto (default), 1 Always, 2 Off
	hide_hud: bool,           // Krunker's Hide UI: crosshair and hitmarker only
	hide_bullet_holes: bool,
	// Pre-0.26 on/off anti-aliasing (4x); migrated to Quality_Settings.msaa
	// when an older settings file loads (client_settings_load).
	anti_alias: bool,
	// Krunker's showKillC / showDeaths: the kill and death counters under the
	// leaderboard (shown by default, as in 0.17).
	hide_kill_counter, hide_death_counter: bool,
	// Krunker's fpsRate: how often the FPS counter updates, in ms; 0 = 250.
	fps_update_ms: i32,
	// Krunker's healthColT / healthColE (nametag health bars) and hudHealthHigh /
	// hudHealthLow (your own health bar). 0 = SR Client's own colour.
	health_color_team, health_color_enemy, hud_health_high, hud_health_low: u32,
	// Krunker's defaultRegion (Settings > General > Localization): an index
	// into KRUNKER_REGIONS plus one; 0 (older files) = Frankfurt. Host uses it.
	default_region: i32,
	// Krunker's objOpac / adsObjOpac (Settings > Interface): the hardpoint
	// marker's opacity, and while aiming down sights near it. Tenths plus
	// one, so 0 (older files) is Krunker's default (1 and 0.5).
	objective_opacity, ads_objective_opacity: i32,
	// Krunker's scope settings (Settings > Mods > Scope): scopeOpac (the
	// scope image), scopeBorders.display / scopeBorderOpac (the bars outside
	// it) and scopeWidth / scopeHeight (x100 px). Stored as tenths plus one,
	// 0 = default. SR's defaults hide the image and the borders: competitive
	// players turn them off in Krunker, leaving the plain zoomed view.
	scope_opacity, scope_border_opacity, scope_width, scope_height: i32,
	scope_borders: bool,
}
Krunker_Region :: struct { id, name: string }
// Krunker's Default Region list, in its order (ids as its settings save them).
KRUNKER_REGIONS := [?]Krunker_Region{
	{"de-fra", "Frankfurt"}, {"us-ca-sv", "Silicon Valley"}, {"au-syd", "Sydney"}, {"jb-hnd", "Tokyo"}, {"sgp", "Singapore"},
	{"us-nj", "New York"}, {"as-mb", "Mumbai"}, {"us-tx", "Dallas"}, {"brz", "Brazil"}, {"me-bhn", "Middle East"},
}
KRUNKER_REGION_LABELS := [len(KRUNKER_REGIONS)]string{"Frankfurt", "Silicon Valley", "Sydney", "Tokyo", "Singapore", "New York", "Mumbai", "Dallas", "Brazil", "Middle East"}
default_region :: proc(settings: HUD_Settings) -> Krunker_Region {
	return KRUNKER_REGIONS[clamp(settings.default_region - 1, 0, len(KRUNKER_REGIONS) - 1)]
}
OBJECTIVE_OPACITY_DEFAULT :: 1
ADS_OBJECTIVE_OPACITY_DEFAULT :: 0.5
// 0..1 in Krunker's 0.1 steps, stored as tenths plus one (0 = default).
objective_opacity_decode :: proc(stored: i32, fallback: f32) -> f32 {
	if stored <= 0 { return fallback }
	return f32(clamp(stored - 1, 0, 10))/10
}
objective_opacity_encode :: proc(value: f32) -> i32 {
	if value != value { return 0 } // NaN
	return i32(clamp(value, 0, 1)*10 + 0.5) + 1
}
objective_opacity :: proc(settings: HUD_Settings) -> f32 { return objective_opacity_decode(settings.objective_opacity, OBJECTIVE_OPACITY_DEFAULT) }
ads_objective_opacity :: proc(settings: HUD_Settings) -> f32 { return objective_opacity_decode(settings.ads_objective_opacity, ADS_OBJECTIVE_OPACITY_DEFAULT) }
SCOPE_OPACITY_DEFAULT :: 0 // SR: no scope image (Krunker's default is 1)
SCOPE_BORDER_OPACITY_DEFAULT :: 1
SCOPE_SIZE_DEFAULT :: 6.8 // Krunker scopeWidth/scopeHeight; the image is size*100 px
SCOPE_SIZE_MIN :: 0.1
SCOPE_SIZE_MAX :: 10
scope_tenths_decode :: proc(stored: i32, fallback, low, high: f32) -> f32 {
	if stored <= 0 { return fallback }
	return clamp(f32(stored - 1)/10, low, high)
}
scope_tenths_encode :: proc(value, low, high: f32) -> i32 {
	if value != value { return 0 } // NaN
	return i32(clamp(value, low, high)*10 + 0.5) + 1
}
// index 0 scopeOpac, 1 scopeBorderOpac, 2 scopeWidth, 3 scopeHeight.
scope_value :: proc(settings: HUD_Settings, index: int) -> f32 {
	switch index {
	case 0: return scope_tenths_decode(settings.scope_opacity, SCOPE_OPACITY_DEFAULT, 0, 1)
	case 1: return scope_tenths_decode(settings.scope_border_opacity, SCOPE_BORDER_OPACITY_DEFAULT, 0, 1)
	case 2: return scope_tenths_decode(settings.scope_width, SCOPE_SIZE_DEFAULT, SCOPE_SIZE_MIN, SCOPE_SIZE_MAX)
	case 3: return scope_tenths_decode(settings.scope_height, SCOPE_SIZE_DEFAULT, SCOPE_SIZE_MIN, SCOPE_SIZE_MAX)
	}
	return 0
}
scope_value_set :: proc(settings: ^HUD_Settings, index: int, value: f32) {
	switch index {
	case 0: settings.scope_opacity = scope_tenths_encode(value, 0, 1)
	case 1: settings.scope_border_opacity = scope_tenths_encode(value, 0, 1)
	case 2: settings.scope_width = scope_tenths_encode(value, SCOPE_SIZE_MIN, SCOPE_SIZE_MAX)
	case 3: settings.scope_height = scope_tenths_encode(value, SCOPE_SIZE_MIN, SCOPE_SIZE_MAX)
	}
}
FPS_UPDATE_DEFAULT_MS :: 250
FPS_UPDATE_MIN_MS :: 50 // Krunker allows 0 (every frame); SR keeps the HUD cache useful.
FPS_UPDATE_MAX_MS :: 1000
fps_update_ms :: proc(settings: HUD_Settings) -> i32 {
	if settings.fps_update_ms <= 0 { return FPS_UPDATE_DEFAULT_MS }
	return clamp(settings.fps_update_ms, FPS_UPDATE_MIN_MS, FPS_UPDATE_MAX_MS)
}
// SR Client's own colours (the 0.17 look) stand in for unset (0) values.
HEALTH_COLOR_TEAM_DEFAULT :: u32(0x9eeb56)
HEALTH_COLOR_ENEMY_DEFAULT :: u32(0xff4444)
HUD_HEALTH_HIGH_DEFAULT :: u32(0x009b00)
HUD_HEALTH_LOW_DEFAULT :: u32(0x009b00) // One colour at every health, as before.
Health_Colors :: struct { team, enemy, hud_high, hud_low: u32 }
health_colors :: proc(settings: HUD_Settings) -> Health_Colors {
	pick :: proc(value, fallback: u32) -> u32 { return value == 0 ? fallback : value & 0xffffff }
	return {
		team = pick(settings.health_color_team, HEALTH_COLOR_TEAM_DEFAULT),
		enemy = pick(settings.health_color_enemy, HEALTH_COLOR_ENEMY_DEFAULT),
		hud_high = pick(settings.hud_health_high, HUD_HEALTH_HIGH_DEFAULT),
		hud_low = pick(settings.hud_health_low, settings.hud_health_high != 0 ? settings.hud_health_high & 0xffffff : HUD_HEALTH_LOW_DEFAULT),
	}
}
// Glorp-style import choices: each part can be left out of an import.
Import_Part :: enum { KEYBINDS, SENSITIVITY, SOUND }
IMPORT_PART_LABELS := [Import_Part]string{.KEYBINDS = "Import Keybinds", .SENSITIVITY = "Import Sensitivity", .SOUND = "Import Sound"}
IMPORT_ALL_PARTS :: bit_set[Import_Part]{.KEYBINDS, .SENSITIVITY, .SOUND}
UI_SCALE_DEFAULT :: 0.7
UI_SCALE_MIN :: 0.1
UI_SCALE_MAX :: 1.0
ui_scale :: proc(settings: HUD_Settings) -> f32 {
	if settings.ui_scale <= 0 || settings.ui_scale != settings.ui_scale { return UI_SCALE_DEFAULT }
	// Krunker's slider steps by 0.1.
	return clamp(math.round(settings.ui_scale*10)/10, UI_SCALE_MIN, UI_SCALE_MAX)
}
// Krunker's scaleBase(): the UI is laid out on a 1700x900 page times
// (2 - scaleUI) and scaled to fit the window, so one CSS pixel of Krunker's
// HUD is this many window pixels. uiScaling off draws it at 1:1.
krunker_ui_factor :: proc(settings: HUD_Settings, width, height: f32) -> f32 {
	if settings.ui_scaling_off { return 1 }
	custom := 2 - ui_scale(settings)
	return min(width/(1700*custom), height/(900*custom))
}
// The menu was laid out for Krunker's default UI Scale; other values zoom it
// the way Krunker zooms its menus.
menu_ui_zoom :: proc(settings: HUD_Settings) -> f32 {
	if settings.ui_scaling_off { return 1 }
	// Never past the size that fits the window: SR's menus are laid out to fill
	// a 1600x900 page, so a larger UI Scale (up to Krunker's maximum 1) would push
	// buttons off screen. Smaller UI Scales still shrink the menus.
	return min(1, (2 - UI_SCALE_DEFAULT) / (2 - ui_scale(settings)))
}
KILL_FEED_DEFAULT_LIMIT :: 8
KILL_FEED_MAX_LIMIT :: 10
kill_feed_limit :: proc(settings: HUD_Settings) -> int {
	if settings.kill_feed_limit <= 0 { return KILL_FEED_DEFAULT_LIMIT }
	return int(min(settings.kill_feed_limit, KILL_FEED_MAX_LIMIT))
}
Settings_Values :: struct {
	display_mode, resolution_index, monitor_index: i32,
	fullscreen_index: i32, // Index into View.fullscreen_options.
	fov: f32,
	sensitivity, mouse_dpi: f32,
	ads_sensitivity: f32,
	advanced_sensitivity, invert_mouse: bool,
	audio_volumes: [4]f32,
	show_fps: bool,
	vsync: bool,
	vulkan: bool, // Graphics API: Vulkan, else OpenGL (applied at the next start)
	menu_fps_limit: i32, // See MENU_FPS_LIMITS.
	bindings: Bindings,
	hud: HUD_Settings,
	visuals: Visual_Settings,
	quality: Quality_Settings,
	viewmodel: Viewmodel_Settings,
	trails: Trail_Settings,
	crosshair: Crosshair_Settings,
	hitmarker: Hitmarker_Settings,
	damage: Damage_Settings,
}
Class :: struct { id: i32, name, weapon: string, health: i32, speed: f32, wall_jump, available: bool, reason: string, used, limit: int, portrait, weapon_icon: rawptr }
Secondary :: struct { id: i32, name: string, icon: rawptr }
Player :: struct { name, class_name: string, team: i32, is_you: bool }
Team :: struct { id: i32, name: string, capacity: int, available: bool, reason: string, score: u32 }
View :: struct {
	presentation: Lobby_Presentation,
	// SR Client mods: the loaded Krunker mod (from the last start) and the one
	// chosen since, which applies on the next start.
	mods_count, mods_problems: int,
	mods_active: string,
	mods_busy, mods_supported: bool,
	ranked, team_selection: bool,
	browser_access_supported, auth_pending: bool,
	// Signed in to Krunker (access ready), and a custom game being created.
	logged_in, hosting: bool,
	classes: []Class,
	selected_class: i32,
	secondaries: []Secondary,
	selected_secondary: i32,
	secondary_name, secondary_reason: string,
	secondary_pending: bool,
	live_class_changes: bool,
	respawn_remaining: f32,
	confirmed_class, confirmed_team, requested_team: i32,
	team_pending, class_pending, local_practice, has_life, connecting: bool,
	players: []Player,
	teams: [2]Team,
	play_reason, selection_status, lobby_name, match_status, current_invite: string,
	online, active, spawn_pending, ready: bool,
	map_name, mode, resolution: string,
	// Status is supplied by the client after a join attempt. The menu only
	// renders it; an empty value uses the default paste hint.
	join_status: string,
	player_count: int,
	display_mode: i32,
	resolution_index: i32,
	resolution_options: []string,
	// Exclusive fullscreen sizes for the selected monitor, largest first.
	fullscreen_index: i32,
	fullscreen_options: []string,
	monitor_index: i32,
	monitor_names: []string,
	vsync: bool,
	vulkan: bool,
	menu_fps_limit: i32,
	bindings: Bindings,
	hud: HUD_Settings,
	visuals: Visual_Settings,
	quality: Quality_Settings,
	viewmodel: Viewmodel_Settings,
	trails: Trail_Settings,
	crosshair: Crosshair_Settings,
	hitmarker: Hitmarker_Settings,
	damage: Damage_Settings,
	max_anisotropy: f32,
	max_msaa: i32, // highest MSAA sample count the GPU supports (1 = none)
	vrr_status: string, // VRR detection and cap, for Settings > Video
	fov: f32,
	sensitivity, mouse_dpi: f32,
	ads_sensitivity: f32,
	advanced_sensitivity, invert_mouse: bool,
	audio_volumes: [4]f32,
	show_fps: bool,
	// What Reset restores: the client's defaults for a missing settings file
	// (client_settings_defaults through client_settings_validate, plus the
	// audio defaults). Reset stays disabled while this is the zero value.
	settings_defaults: Settings_Values,
	// Host page: Krunker's map images and banner (nil until downloaded),
	// and whether Start Game can be pressed.
	host_maps: [HOST_MAP_COUNT]rawptr,
	host_banner: rawptr,
	host_can_start: bool,
}
Input :: struct {
	pointer: clay.Vector2,
	down, tab, shift, enter, escape, left, right: bool,
	backspace, clear_text, paste: bool,
	delete_key, right_down: bool, // Delete and the right mouse button unbind a key bind slot.
	text: string,
	scroll: clay.Vector2,
	up, down_key: bool,
	binding_pressed: i32,
	now: f64, // seconds, for double clicks
}
Control :: struct { id: clay.ElementId, action: Action, enabled, slider, number: bool, slider_min, slider_max, slider_step, slider_curve: f32 }
State :: struct {
	page: Page,
	ctx: ^clay.Context,
	memory: []u8,
	// Search results can list rows from every settings tab at once.
	controls: [256]Control,
	control_count: int,
	// Host game page (Krunker's Comp Server Setup).
	host: Host_Settings,
	host_tab: Host_Tab,
	// Invite field: the whole link is selected (double click or Ctrl+A); the
	// next key replaces it.
	invite_selected: bool,
	last_click_id: u32,
	last_click_time: f64,
	// Log out asks for a second click.
	logout_armed: bool,
	// Account window: Krunker login with an emailed code (login.odin).
	login_text: [Login_Field][LOGIN_TEXT_CAPACITY]u8,
	login_text_length: [Login_Field]int,
	login_code_sent: bool,
	focus, pressed: u32,
	return_focus: u32,
	loadout_parent: Page,
	loadout_return_focus: u32,
	invite_buffer: [2048]u8,
	invite_length: int,
	previous: Input,
	scale: f32,
	errors: int,
	settings_tab: Settings_Tab,
	settings_active: bool,
	scrollbar_dragging: bool,
	scrollbar_grab: f32,
	settings_draft: Settings_Values,
	settings_resolution_count, settings_fullscreen_count: i32,
	settings_resolution_selected: bool,
	binding_capture: i32, // action*2 + slot + 1; zero when not listening.
	binding_reserved: bool,
	settings_dropdown: Settings_Dropdown,
	dropdown_return_focus: u32,
	// The dropdown option last scrolled into view; 0 when the popup opens.
	dropdown_revealed_focus: u32,
	number_edit: Settings_Number,
	number_control: Control,
	number_buffer: [24]u8,
	number_length: int,
	number_replace, number_invalid, number_changed: bool,
	color_edit: i32, // 0 = none; otherwise a settings_color_value field.
	color_buffer: [16]u8,
	color_length: int,
	color_replace, color_invalid: bool,
	crosshair_preview: Crosshair_Preview,
	damage_preview: Damage_Preview,
	// Krunker's "Import Settings" popup. Krunker exports compact JSON; loadouts
	// can make it several kilobytes, so the field holds up to 64 KiB.
	import_open, import_overflow: bool,
	import_excluded: bit_set[Import_Part], // Parts switched off in the import popup.
	// Krunker's resetSettings asks confirm("settings.reset.confirm") first.
	reset_open: bool,
	settings_defaults: Settings_Values, // Copied from View every frame.
	import_buffer: [65536]u8,
	import_length: int,
	settings_message: [160]u8,
	settings_message_length: int,
	settings_message_error: bool,
	// Settings search text lasts for one visit to the menu and is never saved.
	search_buffer: [SEARCH_MAX]u8,
	search_length: int,
	// Per-frame bookkeeping while search results are laid out.
	search_tab: Settings_Tab,
	search_section: string,
	search_tab_pending, search_section_pending, search_tab_match, search_section_match, search_found: bool,
}

prepare_settings :: proc(state: ^State, view: View) {
	if state.page != .SETTINGS && state.page != .CONTROLS {
		state.settings_active = false
		state.scrollbar_dragging = false
		state.binding_capture, state.settings_dropdown = 0, .NONE
		state.number_edit = .NONE
		state.color_edit = 0
		settings_import_close(state)
		state.reset_open = false
		state.settings_message_length = 0
		state.search_length = 0
		return
	}
	state.settings_defaults = view.settings_defaults
	if !state.settings_active {
		state.settings_resolution_selected = false
		state.settings_draft = {display_mode = view.display_mode, resolution_index = view.resolution_index, fullscreen_index = view.fullscreen_index,
			fov = fov_validate(view.fov), sensitivity = view.sensitivity, mouse_dpi = mouse_dpi_validate(view.mouse_dpi), audio_volumes = view.audio_volumes, show_fps = view.show_fps,
			ads_sensitivity = ads_sensitivity_validate(view.ads_sensitivity, view.sensitivity, view.mouse_dpi), advanced_sensitivity = view.advanced_sensitivity, invert_mouse = view.invert_mouse,
			monitor_index = view.monitor_index, vsync = view.vsync, vulkan = view.vulkan, menu_fps_limit = menu_fps_limit_validate(view.menu_fps_limit), bindings = view.bindings, hud = view.hud, visuals = view.visuals, quality = view.quality,
			viewmodel = viewmodel_settings_validate(view.viewmodel), trails = view.trails, crosshair = crosshair_settings_validate(view.crosshair), hitmarker = hitmarker_settings_validate(view.hitmarker), damage = damage_settings_validate(view.damage)}
		state.settings_active = true
	}
	state.settings_resolution_count = i32(len(view.resolution_options))
	state.settings_fullscreen_count = i32(len(view.fullscreen_options))
	if state.page == .CONTROLS { state.settings_tab = .INPUT }
}

error_handler :: proc "c" (data: clay.ErrorData) {
	context = runtime.default_context()
	state := cast(^State)data.userData
	state.errors += 1
	fmt.eprintf("[Menu] %s\n", string(data.errorText.chars[:data.errorText.length]))
}

init :: proc(state: ^State, measure: proc "c" (clay.StringSlice, ^clay.TextElementConfig, rawptr) -> clay.Dimensions, user: rawptr) -> bool {
	clay.SetMaxElementCount(2048)
	clay.SetMaxMeasureTextCacheWordCount(4096)
	state.memory = make([]u8, int(clay.MinMemorySize()))
	arena := clay.CreateArenaWithCapacityAndMemory(uint(len(state.memory)), raw_data(state.memory))
	state.ctx = clay.Initialize(arena, {1280, 720}, {handler = error_handler, userData = state})
	clay.SetMeasureTextFunction(measure, user)
	return state.ctx != nil && state.errors == 0
}

fini :: proc(state: ^State) {
	if clay.GetCurrentContext() == state.ctx { clay.SetCurrentContext(nil) }
	delete(state.memory)
	state.memory = nil
	state.ctx = nil
}

contains :: proc(box: clay.BoundingBox, point: clay.Vector2) -> bool {
	return point[0] >= box.x && point[1] >= box.y && point[0] < box.x + box.width && point[1] < box.y + box.height
}

register :: proc(state: ^State, control: Control) {
	assert(state.control_count < len(state.controls))
	state.controls[state.control_count] = control
	state.control_count += 1
}

// Resolve interactions after layout, against this frame's actual rectangles.
// Pointer press captures a control; release activates it only over that control.
interact :: proc(state: ^State, input: Input, view: View) -> Action {
	clay.SetCurrentContext(state.ctx)
	clay.SetPointerState(input.pointer, input.down)
	defer state.previous = input
	if state.color_edit != 0 && settings_color_interact(state, input) { return {} }
	if state.import_open {
		if action, handled := settings_import_interact(state, input); handled { return action }
	}
	if state.reset_open && settings_reset_interact(state, input) { return {} }
	if state.number_edit != .NONE && settings_number_interact(state, input) { return {} }
	// Capture runs before menu shortcuts: Enter, Tab, arrows and mouse buttons
	// can all be rebound without activating another control behind the listener.
	if state.binding_capture != 0 {
		code := input.binding_pressed
		if input.escape && !state.previous.escape || code == 256 { state.binding_capture, state.binding_reserved = 0, false; return {} }
		if code == 0 { return {} }
		if code == 96 { state.binding_reserved = true; return {} }
		if code == 261 { code = 0 }
		if !binding_valid(code) { return {} }
		action := Binding_Action((state.binding_capture-1)/2)
		slot := (state.binding_capture-1)%2
		state.settings_draft.bindings[action][slot] = code
		if state.settings_draft.bindings[action][1-slot] == code { state.settings_draft.bindings[action][1-slot] = 0 }
		state.binding_capture, state.binding_reserved, state.pressed = 0, false, 0
		return {}
	}
	if state.settings_dropdown != .NONE {
		if input.escape && !state.previous.escape {
			state.settings_dropdown, state.focus = .NONE, state.dropdown_return_focus
			return {}
		}
		if input.down && !state.previous.down && !clay.PointerOver(clay.ID("SettingsOptions")) {
			state.settings_dropdown, state.focus, state.pressed = .NONE, state.dropdown_return_focus, 0
			return {}
		}
	}
	if settings_scrollbar_interact(state, input) { return {} }
	focused_index := -1
	for control, i in state.controls[:state.control_count] {
		if control.id.id == state.focus && control.enabled { focused_index = i }
	}
	// Outside capture, right-clicking a key bind slot, or pressing Delete or
	// Backspace while one is focused, unbinds it without opening the listener.
	if input.right_down && !state.previous.right_down {
		for control in state.controls[:state.control_count] {
			if control.action.kind != .BIND_KEY || !control.enabled { continue }
			data := clay.GetElementData(control.id)
			if data.found && contains(data.boundingBox, input.pointer) && clay.PointerOver(control.id) {
				state.focus, state.pressed = control.id.id, 0
				binding_unbind(state, control.action.index)
				return {kind = .UNBIND_KEY, index = control.action.index}
			}
		}
	}
	if focused_index >= 0 && state.controls[focused_index].action.kind == .BIND_KEY && (input.delete_key && !state.previous.delete_key || input.backspace && !state.previous.backspace) {
		binding_unbind(state, state.controls[focused_index].action.index)
		return {kind = .UNBIND_KEY, index = state.controls[focused_index].action.index}
	}
	// With text or focus in the search field, Escape clears the search and leaves
	// the field instead of closing Settings, as Escape only closes the import popup.
	if input.escape && !state.previous.escape && (state.page == .SETTINGS || state.page == .CONTROLS) && (state.search_length > 0 || settings_search_focused(state)) {
		settings_search_clear(state)
		state.pressed = 0
		if settings_search_focused(state) { state.focus = 0 }
		return {}
	}
	if input.escape && !state.previous.escape {
		state.pressed = 0
		if state.page == .SETTINGS || state.page == .CONTROLS {
			return activate(state, {action = {kind = .SETTINGS_CANCEL}})
		}
		if state.page != .HOME {
			state.page, state.focus = back_page(state), back_focus(state)
		} else if view.active {
			return {kind = .PLAY}
		}
		return {}
	}
	if settings_search_focused(state) { settings_search_input(state, input) }
	host_text_input(state, input)
	if action := login_text_input(state, input); action.kind != .NONE { return action }
	if state.focus == clay.ID("Invite").id {
		if input.paste && !state.previous.paste { return {kind = .PASTE} }
		if input.clear_text && state.invite_length > 0 { state.invite_selected = true }
		if input.backspace && !state.previous.backspace && state.invite_length > 0 {
			if state.invite_selected { state.invite_length = 0 } else { state.invite_length -= 1 }
			state.invite_selected = false
		}
		for c in input.text {
			// Backtick remains available for the client's map rotation shortcut.
			if c >= 32 && c < 127 && c != '`' {
				if state.invite_selected { state.invite_length, state.invite_selected = 0, false }
				if state.invite_length < len(state.invite_buffer) { state.invite_buffer[state.invite_length] = u8(c); state.invite_length += 1 }
			}
		}
		if input.enter && !state.previous.enter { return {kind = .JOIN_LINK} }
	}
	if input.tab && !state.previous.tab || state.settings_dropdown != .NONE && (input.up && !state.previous.up || input.down_key && !state.previous.down_key) {
		step := input.shift || input.up ? -1 : 1
		if focused_index < 0 { focused_index = input.shift ? 0 : -1 }
		for _ in 0 ..< state.control_count {
			focused_index = (focused_index + step + state.control_count) % state.control_count
			if state.controls[focused_index].enabled {
				state.focus = state.controls[focused_index].id.id
				focus_visible(state.controls[focused_index], state.page)
				break
			}
		}
	}
	if input.enter && !state.previous.enter && focused_index >= 0 {
		control := state.controls[focused_index]
		if !control.slider { return activate(state, control) }
	}
	if focused_index >= 0 && state.controls[focused_index].slider {
		direction := (input.right && !state.previous.right ? 1 : 0) - (input.left && !state.previous.left ? 1 : 0)
		if direction != 0 {
			control := state.controls[focused_index]
			value := settings_slider_value(state, view, control.action)
			action := control.action
			action.value = clamp(value + f32(direction) * control.slider_step, control.slider_min, control.slider_max)
			return activate(state, {action = action})
		}
	}
	for control in state.controls[:state.control_count] {
		if !control.enabled { continue }
		data := clay.GetElementData(control.id)
		over := data.found && contains(data.boundingBox, input.pointer) && clay.PointerOver(control.id)
		if input.down && !state.previous.down && over {
			// Double click on the invite selects the whole link.
			if control.id.id == clay.ID("Invite").id {
				state.invite_selected = state.last_click_id == control.id.id && input.now - state.last_click_time < 0.4 && state.invite_length > 0
			}
			state.last_click_id, state.last_click_time = control.id.id, input.now
			state.pressed = control.id.id
			state.focus = control.id.id
		}
		if state.pressed == control.id.id {
			if control.slider && input.down {
				progress := clamp((input.pointer[0] - data.boundingBox.x) / data.boundingBox.width, 0, 1)
				action := control.action
				action.value = slider_value_at(progress, control.slider_min, control.slider_max, control.slider_curve, control.slider_step)
				return activate(state, {action = action})
			}
			if !input.down && state.previous.down && over {
				state.pressed = 0
				if control.slider { return {} }
				return activate(state, control)
			}
		}
	}
	if !input.down { state.pressed = 0 }
	return {}
}

activate :: proc(state: ^State, control: Control) -> Action {
	if control.number {
		state.number_control = control
		settings_number_begin(state, .SLIDER)
		return {}
	}
	if state.page == .HOST {
		if action, handled := host_activate(state, control); handled { return action }
	}
	// Log out forgets the account and the browser profile: it asks twice.
	if control.action.kind == .FORGET_BROWSER_SESSION {
		state.pressed = 0
		if !state.logout_armed { state.logout_armed = true; return {} }
		state.logout_armed = false
		return control.action
	}
	state.logout_armed = false
	if control.action.kind == .CROSSHAIR_COLOR {
		settings_color_begin(state, control.action.index)
		return {}
	}
	if control.action.kind == .SETTINGS_NUMBER {
		settings_number_begin(state, Settings_Number(control.action.index))
		return {}
	}
	if control.action.kind == .BIND_KEY {
		state.binding_capture, state.binding_reserved = control.action.index+1, false
		state.pressed = 0
		return {}
	}
	if control.action.kind == .UNBIND_KEY {
		binding_unbind(state, control.action.index)
		state.pressed = 0
		// The X disables itself once the slot is empty; keep focus on the row.
		state.focus = clay.ID("Binding", u32(control.action.index)).id
		return control.action
	}
	if control.action.kind == .SETTINGS_DROPDOWN {
		state.settings_dropdown = Settings_Dropdown(control.action.index)
		data := clay.GetScrollContainerData(clay.ID("SettingsOptions"))
		if data.found { data.scrollPosition^ = {} }
		state.dropdown_revealed_focus = 0
		state.dropdown_return_focus = control.id.id
		index: i32
		switch state.settings_dropdown {
		case .NONE:
		case .DISPLAY_MODE: index = state.settings_draft.display_mode
		case .MONITOR: index = state.settings_draft.monitor_index
		case .RESOLUTION: index = state.settings_draft.display_mode == 2 ? state.settings_draft.fullscreen_index : state.settings_draft.resolution_index
		case .TEXTURE_FILTER: index = state.settings_draft.quality.smooth_textures ? 1 : 0
		case .LIGHTING: index = clamp(state.settings_draft.quality.lighting, 0, 3)
		case .SHADOW_QUALITY: index = clamp(state.settings_draft.quality.shadow_quality, 0, 1)
		case .CROSSHAIR_TYPE: index = state.settings_draft.crosshair.kind == .IMAGE ? 1 : 0
		case .ANISOTROPY:
			for value, i in ([5]i32{0, 2, 4, 8, 16}) { if value == state.settings_draft.quality.anisotropy { index = i32(i) } }
		case .MENU_FPS_LIMIT: index = menu_fps_limit_index(state.settings_draft.menu_fps_limit)
		case .GAME_FPS_LIMIT: index = game_fps_limit_index(state.settings_draft.hud.fps_limit)
		case .MSAA: index = msaa_index(state.settings_draft.quality.msaa)
		case .VRR_CAP: index = clamp(state.settings_draft.hud.vrr_cap, 0, len(VRR_CAP_LABELS) - 1)
		case .INPUT_RATE: index = input_rate_index(state.settings_draft.hud.input_rate)
		case .NET_MODE: index = net_mode_index(state.settings_draft.hud)
		case .DEFAULT_REGION: index = clamp(state.settings_draft.hud.default_region - 1, 0, len(KRUNKER_REGIONS) - 1)
		}
		state.focus = clay.ID("SettingsOption", u32(index)).id
		return {}
	}
	if control.action.kind == .SETTINGS_IMPORT_OPEN {
		state.import_open, state.import_length, state.import_overflow = true, 0, false
		state.import_excluded = {}
		state.settings_message_length, state.pressed = 0, 0
		state.focus = clay.ID("ImportConfirm").id
		return {}
	}
	if control.action.kind == .SETTINGS_RESET_OPEN {
		if !settings_reset_available(state) { return {} }
		state.reset_open, state.pressed, state.settings_message_length = true, 0, 0
		state.binding_capture, state.binding_reserved, state.settings_dropdown = 0, false, .NONE
		state.focus = clay.ID("ResetConfirm").id
		return {}
	}
	if control.action.kind == .SETTINGS_RESET_CLOSE {
		state.reset_open, state.pressed, state.focus = false, 0, clay.ID("SettingsReset").id
		return {}
	}
	if control.action.kind == .SETTINGS_RESET {
		state.reset_open, state.pressed, state.focus = false, 0, clay.ID("SettingsReset").id
		if !settings_reset_available(state) { return {} }
		if control.action.index == 1 {
			settings_reset_tab(&state.settings_draft, state.settings_defaults, state.settings_tab)
			settings_set_message(state, fmt.tprintf("%s reset to defaults. Save keeps them; Cancel restores your settings.", SETTINGS_TABS[state.settings_tab]), false)
		} else {
			// Reset all applies and saves at once: it must work even when a
			// broken setting (zoom, resolution) hides the Save button.
			state.settings_draft = state.settings_defaults
			state.page, state.focus, state.pressed = .HOME, state.return_focus, 0
			state.settings_active = false
			state.scrollbar_dragging = false
			state.binding_capture, state.settings_dropdown = 0, .NONE
			state.number_edit = .NONE
			state.color_edit, state.color_invalid = 0, false
			state.binding_reserved = false
			settings_import_close(state)
			state.settings_message_length = 0
			state.search_length = 0
			return {kind = .SETTINGS_SAVE}
		}
		return {}
	}
	if control.action.kind == .SETTINGS_IMPORT {
		state.pressed = 0
		if state.import_overflow { settings_set_message(state, "Settings text is too long.", true); return {} }
		result, error := krunker_settings_import(&state.settings_draft, string(state.import_buffer[:state.import_length]), IMPORT_ALL_PARTS - state.import_excluded)
		if len(error) > 0 { settings_set_message(state, error, true); return {} }
		settings_import_close(state)
		state.focus = clay.ID("SettingsImport").id
		message := fmt.tprintf("Imported %d Krunker settings.", result.imported)
		if result.ignored > 0 { message = fmt.tprintf("%s %d aren't in SR Client yet.", message, result.ignored) }
		if result.not_applicable > 0 { message = fmt.tprintf("%s %d don't apply (controller, voice chat, effects you have off).", message, result.not_applicable) }
		settings_set_message(state, message, false)
		return {kind = .SETTINGS_IMPORT} // The client applies and saves the draft, as Save does.
	}
	if control.action.kind == .IMPORT_PART {
		state.pressed = 0
		part := Import_Part(clamp(control.action.index, 0, len(Import_Part)-1))
		state.import_excluded ~= {part}
		return {}
	}
	if control.action.kind == .SETTINGS_SEARCH {
		state.pressed = 0
		return {} // Clicking the field focuses it; typing is handled in interact.
	}
	if control.action.kind == .SETTINGS_TAB {
		state.search_length = 0 // Krunker's changeTab clears the search field.
		state.settings_tab = Settings_Tab(control.action.index)
		state.scrollbar_dragging = false
		state.page = .SETTINGS
		state.pressed = 0
		data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
		if data.found { data.scrollPosition^ = {} }
		return {}
	}
	if control.action.kind == .SETTINGS_SAVE || control.action.kind == .SETTINGS_CANCEL {
		state.page, state.focus, state.pressed = .HOME, state.return_focus, 0
		state.settings_active = false
		state.scrollbar_dragging = false
		state.binding_capture, state.settings_dropdown = 0, .NONE
		state.number_edit = .NONE
		state.color_edit, state.color_invalid = 0, false
		state.binding_reserved = false
		settings_import_close(state)
		state.reset_open = false
		state.settings_message_length = 0
		state.search_length = 0
		return control.action if control.action.kind == .SETTINGS_SAVE else Action{}
	}
	if state.settings_active {
		if state.settings_dropdown != .NONE {
			state.settings_dropdown, state.focus = .NONE, state.dropdown_return_focus
		}
		#partial switch control.action.kind {
		case .DISPLAY_MODE: state.settings_draft.display_mode = control.action.index; return {}
		case .VISUAL_VALUE:
			if control.action.index >= 0 && control.action.index < i32(Visual_Control.FOG_DISTANCE) {
				state.settings_draft.visuals.values[Visual_Control(control.action.index)] = control.action.value
			}
			return {}
		case .VISUAL_TOGGLE:
			switch control.action.index {
			case 0: state.settings_draft.visuals.hide_cats = !state.settings_draft.visuals.hide_cats
			case 1: state.settings_draft.visuals.hide_extra_props = !state.settings_draft.visuals.hide_extra_props
			case 2: state.settings_draft.visuals.night_mode = !state.settings_draft.visuals.night_mode
			}
			return {}
		case .HUD_SCALE:
			if value := control.action.value; value == value { state.settings_draft.hud.ui_scale = clamp(value, UI_SCALE_MIN, UI_SCALE_MAX) }
			return {}
		case .OBJECTIVE_OPACITY:
			// index 0: objOpac, 1: adsObjOpac.
			if value := control.action.value; value == value {
				if control.action.index == 0 { state.settings_draft.hud.objective_opacity = objective_opacity_encode(value) }
				else { state.settings_draft.hud.ads_objective_opacity = objective_opacity_encode(value) }
			}
			return {}
		case .SCOPE_VALUE:
			if value := control.action.value; value == value { scope_value_set(&state.settings_draft.hud, int(control.action.index), value) }
			return {}
		case .FPS_UPDATE_RATE:
			if value := control.action.value; value == value { state.settings_draft.hud.fps_update_ms = i32(clamp(value + 0.5, FPS_UPDATE_MIN_MS, FPS_UPDATE_MAX_MS)) } // Skips NaN.
			return {}
		case .KILL_FEED_LIMIT:
			if value := control.action.value; value == value { state.settings_draft.hud.kill_feed_limit = i32(clamp(value + 0.5, 1, KILL_FEED_MAX_LIMIT)) } // Skips NaN.
			return {}
		case .NIGHT_STRENGTH:
			if value := control.action.value; value == value { state.settings_draft.visuals.night_strength = clamp(value, 0, 1) } // Skips NaN.
			return {}
		case .VISUAL_RESET:
			state.settings_draft.visuals = DEFAULT_VISUAL_SETTINGS
			return {}
		case .TEXTURE_FILTER: state.settings_draft.quality.smooth_textures = control.action.index == 1; return {}
		case .ANISOTROPY: state.settings_draft.quality.anisotropy = ANISOTROPY_LEVELS[clamp(control.action.index, 0, 4)]; return {}
		case .MSAA: state.settings_draft.quality.msaa = MSAA_LEVELS[clamp(control.action.index, 0, len(MSAA_LEVELS)-1)]; return {}
		case .VRR_CAP: state.settings_draft.hud.vrr_cap = clamp(control.action.index, 0, len(VRR_CAP_LABELS) - 1); return {}
		case .INPUT_RATE: state.settings_draft.hud.input_rate = INPUT_RATES[clamp(control.action.index, 0, len(INPUT_RATES) - 1)]; return {}
		case .NET_MODE: state.settings_draft.hud.net_mode = clamp(control.action.index, 0, len(NET_MODE_LABELS) - 1) + 1; return {}
		case .LIGHTING: state.settings_draft.quality.lighting = clamp(control.action.index, 0, 3); return {}
		case .SHADOW_QUALITY: state.settings_draft.quality.shadow_quality = clamp(control.action.index, 0, 1); return {}
		case .QUALITY_TOGGLE:
			quality := &state.settings_draft.quality
			switch Quality_Toggle(control.action.index) {
			case .SHADOWS: quality.shadows = !quality.shadows
			case .SOFT_SHADOWS: quality.soft_shadows = !quality.soft_shadows
			case .HIGH_RES_SHADOWS: quality.high_res_shadows = !quality.high_res_shadows
			case .DYNAMIC_SHADOWS: quality.dynamic_shadows = !quality.dynamic_shadows
			case .SELF_SHADOW: quality.self_shadow = !quality.self_shadow
			}
			return {}
		case .MONITOR: state.settings_draft.monitor_index = control.action.index; return {}
		case .RESOLUTION_SELECT:
			if state.settings_draft.display_mode == 2 {
				state.settings_draft.fullscreen_index = control.action.index
			} else {
				state.settings_draft.resolution_index = control.action.index
			}
			state.settings_resolution_selected = true
			return {}
		case .VSYNC: state.settings_draft.vsync = !state.settings_draft.vsync; return {}
		case .GRAPHICS_API: state.settings_draft.vulkan = !state.settings_draft.vulkan; return {}
		case .MENU_FPS_LIMIT: state.settings_draft.menu_fps_limit = MENU_FPS_LIMITS[clamp(control.action.index, 0, len(MENU_FPS_LIMITS)-1)]; return {}
		case .DEFAULT_REGION: state.settings_draft.hud.default_region = clamp(control.action.index, 0, len(KRUNKER_REGIONS) - 1) + 1; return {}
		case .GAME_FPS_LIMIT: state.settings_draft.hud.fps_limit = GAME_FPS_LIMITS[clamp(control.action.index, 0, len(GAME_FPS_LIMITS)-1)]; return {}
		case .HUD_TOGGLE:
			switch control.action.index {
			case 0: state.settings_draft.hud.hide_timer = !state.settings_draft.hud.hide_timer
			case 1: state.settings_draft.hud.hide_round_score = !state.settings_draft.hud.hide_round_score
			case 2: state.settings_draft.hud.hide_game_score = !state.settings_draft.hud.hide_game_score
			case 3: state.settings_draft.hud.hide_ping = !state.settings_draft.hud.hide_ping
			case 4: state.settings_draft.hud.hide_nametags = !state.settings_draft.hud.hide_nametags
			case 5: state.settings_draft.hud.hide_healthbars = !state.settings_draft.hud.hide_healthbars
			case 6: state.settings_draft.hud.hide_kill_feed = !state.settings_draft.hud.hide_kill_feed
			case 7: state.settings_draft.hud.manual_respawn = !state.settings_draft.hud.manual_respawn
			case 8: state.settings_draft.hud.hide_enemy_counter = !state.settings_draft.hud.hide_enemy_counter
			case 9: state.settings_draft.hud.hide_leaderboard = !state.settings_draft.hud.hide_leaderboard
			case 10: state.settings_draft.hud.hide_chat = !state.settings_draft.hud.hide_chat
			case 11: state.settings_draft.hud.network_thread = !state.settings_draft.hud.network_thread
			case 12: state.settings_draft.hud.classic_font = !state.settings_draft.hud.classic_font
			case 13: state.settings_draft.hud.hide_hud = !state.settings_draft.hud.hide_hud
			case 14: state.settings_draft.hud.hide_bullet_holes = !state.settings_draft.hud.hide_bullet_holes
			case 16: state.settings_draft.hud.ui_scaling_off = !state.settings_draft.hud.ui_scaling_off
			case 17: state.settings_draft.hud.hide_kill_counter = !state.settings_draft.hud.hide_kill_counter
			case 18: state.settings_draft.hud.hide_death_counter = !state.settings_draft.hud.hide_death_counter
			case 19: state.settings_draft.hud.scope_borders = !state.settings_draft.hud.scope_borders
			case 20: state.settings_draft.hud.input_clock = !state.settings_draft.hud.input_clock
			}
			return {}
		case .RESOLUTION:
			fullscreen := state.settings_draft.display_mode == 2
			count := fullscreen ? state.settings_fullscreen_count : state.settings_resolution_count
			index := fullscreen ? &state.settings_draft.fullscreen_index : &state.settings_draft.resolution_index
			if count > 0 {
				index^ = (index^ + control.action.index + count) % count
				state.settings_resolution_selected = true
			}
			return {}
		case .SENSITIVITY: state.settings_draft.sensitivity = control.action.value; return {}
		case .ADVANCED_SENSITIVITY: state.settings_draft.advanced_sensitivity = !state.settings_draft.advanced_sensitivity; return {}
		case .INVERT_MOUSE: state.settings_draft.invert_mouse = !state.settings_draft.invert_mouse; return {}
		case .FOV: state.settings_draft.fov = fov_validate(control.action.value); return {}
		case .VIEWMODEL_VALUE:
			if control.action.index >= 0 && control.action.index < i32(len(Viewmodel_Control)) {
				state.settings_draft.viewmodel.values[Viewmodel_Control(control.action.index)] = control.action.value
				state.settings_draft.viewmodel = viewmodel_settings_validate(state.settings_draft.viewmodel)
			}
			return {}
		case .VIEWMODEL_TOGGLE:
			if control.action.index >= 0 && control.action.index < i32(len(Viewmodel_Toggle)) {
				toggle := Viewmodel_Toggle(control.action.index)
				state.settings_draft.viewmodel.toggles[toggle] = !state.settings_draft.viewmodel.toggles[toggle]
			}
			return {}
		case .TRAILS_TOGGLE:
			if control.action.index == 0 { state.settings_draft.trails.hide_others = !state.settings_draft.trails.hide_others }
			if control.action.index == 1 { state.settings_draft.trails.hide_yours = !state.settings_draft.trails.hide_yours }
			return {}
		case .CROSSHAIR_TYPE:
			state.settings_draft.crosshair.kind = control.action.index == 1 ? .IMAGE : .PRECISION
			return {}
		case .CROSSHAIR_IMAGE_CLEAR:
			state.settings_draft.crosshair.image_url = ""
			return {}
		case .CROSSHAIR_VALUE:
			if control.action.index >= 0 && control.action.index < i32(len(Crosshair_Control)) {
				state.settings_draft.crosshair.values[Crosshair_Control(control.action.index)] = control.action.value
				state.settings_draft.crosshair = crosshair_settings_validate(state.settings_draft.crosshair)
			}
			return {}
		case .CROSSHAIR_TOGGLE:
			if control.action.index >= 0 && control.action.index < i32(len(Crosshair_Toggle)) {
				toggle := Crosshair_Toggle(control.action.index)
				state.settings_draft.crosshair.toggles[toggle] = !state.settings_draft.crosshair.toggles[toggle]
			}
			return {}
		case .HITMARKER_VALUE:
			if control.action.index >= 0 && control.action.index < i32(len(Hitmarker_Control)) {
				state.settings_draft.hitmarker.values[Hitmarker_Control(control.action.index)] = control.action.value
				state.settings_draft.hitmarker = hitmarker_settings_validate(state.settings_draft.hitmarker)
			}
			return {}
		case .HITMARKER_TOGGLE: state.settings_draft.hitmarker.show = !state.settings_draft.hitmarker.show; return {}
		case .HITMARKER_IMAGE_CLEAR: state.settings_draft.hitmarker.image_url = ""; return {}
		case .DAMAGE_VALUE:
			if control.action.index >= 0 && control.action.index < i32(len(Damage_Control)) {
				state.settings_draft.damage.values[Damage_Control(control.action.index)] = control.action.value
				state.settings_draft.damage = damage_settings_validate(state.settings_draft.damage)
			}
			return {}
		case .DAMAGE_TOGGLE:
			if control.action.index >= 0 && control.action.index < i32(len(Damage_Toggle)) {
				toggle := Damage_Toggle(control.action.index)
				state.settings_draft.damage.toggles[toggle] = !state.settings_draft.damage.toggles[toggle]
			}
			return {}
		case .AUDIO_VOLUME: state.settings_draft.audio_volumes[control.action.index] = control.action.value; return {}
		case .FPS: state.settings_draft.show_fps = !state.settings_draft.show_fps; return {}
		}
	}
	if control.action.kind == .INSPECT_CLASS || control.action.kind == .EDIT_INVITE || control.action.kind == .LOGIN_FIELD { return {} }
	// Navigation changes the menu page without dispatching a gameplay action.
	if control.action.kind == .NONE {
		previous_page := state.page
		if state.page == .HOME { state.return_focus = control.id.id }
		state.page = Page(control.action.index)
		state.focus = state.page == .HOME ? state.return_focus : previous_page == .LOADOUT && state.page == state.loadout_parent ? state.loadout_return_focus : 0
		return {}
	}
	return control.action
}

// Clears one key bind slot (index = action*2 + slot) in the settings draft.
// Zero is unbound: it never reads as held, saves as 0 and exports to Krunker as -1.
binding_unbind :: proc(state: ^State, index: i32) {
	if index < 0 || index >= i32(len(Binding_Action))*2 { return }
	state.settings_draft.bindings[Binding_Action(index/2)][index%2] = 0
	state.binding_capture, state.binding_reserved = 0, false
}

back_page :: proc(state: ^State) -> Page {
	if state.page == .LOADOUT { return state.loadout_parent }
	if state.page == .CONTROLS { return .SETTINGS }
	return .HOME
}

back_focus :: proc(state: ^State) -> u32 {
	return state.page == .LOADOUT ? state.loadout_return_focus : state.return_focus
}

focus_visible :: proc(control: Control, page: Page) {
	container: string
	if control.action.kind == .SELECT_CLASS || control.action.kind == .INSPECT_CLASS {
		if page == .HOME { container = "ClassStrip" }
		if page == .CLASSES { container = "ClassPicker" }
	}
	if page == .HOST { container = "SettingsPanel" }
	if (page == .SETTINGS || page == .CONTROLS) && (control.slider || control.number || control.action.kind == .SETTINGS_DROPDOWN || control.action.kind == .SETTINGS_NUMBER || control.action.kind == .BIND_KEY || control.action.kind == .UNBIND_KEY || control.action.kind == .HUD_TOGGLE || control.action.kind == .VSYNC || control.action.kind == .FPS || control.action.kind == .VISUAL_RESET || control.action.kind == .VISUAL_TOGGLE || control.action.kind == .QUALITY_TOGGLE || control.action.kind == .ADVANCED_SENSITIVITY || control.action.kind == .INVERT_MOUSE || control.action.kind == .VIEWMODEL_TOGGLE || control.action.kind == .TRAILS_TOGGLE || control.action.kind == .CROSSHAIR_TOGGLE || control.action.kind == .CROSSHAIR_COLOR || control.action.kind == .HITMARKER_TOGGLE || control.action.kind == .DAMAGE_TOGGLE || control.action.kind == .MODS_BROWSE || control.action.kind == .MODS_REMOVE || control.action.kind == .MODS_PASTE || control.action.kind == .CROSSHAIR_IMAGE_PASTE || control.action.kind == .CROSSHAIR_IMAGE_CLEAR || control.action.kind == .HITMARKER_IMAGE_PASTE || control.action.kind == .HITMARKER_IMAGE_CLEAR || control.action.kind == .GRAPHICS_API) { container = "SettingsPanel" }
	if control.action.kind == .DISPLAY_MODE || control.action.kind == .MONITOR || control.action.kind == .RESOLUTION_SELECT || control.action.kind == .TEXTURE_FILTER || control.action.kind == .ANISOTROPY || control.action.kind == .MSAA || control.action.kind == .VRR_CAP || control.action.kind == .INPUT_RATE || control.action.kind == .NET_MODE || control.action.kind == .MENU_FPS_LIMIT || control.action.kind == .GAME_FPS_LIMIT || control.action.kind == .DEFAULT_REGION || control.action.kind == .LIGHTING || control.action.kind == .SHADOW_QUALITY { container = "SettingsOptions" }
	if control.action.kind == .SELECT_SECONDARY { container = "SecondaryPicker" }
	if len(container) == 0 { return }
	data := clay.GetScrollContainerData(clay.ID(container))
	if !data.found { return }
	parent := clay.GetElementData(clay.ID(container)).boundingBox
	box := clay.GetElementData(control.id).boundingBox
	if container == "ClassStrip" {
		offset: f32
		if box.x < parent.x { offset = parent.x - box.x }
		if box.x + box.width > parent.x + parent.width { offset = parent.x + parent.width - box.x - box.width }
		data.scrollPosition[0] = clamp(data.scrollPosition[0] + offset, min(0, data.scrollContainerDimensions.width - data.contentDimensions.width), 0)
		return
	}
	offset: f32
	if box.y < parent.y { offset = parent.y - box.y }
	if box.y + box.height > parent.y + parent.height { offset = parent.y + parent.height - box.y - box.height }
	data.scrollPosition[1] = clamp(data.scrollPosition[1] + offset, min(0, data.scrollContainerDimensions.height - data.contentDimensions.height), 0)
}

invite :: proc(state: ^State) -> string { return string(state.invite_buffer[:state.invite_length]) }
set_invite :: proc(state: ^State, value: string) {
	state.invite_length = min(len(value), len(state.invite_buffer))
	copy(state.invite_buffer[:state.invite_length], transmute([]u8)value[:state.invite_length])
}

// Settings > Experimental > Inputs per second (real inputs, not the browser's
// Network Rate number: the browser sends once half its interval has passed, so
// its Network Rate 360 is up to 720 inputs a second at high FPS). 1000 is the
// protocol's limit: input durations are whole milliseconds, at least 1.
INPUT_RATES := [7]i32{120, 240, 360, 480, 720, 840, 1000}
INPUT_RATE_LABELS := [7]string{"120", "240", "360 (default)", "480", "720 (= Krunker 360)", "840", "1000"}
INPUT_RATE_DEFAULT :: 360

input_rate_index :: proc(rate: i32) -> i32 {
	for value, i in INPUT_RATES { if value == rate { return i32(i) } }
	return 2 // 0 (older files) or a removed choice (900): 360
}

input_rate_value :: proc(rate: i32) -> i32 { return INPUT_RATES[input_rate_index(rate)] }

// Dev build: one choice for how inputs reach the server (hud.net_mode, 1-based; 0 = default).
NET_MODE_LABELS := [3]string{"Fixed clock (default)", "Network thread", "Off"}

net_mode_index :: proc(hud: HUD_Settings) -> i32 {
	if hud.net_mode >= 1 && hud.net_mode <= len(NET_MODE_LABELS) { return hud.net_mode - 1 }
	return 0
}

// Whether the network thread runs: Dev uses net_mode (fixed clock needs the thread too),
// the normal build its Network thread toggle.
hud_network_thread :: proc(hud: HUD_Settings) -> bool {
	when SR_DEV { return net_mode_index(hud) <= 1 }
	return hud.network_thread
}

// Whether inputs are built and sent on the fixed clock (Dev build only).
hud_input_clock :: proc(hud: HUD_Settings) -> bool {
	when SR_DEV { return net_mode_index(hud) == 0 }
	return false
}
