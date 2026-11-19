package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
import "core:thread"
import "core:time"
import "core:slice"
import "core:encoding/json"
import "core:strconv"
import "core:strings"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import stbi "vendor:stb/image"
import shared "../shared"
import kproto "../krunker"
import menuui "../menu"
import clay "../third_party/clay"

Display_Mode :: enum {
	Windowed,
	Borderless,
	Fullscreen,
}

Display_Resolution :: struct {
	width, height: i32,
}

DISPLAY_RESOLUTIONS := [?]Display_Resolution{
	{1280, 720},
	{1600, 900},
	{1920, 1080},
	{2560, 1440},
}

Client :: struct {
	window: glfw.WindowHandle,
	camera: Camera,
	scene:  ^Scene,
	fps_scene: ^Scene,
	ui:     ^UI,
	audio: ^Audio_System,
	audio_settings: Audio_Settings,
	audio_settings_dirty: bool,
	audio_save_delay: f32,
	bindings: menuui.Bindings,
	binding_event: i32,
	// Krunker's wheel "key" (bind code 20000): latched by a wheel notch while
	// the cursor is locked and released once a gameplay command has read it.
	scroll_press: bool,
	scroll_press_time: f64, // GetTime of the last latched press (50 ms throttle).
	hud_settings: menuui.HUD_Settings,
	kill_feed: Kill_Feed,
	visual_settings: menuui.Visual_Settings,
	quality_settings: menuui.Quality_Settings,
	viewmodel_settings: menuui.Viewmodel_Settings,
	trail_settings: menuui.Trail_Settings,
	crosshair_settings: menuui.Crosshair_Settings,
	hitmarker_settings: menuui.Hitmarker_Settings,
	hit_marker: Hit_Marker,
	damage_settings: menuui.Damage_Settings,
	damage_feedback: Damage_Feedback,
	aim_pressed, aim_toggled: bool,
	inspect_pressed: bool,
	scoreboard_open: bool,
	end_screen_active, end_screen_dismissed: bool,
	// The match ended and the lobby closed (host ended the game): its final
	// scoreboard stays up until Escape, then SR returns to a fresh start screen.
	end_hold, krunker_was_connected: bool,
	backspace_since, backspace_repeat: f64,
	last_refresh_key: bool,
	end_screen_started: f64,
	inspect_weapon: ^shared.Weapon,
	inspect_slot: i32,
	inspect_angle, inspect_time: f32,
	graphics_sampler: Gpu_Sampler,
	graphics_sampler_ready: bool,
	graphics_quality: menuui.Quality_Settings,
	max_anisotropy: f32,
	max_msaa: i32, // gpu_max_msaa_samples
	// VRR (vrr.odin): what is known about the window's monitor, re-detected
	// when the window moves to another monitor or monitors change.
	vrr: Vrr_Info,
	vrr_monitor: glfw.MonitorHandle,
	vrr_adapt: Vrr_Adapt,
	vrr_check_frame: int,
	msaa: struct { target: Gpu_Render_Target, samples, width, height: i32 }, // client_msaa_begin
	bench_seconds: f32, // Benchmark mode only.
	// Static map batching and frustum culling (map_batch.odin). On by default;
	// `--no-batching` turns it off for A/B comparisons.
	render_batching: bool,
	// The startup self-test (map_batch_self_test.odin) has compared batched and
	// per-object rendering this session.
	batch_self_test_done: bool,
	render_target: Gpu_Render_Target, // Target of the world pass; 0 (the window) except in benchmark mode.
	settings_dirty, vsync: bool,
	opengl: bool, // Settings > Video > Vulkan Renderer off: OpenGL from the next start.
	menu_fps_limit: i32, // menuui.MENU_FPS_LIMITS: 0 = monitor refresh, -1 = unlimited.
	idle_frame_deadline: f64, // The last paced frame's target end; 0 while uncapped.
	monitor_index: i32,
	monitor_cache: Monitor_Cache,
	monitor_cache_refreshes: int, // Diagnostics: glfw.GetVideoModes enumerations.

	mouse_state: struct {
		locked:  bool,
		last_pos: shared.Vec2,
	},

	windowed_rect: struct {
		x, y, width, height: i32,
	},

	last_noclip_key:   bool,
	last_debug_key:    bool,
	last_freecam_key:  bool,
	last_fullscreen_key: bool,
	last_escape_key:   bool,
	last_swap_key:     u8,
	in_game:           bool,
	spawn_pending:     bool,
	spawn_retry_timer: f32,
	selected_class:    i32,
	selected_secondary: i32,
	local_practice: bool,
	has_life: bool,
	lobby_team: i32,
	requested_team: i32,
	team_pending: bool,
	team_request_time: f64,
	selection_status: string,
	menu_text: [128]u8,
	menu_text_length: int,
	join_queued: int,
	access: Client_Access,
	menu:             menuui.State,
	menu_scroll:      clay.Vector2,
	display_mode:      Display_Mode,
	resolution_index:  i32,
	// Exclusive fullscreen video mode; zero means the monitor's largest mode.
	fullscreen_resolution: Display_Resolution,
	sensitivity:       f32,
	mouse_dpi:         f32,
	ads_sensitivity:   f32,
	advanced_sensitivity, invert_mouse: bool,
	freecam_enabled:   bool,
	map_loaded:        bool,
	offline_custom_map: ^shared.Map,
	net:               Net_Client_State,
	krunker:           Krunker_WS_State,
	krunker_world:     kproto.Krunker_World_State,
	join_link:         shared.Join_Link,
	join_status:       string,
	net_input_seq:     i32,
	// This frame's start time, at full precision (client_tick's `now` is an
	// f32, which loses a millisecond within hours of uptime). Remote players are
	// drawn at it and shots are stamped with it, so the shot's snapshot progress
	// describes exactly the poses on screen. 0 outside the game loop (tests).
	frame_time:        f64,
	snapshot_send_rate: f32,
	predicted_inputs:  [dynamic]shared.Input,

	game: shared.Game,
	me:   ^shared.Player,
	impact_markers: [dynamic]Impact_Marker,
	tracer_markers: [dynamic]Tracer_Marker,
	bullet_trails: [dynamic]Bullet_Trail,
	projectile_meshes: [dynamic]^Mesh,
	explosions: [dynamic]Krunker_Explosion_Flash,
	show_fps:       bool,
	// Debug performance window: stats ring, GPU timer queries and the
	// lazily created microui context (nil until the window is first shown).
	perf_overlay:   bool,
	last_perf_overlay_key: bool,
	perf:           Perf_Stats,
	debug_ui:       ^Debug_UI,
	// Debug window "Rendering" toggles and their line buffers (developer builds).
	debug_render:   Debug_Render,
	fps_value:      u32,
	fps_frames:     u32,
	fps_elapsed:    f32,
	// Nameplate visibility scheduler (healthbars.odin): the client time of the
	// last update, the round-robin cursor into game.players and the fractional
	// line-of-sight checks carried to the next frame.
	healthbar_visibility_time:   f32,
	healthbar_visibility_cursor: int,
	healthbar_visibility_budget: f32,
	viewport_width: i32,
	viewport_height: i32,
}

g_client: ^Client

// The menu's monitor names and fullscreen sizes. glfw.GetVideoModes
// re-enumerates every display mode on Windows, so this is refreshed only when
// a monitor is connected or removed, the chosen monitor changes, or Settings
// opens. Fixed capacity keeps it allocation-free.
Monitor_Cache :: struct {
	valid: bool,
	index: i32,
	sizes: [dynamic; 256]Display_Resolution,
	// GLFW owns the names until the monitor is removed, which invalidates the cache.
	names: [dynamic; 32]string,
	// Seconds per frame while not playing, from the monitor's refresh rate.
	idle_frame_interval: f64,
}

client_monitor_cache_refresh :: proc(client: ^Client) {
	phase_mark(.MONITOR_CACHE_REFRESH)
	client.monitor_cache_refreshes += 1
	start := glfw.GetTime()
	defer {
		// Some display drivers enumerate modes slowly; Settings opening runs this.
		if elapsed := glfw.GetTime() - start; elapsed > 0.1 {
			fmt.printf("[Display] Listing monitor modes took %.0f ms (%d sizes)\n", elapsed * 1000, len(client.monitor_cache.sizes))
		}
	}
	cache := &client.monitor_cache
	cache^ = {valid = true, index = client.monitor_index, idle_frame_interval = 1.0 / 60}
	monitor := client_monitor(client.monitor_index)
	append(&cache.sizes, ..monitor_resolutions(monitor))
	for handle in glfw.GetMonitors() { append(&cache.names, glfw.GetMonitorName(handle)) }
	if monitor != nil {
		if mode := glfw.GetVideoMode(monitor); mode != nil && mode.refresh_rate > 0 { cache.idle_frame_interval = 1.0 / f64(mode.refresh_rate) }
	}
}

// Refreshes the cache when it is stale or Settings is opening this frame.
client_monitor_cache :: proc(client: ^Client) -> ^Monitor_Cache {
	settings_opening := (client.menu.page == .SETTINGS || client.menu.page == .CONTROLS) && !client.menu.settings_active
	if !client.monitor_cache.valid || client.monitor_cache.index != client.monitor_index || settings_opening {
		client_monitor_cache_refresh(client)
	}
	return &client.monitor_cache
}

client_monitor_changed :: proc "c" (monitor: glfw.MonitorHandle, event: i32) {
	if g_client != nil { g_client.monitor_cache.valid = false; g_client.vrr_monitor = nil }
}

// The monitor showing the window: the fullscreen one, else the one holding
// the window's centre (the primary when none does).
client_window_monitor :: proc(window: glfw.WindowHandle) -> glfw.MonitorHandle {
	if window == nil { return glfw.GetPrimaryMonitor() }
	if monitor := glfw.GetWindowMonitor(window); monitor != nil { return monitor }
	x, y := glfw.GetWindowPos(window)
	w, h := glfw.GetWindowSize(window)
	cx, cy := x + w/2, y + h/2
	for monitor in glfw.GetMonitors() {
		mx, my := glfw.GetMonitorPos(monitor)
		mode := glfw.GetVideoMode(monitor)
		if mode == nil { continue }
		if cx >= mx && cx < mx + i32(mode.width) && cy >= my && cy < my + i32(mode.height) { return monitor }
	}
	return glfw.GetPrimaryMonitor()
}

// Re-detects VRR when the window's monitor changed (checked every 30 frames)
// or `force`. A changed refresh rate restarts the cap's margin.
client_vrr_update :: proc(client: ^Client, force := false) {
	client.vrr_check_frame += 1
	if !force && client.vrr_monitor != nil && client.vrr_check_frame % 30 != 0 { return }
	monitor := client_window_monitor(client.window)
	if !force && monitor == client.vrr_monitor && monitor != nil { return }
	client.vrr_monitor = monitor
	delete(client.vrr.name)
	delete(client.vrr.source)
	info := vrr_detect(monitor)
	info.name, info.source = strings.clone(info.name), strings.clone(info.source)
	if info.refresh_hz != client.vrr.refresh_hz { vrr_adapt_reset(&client.vrr_adapt, info.refresh_hz) }
	client.vrr = info
	fmt.printfln("[Display] %s", vrr_status_text(info, client_vrr_mode(client), client.vsync, client.vrr_adapt.margin))
}

// Settings > Video > VRR cap and V-Sync, previewing the Settings draft.
client_vrr_mode :: proc(client: ^Client) -> Vrr_Mode {
	value := client.hud_settings.vrr_cap
	if client.menu.settings_active && (client.menu.page == .SETTINGS || client.menu.page == .CONTROLS) { value = client.menu.settings_draft.hud.vrr_cap }
	return Vrr_Mode(clamp(value, 0, len(Vrr_Mode) - 1))
}

client_vrr_vsync :: proc(client: ^Client) -> bool {
	if client.menu.settings_active && (client.menu.page == .SETTINGS || client.menu.page == .CONTROLS) { return client.menu.settings_draft.vsync }
	return client.vsync
}

// Seconds per frame of the VRR cap, or 0 when not capping.
client_vrr_interval :: proc(client: ^Client) -> f64 {
	if !vrr_cap_active(client_vrr_mode(client), client_vrr_vsync(client), client.vrr) { return 0 }
	return 1 / vrr_cap_fps(client.vrr.refresh_hz, client.vrr_adapt.margin)
}

// After a presented frame: widens the cap's margin if V-Sync still made it wait.
client_vrr_frame :: proc(client: ^Client) {
	if !vrr_cap_active(client_vrr_mode(client), client_vrr_vsync(client), client.vrr) { return }
	if vrr_adapt_frame(&client.vrr_adapt, gpu_last_vsync_wait_ms()) {
		fmt.printfln("[Display] Frames still waited for V-Sync under the VRR cap; capping at %.1f FPS now", vrr_cap_fps(client.vrr.refresh_hz, client.vrr_adapt.margin))
	}
}

// Menus and loading screens wait between frames instead of spinning a core:
// by default one display refresh, or the user's menu FPS limit. Whenever the
// cursor is captured for play, frames stay uncapped. Readiness flags are
// deliberately not checked: Krunker's "ready" packet clears
// krunker_world.ready during waiting and warmup phases while the player still
// moves, and capping then causes visible hitches. client_tick still runs every
// frame, so sockets keep being polled.
client_idle_frame_interval :: proc(client: ^Client) -> f64 {
	// V-Sync on a VRR display: never faster than the VRR cap.
	vrr := client_vrr_interval(client)
	if client.mouse_state.locked {
		// In game: Settings > Display > FPS limit (unlimited by default).
		cap := menuui.game_fps_limit_validate(client.hud_settings.fps_limit)
		return max(cap > 0 ? 1 / f64(cap) : 0, vrr)
	}
	limit := client.menu_fps_limit
	// Settings previews the staged limit; Cancel discards it with the draft.
	if client.menu.settings_active && (client.menu.page == .SETTINGS || client.menu.page == .CONTROLS) { limit = client.menu.settings_draft.menu_fps_limit }
	limit = menuui.menu_fps_limit_validate(limit)
	switch limit {
	case menuui.MENU_FPS_LIMIT_UNLIMITED: return vrr
	case menuui.MENU_FPS_LIMIT_MONITOR:
		if !client.monitor_cache.valid || client.monitor_cache.index != client.monitor_index { client_monitor_cache_refresh(client) }
		return max(client.monitor_cache.idle_frame_interval, vrr)
	case: return max(1 / f64(limit), vrr)
	}
}

// The next frame's target end. Deadlines advance by whole intervals so wakeup
// jitter does not lower the average rate; after a frame that ran more than one
// interval late, or when pacing starts, the schedule restarts from this frame.
client_idle_frame_deadline :: proc(previous, frame_start, interval: f64) -> f64 {
	deadline := previous + interval
	if previous <= 0 || deadline < frame_start || deadline > frame_start + interval { deadline = frame_start + interval }
	return deadline
}

// Event waits keep window messages and input flowing until the last stretch,
// which yields on the clock. With 1 ms timer resolution the waits land within
// a fraction of a millisecond, and the deadline schedule absorbs the rest, so
// a short margin keeps frame times even without burning a core: at 240 FPS a
// 1.5 ms margin cost about a third of a core more than 0.5 ms for no gain in
// rate (measured on a 240 Hz Windows laptop).
IDLE_FRAME_SPIN_MARGIN :: 0.0005

client_pace_idle_frame :: proc(client: ^Client, frame_start, interval: f64) {
	if interval <= 0 { client.idle_frame_deadline = 0; return }
	deadline := client_idle_frame_deadline(client.idle_frame_deadline, frame_start, interval)
	client.idle_frame_deadline = deadline
	for !bool(glfw.WindowShouldClose(client.window)) {
		remaining := deadline - glfw.GetTime()
		if remaining <= 0 { return }
		if remaining > IDLE_FRAME_SPIN_MARGIN {
			client_wait_events(remaining - IDLE_FRAME_SPIN_MARGIN)
		} else {
			client_timer_yield()
		}
	}
}

// Low latency: when the GPU is the bottleneck, the next frame starts (and
// reads input) only as early as it must to keep the GPU busy
// (gpu_frame_ready_delay), not a whole GPU frame early.
client_wait_frame_ready :: proc(client: ^Client) {
	delay := gpu_frame_ready_delay()
	if delay <= 0 { return }
	deadline := glfw.GetTime() + delay
	for !bool(glfw.WindowShouldClose(client.window)) {
		remaining := deadline - glfw.GetTime()
		if remaining <= 0 { return }
		if remaining > IDLE_FRAME_SPIN_MARGIN {
			client_wait_events(remaining - IDLE_FRAME_SPIN_MARGIN)
		} else {
			client_timer_yield()
		}
	}
}

MAX_PREDICTED_INPUTS :: 256

client_window_resolution :: proc(client: ^Client) -> Display_Resolution {
	if client.window != nil {
		width, height := glfw.GetWindowSize(client.window)
		return {width, height}
	}
	return DISPLAY_RESOLUTIONS[client.resolution_index]
}

client_remember_windowed_rect :: proc(client: ^Client) {
	if client.display_mode != .Windowed || glfw.GetWindowMonitor(client.window) != nil {
		return
	}

	client.windowed_rect.x, client.windowed_rect.y = glfw.GetWindowPos(client.window)
	client.windowed_rect.width, client.windowed_rect.height = glfw.GetWindowSize(client.window)
}

monitor_max_video_mode :: proc(monitor: glfw.MonitorHandle) -> (width, height, refresh_rate: i32) {
	modes := glfw.GetVideoModes(monitor)
	for mode in modes {
		mode_area := i32(mode.width) * i32(mode.height)
		if mode_area > width * height || (mode_area == width * height && i32(mode.refresh_rate) > refresh_rate) {
			width = i32(mode.width)
			height = i32(mode.height)
			refresh_rate = i32(mode.refresh_rate)
		}
	}
	return
}

client_monitor :: proc(index: i32) -> glfw.MonitorHandle {
	monitors := glfw.GetMonitors()
	if len(monitors) > 0 { return monitors[clamp(index, 0, i32(len(monitors))-1)] }
	return glfw.GetPrimaryMonitor()
}

// Distinct sizes the monitor can switch to in exclusive fullscreen, largest first.
monitor_resolutions :: proc(monitor: glfw.MonitorHandle, allocator := context.temp_allocator) -> []Display_Resolution {
	result := make([dynamic]Display_Resolution, allocator)
	if monitor == nil { return result[:] }
	for mode in glfw.GetVideoModes(monitor) {
		size := Display_Resolution{i32(mode.width), i32(mode.height)}
		if !slice.contains(result[:], size) { append(&result, size) }
	}
	slice.sort_by(result[:], proc(a, b: Display_Resolution) -> bool {
		return a.width*a.height > b.width*b.height || a.width*a.height == b.width*b.height && a.width > b.width
	})
	return result[:]
}

// The chosen fullscreen mode at its highest refresh rate, or the monitor's
// largest mode when nothing was chosen or the monitor cannot show that size.
monitor_fullscreen_mode :: proc(monitor: glfw.MonitorHandle, requested: Display_Resolution) -> (width, height, refresh_rate: i32) {
	width, height, refresh_rate = monitor_max_video_mode(monitor)
	if requested.width <= 0 || requested.height <= 0 { return }
	rate: i32
	for mode in glfw.GetVideoModes(monitor) {
		if i32(mode.width) == requested.width && i32(mode.height) == requested.height { rate = max(rate, i32(mode.refresh_rate)) }
	}
	if rate > 0 { width, height, refresh_rate = requested.width, requested.height, rate }
	return
}

// Picker index for the saved fullscreen size; unset or unsupported sizes show
// the largest mode, which is what monitor_fullscreen_mode then applies.
client_fullscreen_index :: proc(sizes: []Display_Resolution, requested: Display_Resolution) -> i32 {
	index, found := slice.linear_search(sizes, requested)
	return found ? i32(index) : 0
}

// The fullscreen size Save should apply: the picked mode of the draft's monitor
// when the draft is Fullscreen and a resolution was picked, else the saved one.
client_staged_fullscreen_resolution :: proc(client: ^Client, values: menuui.Settings_Values) -> Display_Resolution {
	if values.display_mode != i32(Display_Mode.Fullscreen) || !client.menu.settings_resolution_selected || client.window == nil { return client.fullscreen_resolution }
	sizes := monitor_resolutions(client_monitor(values.monitor_index))
	if len(sizes) == 0 { return client.fullscreen_resolution }
	return sizes[clamp(values.fullscreen_index, 0, i32(len(sizes))-1)]
}

client_apply_display_settings :: proc(client: ^Client) {
	phase_mark(.APPLY_DISPLAY)
	monitors := glfw.GetMonitors()
	if len(monitors) > 0 {
		client.monitor_index = clamp(client.monitor_index, 0, i32(len(monitors))-1)
	}
	monitor := client_monitor(client.monitor_index)
	if monitor == nil {
		return
	}

	mode := glfw.GetVideoMode(monitor)
	monitor_x, monitor_y := glfw.GetMonitorPos(monitor)
	resolution := DISPLAY_RESOLUTIONS[client.resolution_index]

	switch client.display_mode {
	case .Windowed:
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 1)
		x := monitor_x + (mode.width - resolution.width) / 2
		y := monitor_y + (mode.height - resolution.height) / 2
		glfw.SetWindowMonitor(client.window, nil, x, y, resolution.width, resolution.height, 0)
		client.windowed_rect = {x, y, resolution.width, resolution.height}
	case .Borderless:
		glfw.SetWindowMonitor(client.window, nil, monitor_x, monitor_y, mode.width, mode.height, 0)
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 0)
		glfw.SetWindowPos(client.window, monitor_x, monitor_y)
		glfw.SetWindowSize(client.window, mode.width, mode.height)
	case .Fullscreen:
		glfw.SetWindowAttrib(client.window, glfw.DECORATED, 1)
		full_width, full_height, full_refresh_rate := monitor_fullscreen_mode(monitor, client.fullscreen_resolution)
		glfw.SetWindowMonitor(client.window, monitor, 0, 0, full_width, full_height, full_refresh_rate)
	}
}

client_set_display_mode :: proc(client: ^Client, display_mode: Display_Mode) {
	if client.display_mode == display_mode {
		return
	}

	client_remember_windowed_rect(client)
	client.display_mode = display_mode
	client_apply_display_settings(client)
}

Client_Options :: struct {
	map_name: string,
	class_name: string,
	show_help: bool,
	show_fps:  bool,
	perf_overlay: bool,
	offline:   bool,
	asset_sweep: string,
	bench_maps: string, // Comma-separated; empty when not benchmarking.
	bench_seconds: f32,
	bench_sizes: string, // Comma-separated WxH or "native".
	no_batching: bool,
	gpu_debug: bool, // GL: debug context + KHR_debug log (logs/gl-debug.log); Vulkan: validation (logs/gpu-debug.log).
	no_cpu_pinning: bool, // Leave thread placement to the OS (cpu_affinity.odin).
	backend: Gpu_Backend, // --vulkan / --opengl, over the saved Graphics API setting
	backend_set: bool,
	host_link: string, // srclient://game?action=host-comp&... (host_link.odin)
}

print_client_help :: proc() {
	fmt.println("SR Client Odin client")
	fmt.println()
	fmt.printf("Usage: %s [options]\n", os.args[0])
	fmt.println()
	fmt.println("Options:")
	fmt.println("  -h, --help            Show this help message")
	fmt.println("  -m, --map <name>      Load a map by name (for example: burg)")
	fmt.println("  -c, --class <name>    Spawn as the given class (for example: hunter)")
	fmt.println("      --fps             Show an FPS meter")
	when SR_DEV {
		fmt.println("      --perf-overlay    Start with the debug performance window open (F3)")
	}
	fmt.println("      --offline         Run the local authoritative simulation")
	fmt.println("      --asset-sweep <manifest.txt>")
	fmt.println("                        Load every map, model, icon and sound in a hidden")
	fmt.println("                        window and list the asset files used (for packaging)")
	fmt.println("      --bench <maps> <seconds> [--bench-size <sizes>]")
	fmt.println("                        Render fixed viewpoints of each map (comma-separated)")
	fmt.println("                        offscreen with an uncapped frame rate, once per")
	fmt.println("                        Shadows/Lighting configuration, and print frame times.")
	fmt.println("                        Sizes are WxH or native, comma-separated (default native)")
	fmt.println("      --no-batching     Draw every map object individually, without culling")
	fmt.println("      --gpu-debug       Log driver messages: a debug OpenGL context to")
	fmt.println("                        logs/gl-debug.log, or Vulkan validation to")
	fmt.println("                        logs/gpu-debug.log (crashes and hangs are always")
	fmt.println("                        logged to logs/crash.log and logs/hang.log)")
	fmt.println("      --vulkan, --opengl")
	fmt.println("                        Draw with this graphics API for this run (default:")
	fmt.println("                        Settings > Video > Vulkan Renderer, which is on)")
	fmt.println("      --no-cpu-pinning  Let the OS place threads instead of giving the game")
	fmt.println("                        thread its own core (never core 0) and keeping")
	fmt.println("                        networking and helper threads off it")
	fmt.println()
	fmt.println("Available maps:")

	for name in shared.DEFAULT_MAP_NAMES {
		fmt.printf("  %s\n", name)
	}
	fmt.println("  ss_v3 (sandstorm_v3)")
	fmt.println()
	fmt.println("Available classes:")

	for i in 0 ..< shared.class_config_name_count() {
		fmt.printf("  %s\n", shared.class_config_name(i))
	}
}

normalize_map_name :: proc(name: string) -> string {
	if strings.has_suffix(name, ".json") {
		return name[:len(name) - len(".json")]
	}

	return name
}

map_name_is_valid :: proc(name: string) -> bool {
	if name == "ss_v3" {
		return true
	}

	for available in shared.DEFAULT_MAP_NAMES {
		if name == available {
			return true
		}
	}

	return false
}

map_asset_name :: proc(name: string) -> string {
	return shared.map_asset_name(name)
}

parse_client_options :: proc() -> (options: Client_Options, ok: bool) {
	ok = true

	for i := 1; i < len(os.args); i += 1 {
		arg := os.args[i]

		switch arg {
		case "-h", "--help":
			options.show_help = true
		case "--fps", "--show-fps":
			options.show_fps = true
		case "--perf-overlay":
			// Developer builds only (-define:SR_DEV=true); release builds ignore it.
			when SR_DEV { options.perf_overlay = true }
		case "--offline":
			options.offline = true
		case "--no-batching":
			options.no_batching = true
		case "--gpu-debug", "--gl-debug":
			options.gpu_debug = true
		case "--vulkan":
			options.backend, options.backend_set = .Vulkan, true
		case "--opengl":
			options.backend, options.backend_set = .OpenGL, true
		case "--no-cpu-pinning":
			options.no_cpu_pinning = true
		case "-m", "--map":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing map name after %s.\n\n", arg)
				return options, false
			}

			i += 1
			options.map_name = normalize_map_name(os.args[i])
		case "--asset-sweep":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing manifest path after %s.\n\n", arg)
				return options, false
			}

			i += 1
			options.asset_sweep = os.args[i]
		case "--bench":
			if i + 2 >= len(os.args) {
				fmt.eprintf("Missing map list or seconds after %s.\n\n", arg)
				return options, false
			}
			options.bench_maps = os.args[i + 1]
			seconds, seconds_ok := strconv.parse_f32(os.args[i + 2])
			if !seconds_ok || seconds <= 0 {
				fmt.eprintf("Invalid benchmark duration: %s\n\n", os.args[i + 2])
				return options, false
			}
			options.bench_seconds = seconds
			i += 2
		case "--bench-size":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing size after %s.\n\n", arg)
				return options, false
			}
			i += 1
			options.bench_sizes = os.args[i]
		case "-c", "--class":
			if i + 1 >= len(os.args) {
				fmt.eprintf("Missing class name after %s.\n\n", arg)
				return options, false
			}

			i += 1
			options.class_name = os.args[i]
		case:
			if strings.has_prefix(arg, "--map=") {
				options.map_name = normalize_map_name(arg[len("--map="):])
			} else if strings.has_prefix(arg, "--class=") {
				options.class_name = arg[len("--class="):]
			} else if host_link_is(arg) {
				options.host_link = arg
			} else {
				fmt.eprintf("Unknown option: %s\n\n", arg)
				return options, false
			}
		}
	}

	if len(options.map_name) > 0 && !map_name_is_valid(options.map_name) {
		fmt.eprintf("Unknown map: %s\n\n", options.map_name)
		return options, false
	}

	if len(options.class_name) > 0 && shared.class_config_index(options.class_name) < 0 {
		fmt.eprintf("Unknown class: %s\n\n", options.class_name)
		return options, false
	}

	return options, true
}

client_update_fps :: proc(client: ^Client, delta: f32) {
	if !client.show_fps {
		return
	}

	client.fps_frames += 1
	client.fps_elapsed += delta

	// Krunker's fpsRate (FPS Update Rate, ms); SR's default stays 250 ms.
	if client.fps_elapsed >= f32(menuui.fps_update_ms(client.hud_settings))/1000 {
		client.fps_value = u32(math.round(f32(client.fps_frames) / client.fps_elapsed))
		client.fps_frames = 0
		client.fps_elapsed = 0
	}
}


// Krunker's ping colours (z2): low below 50 ms, medium below 150 ms, else high.
ping_color :: proc(value: i32) -> shared.Vec4 {
	if value >= 150 { return {255.0/255, 75.0/255, 66.0/255, 1} }
	if value >= 50 { return {255.0/255, 213.0/255, 66.0/255, 1} }
	return {158.0/255, 235.0/255, 86.0/255, 1}
}

// #pingText starts as "0" and shows "-" when the server reports -1.
ping_label :: proc(value: i32, received: bool) -> string {
	if !received { return "0" }
	if value == -1 { return "-" }
	return fmt.tprintf("%d", value)
}

// Live sessions use the server-reported ping from SYNC_PLAYER; native
// sessions use the PING echo round trip. Local practice has no server.
client_ping :: proc(client: ^Client) -> (value: i32, received, available: bool) {
	if client.krunker.connected { return client.krunker_world.ping, client.krunker_world.has_ping, true }
	if client.net.connected { return client.net.ping.rtt_ms, client.net.ping.has_sample, true }
	return 0, false, false
}

// Krunker's .debugInfo beside the timer: "<fps> FPS" over "<ping> PING",
// 14px lines (the number in Krunker's green, the label at .5 white).
fps_render :: proc(client: ^Client) {
	if (!client.in_game && !g_death.active) || !client.mouse_state.locked {
		return
	}
	ping, ping_received, ping_available := client_ping(client)
	show_ping := ping_available && !client.hud_settings.hide_ping
	if !client.show_fps && !show_ping {
		return
	}
	base := client.ui.scale
	client.ui.scale = krunker_hud_scale(client)
	defer client.ui.scale = base
	ui := client.ui
	s := ui.scale
	x, top := 15*s, 15*s
	if !client.hud_settings.hide_timer {
		tx, _, tw, _ := kh_timer_rect(client)
		x = tx + tw + 10*s
	}
	label := shared.Vec4{1, 1, 1, 0.5}
	if client.show_fps {
		value := fmt.tprintf("%d", client.fps_value)
		kh_text(ui, ping_color(0), value, x, top, 14)
		kh_text(ui, label, " FPS", x + kh_measure(ui, value, 14), top, 14)
		top += (14*KH_LINE + 5)*s
	}
	if show_ping {
		value := ping_label(ping, ping_received)
		kh_text(ui, ping_color(ping), value, x, top, 14)
		kh_text(ui, label, " PING", x + kh_measure(ui, value, 14), top, 14)
	}
}

client_load_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	for i in 0 ..< len(client.game.map_inst.objects) {
		object := client.game.map_inst.objects[i]
		if object.mesh != nil {
			mesh := cast(^Mesh)object.mesh
			mesh.map_detail = map_object_detail(object)
			mesh.map_detail_visible = mesh.visible
			scene_add_mesh(client.scene, mesh)
		}
	}

	client_build_map_batches(client)
}

client_find_player :: proc(client: ^Client, uid: i32) -> ^shared.Player {
	for player in client.game.players {
		if player.uid == uid {
			return player
		}
	}
	return nil
}

client_clear_players :: proc(client: ^Client) {
	self_shadow_release()
	client_clear_projectiles(client)
	for player in client.game.players {
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_destroy(player)
	}
	clear(&client.game.players)
	client.game.player_count = 0
	client.me = nil
	client.in_game = false
	client.spawn_pending = false
	clear(&client.predicted_inputs)
}

client_discard_acked_inputs :: proc(client: ^Client, ack_seq: i32) {
	acked := 0
	for acked < len(client.predicted_inputs) && client.predicted_inputs[acked].seq <= ack_seq { acked += 1 }
	remove_range(&client.predicted_inputs, 0, acked)
}

// Drops the oldest predicted inputs beyond `limit` in one shift.
client_cap_predicted_inputs :: proc(client: ^Client, limit: int) {
	if excess := len(client.predicted_inputs) - limit; excess > 0 { remove_range(&client.predicted_inputs, 0, excess) }
}

client_apply_movement_state :: proc(player: ^shared.Player, state: ^shared.Packet_Player_State) {
	player.on_ground = state.on_ground
	player.on_ladder = state.on_ladder
	player.on_ramp = state.on_ramp
	player.on_terrain = state.on_terrain
	player.terrain_slipping = state.terrain_slipping
	player.did_jump = state.did_jump
	player.did_wall_jump = state.did_wall_jump
	player.can_slide = state.can_slide
	player.on_wall = state.on_wall
	player.wall_jump_count = i32(state.wall_jump_count)
	player.crouch_val = state.crouch_val
	player.aim_val = state.aim_val
	player.spread_plus = state.spread_plus
	shared.player_update_spread(player, 0, 0, 0)
	player.slide_timer = state.slide_timer
	player.jump_timer = state.jump_timer
	shared.player_update_height(player)

	if !state.on_ramp {
		player.has_ramp_fix = false
	}
}

client_reconcile_local_player :: proc(client: ^Client, player: ^shared.Player, state: ^shared.Packet_Player_State, was_active: bool) {
	client_discard_acked_inputs(client, state.ack_seq)
	player.interpolate = false
	player.position = state.position
	player.velocity = state.velocity
	client_apply_movement_state(player, state)

	if !was_active {
		player.direction = {state.x_dir, state.y_dir}
	}

	// Reapply inputs the server had not processed when it produced this
	// snapshot. `recon=true` runs deterministic movement/collision code while
	// suppressing duplicate shots, reloads, and recoil effects.
	for &input in client.predicted_inputs {
		shared.player_proc_input(player, &input, true, client.game.move_lock)
	}
}

client_apply_match_state :: proc(client: ^Client, state: ^shared.Packet_Match_State) {
	if (!client.map_loaded || state.map_index != client.game.current_map_index) && state.map_index >= 0 && state.map_index < client.game.map_count {
		if client.map_loaded {
			client_unload_map(client)
		}
		client_clear_players(client)
		if !client.game.ready || state.map_index != client.game.current_map_index {
			shared.game_init(&client.game, state.map_index, 0, false)
		}
		client_load_current_map(client)
		fmt.printf("[Net Client] Loaded authoritative server map slot %d\n", state.map_index)
	}
	shared.packet_apply_match_state(&client.game, state)
	client.snapshot_send_rate = state.send_rate > 0 ? state.send_rate : 32
	client_reconcile_players(client, state)
}

// client_reconcile_players drops remote players the server no longer tracks.
// The server removes a player from its sim the moment the client disconnects,
// so the roster in MATCH_STATE is the source of truth; without this a departed
// player would stay frozen in the world forever.
client_reconcile_players :: proc(client: ^Client, state: ^shared.Packet_Match_State) {
	for i := len(client.game.players) - 1; i >= 0; i -= 1 {
		player := client.game.players[i]
		if player.is_you || player == client.me {
			continue
		}
		found := false
		for j in 0 ..< state.player_count {
			if state.player_ids[j] == u32(player.uid) {
				found = true
				break
			}
		}
		if found {
			continue
		}
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_destroy(player)
		unordered_remove(&client.game.players, i)
	}
	client.game.player_count = i32(len(client.game.players))
}

client_apply_player_state :: proc(client: ^Client, state: ^shared.Packet_Player_State) {
	if state.class_id < 0 || state.class_id >= i32(len(client.game.classes)) || state.player_id == 0 || state.team < 0 || state.team > 2 {
		fmt.eprintf("[Net Client] Rejected invalid player state id=%d class=%d team=%d\n", state.player_id, state.class_id, state.team)
		return
	}
	if state.health < 0 || state.health > f32(state.max_health) || state.max_health <= 0 || state.max_health > 10000 {
		fmt.eprintf("[Net Client] Rejected invalid health state for player %d\n", state.player_id)
		return
	}
	if state.crouch_val < 0 || state.crouch_val > 1 || state.aim_val < 0 || state.aim_val > 1 || state.slide_timer < 0 || state.jump_timer < 0 {
		fmt.eprintf("[Net Client] Rejected invalid movement state for player %d\n", state.player_id)
		return
	}

	// The server reports its snapshot cadence in MATCH_STATE. Until the first
	// one arrives (or if it is missing) fall back to the default 32 Hz rate.
	send_rate := client.snapshot_send_rate
	if send_rate <= 0 {
		send_rate = 32
	}

	player := client_find_player(client, i32(state.player_id))
	if state.is_you && client.me != nil && client.me.uid != i32(state.player_id) {
		fmt.eprintf("[Net Client] Rejected duplicate local ownership for player %d (local is %d)\n", state.player_id, client.me.uid)
		return
	}
	if !state.is_you && client.me != nil && client.me.uid == i32(state.player_id) {
		fmt.eprintf("[Net Client] Rejected ownership loss for local player %d\n", state.player_id)
		return
	}
	if player == nil {
		player = shared.player_init(&client.game)
		player.uid = i32(state.player_id)
		player.team = state.team
		shared.game_players_add(&client.game, player)
		shared.player_spawn(player, state.class_id, state.secondary_id)
		player.swap_timer_ms = 0
		player.active = false
	}

	was_active := player.active
	previous_shot_seq := player.shot_seq
	if player.class_index != state.class_id || player.secondary_id != shared.secondary_weapon_id(client.game.weapons, state.secondary_id) {
		if player.mesh != nil {
			scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
			player_meshes_fini(player)
		}
		shared.player_spawn(player, state.class_id, state.secondary_id)
		player.swap_timer_ms = 0
		was_active = false
	}

	player.team = state.team
	if state.active && !was_active {
		shared.player_reset_movement_animation(player)
	}
	player.active = state.active
	if state.is_you {
		if state.active {
			client_reconcile_local_player(client, player, state, was_active)
		} else {
			clear(&client.predicted_inputs)
			player.interpolate = false
			player.position = state.position
			player.velocity = state.velocity
			client_apply_movement_state(player, state)
		}
	} else if was_active {
		// Interpolate from the previously displayed position toward the fresh
		// authoritative one. Between snapshots the client lerps, so a moving
		// player no longer steps/jerks and never desyncs visually.
		player.interpolate = true
		player.dt = 0
		player.send_rate = send_rate
		player.interp_pos_start = player.position
		player.interp_pos_end = state.position
		player.interp_dir_start = player.direction
		player.interp_dir_end = {state.x_dir, state.y_dir}
		player.velocity = state.velocity
		client_apply_movement_state(player, state)
	} else {
		// Fresh spawn or re-appearance: snap, then interpolate from here.
		player.position = state.position
		player.direction = {state.x_dir, state.y_dir}
		player.interpolate = true
		player.dt = 0
		player.send_rate = send_rate
		player.interp_pos_start = player.position
		player.interp_pos_end = state.position
		player.interp_dir_start = player.direction
		player.interp_dir_end = player.direction
		player.velocity = state.velocity
		client_apply_movement_state(player, state)
	}
	if state.health < player.health { shared.player_emit_presentation(player, .DAMAGE) }
	player.health = state.health
	player.max_health = state.max_health
	player.score, player.kills, player.deaths = state.score, state.kills, state.deaths
	player.input_seq = state.ack_seq
	ownership_changed := player.mesh != nil && player.render_you != state.is_you
	if ownership_changed {
		scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
		player_meshes_fini(player)
		was_active = false
	}
	player.is_you = state.is_you
	player.render_you = state.is_you
	weapon_found := false
	for weapon_id, loadout_index in player.loadout {
		if weapon_id == i32(state.weapon_id) {
			weapon_found = true
			weapon := client.game.weapons[weapon_id]
			if state.active_ammo > weapon.ammo {
				fmt.eprintf("[Net Client] Rejected invalid ammo %d for player %d weapon %d\n", state.active_ammo, state.player_id, state.weapon_id)
				return
			}
			if player.loadout_index != i32(loadout_index) {
				shared.player_swap_weapon(player, i32(loadout_index), true, true, true)
			}
			player.ammo[loadout_index] = state.active_ammo
			break
		}
	}
	if !weapon_found {
		fmt.eprintf("[Net Client] Rejected weapon %d outside player %d loadout\n", state.weapon_id, state.player_id)
		return
	}
	shared.player_update_spread(player, 0, 0, 0)
	new_shots: u32
	if was_active && state.active && state.shot_seq > previous_shot_seq {
		// Cap a pathological jump while still preserving the authoritative
		// sequence value, so a malformed snapshot cannot create an unbounded loop.
		new_shots = min(state.shot_seq - previous_shot_seq, u32(16))
	}
	player.shot_seq = state.shot_seq
	for shot_index in 0 ..< int(new_shots) {
		shared.player_emit_presentation(player, .FIRE)
		if player.weapon.melee {
			is_throw := player.can_throw && player.aim_val >= 1 && player.game.config.throwable_melees
			shared.player_start_melee_animation(player, is_throw ? 3 : player.can_throw ? 1 : 2)
			if is_throw {
				player.can_throw = player.unlimited_ammo
			}
		} else {
			shared.player_apply_recoil(player)
			shared.player_start_view_kick(player)
			if player.weapon.projectile && (!player.weapon.projectile_disable || player.game.config.bullet_drop) {
				remaining := new_shots - u32(shot_index) - 1
				player.projectile_shot_seq = state.projectile_shot_seq >= remaining ? state.projectile_shot_seq - remaining : 0
				shared.projectile_spawn(player, shared.player_projectile_angles(player))
			}
		}
	}

	player.projectile_shot_seq = state.projectile_shot_seq

	if state.active && (!was_active || player.mesh == nil) {
		if player.mesh == nil {
			player_generate_meshes(player, state.is_you)
		}
		scene_add_player_mesh(state.is_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
	} else if !state.active && was_active && player.mesh != nil {
		scene_remove_player_mesh(player.render_you ? client.fps_scene : client.scene, cast(^Player_Mesh)player.mesh, int(player.loadout_size))
	}

	if state.is_you {
		client.me = player
		if state.active {
			client.in_game = true
			client.has_life = true
			if client.spawn_pending && client.menu.page == .HOME {
				glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_DISABLED)
				client.mouse_state.locked = true
				x, y := glfw.GetCursorPos(client.window)
				client.mouse_state.last_pos = {f32(x), f32(y)}
			}
			client.spawn_pending = false
			client.spawn_retry_timer = 0
		}
	}
	if player.mesh != nil && player.active {
		player_update_meshes(player, false)
	}
}

set_window_icon :: proc(client: ^Client) {
	// SR Client's own icon; the game's icon only if it is missing.
	icon_path := shared.concat(shared.assets_path(), "img/sr_icon.png")
	if !os.exists(icon_path) { delete(icon_path); icon_path = shared.concat(shared.assets_path(), "img/icon.png") }
	defer delete(icon_path)
	c_icon_path := strings.clone_to_cstring(icon_path)
	defer delete(c_icon_path)

	w, h, channels: i32
	pixels := stbi.load(c_icon_path, &w, &h, &channels, 4)
	shared.asset_trace(icon_path, pixels != nil)
	if pixels == nil {
		fmt.eprintln("Failed to load window icon:", icon_path)
		return
	}
	defer stbi.image_free(pixels)

	image := glfw.Image {
		width  = w,
		height = h,
		pixels = pixels,
	}

	glfw.SetWindowIcon(client.window, []glfw.Image{image})
}

client_unload_map :: proc(client: ^Client) {
	audio_stop_all(client.audio)
	clear(&client.game.presentation_events)
	if client.game.map_inst == nil || !client.map_loaded {
		return
	}

	map_batch_destroy(client.scene)
	for object in client.game.map_inst.objects {
		if object.mesh != nil {
			mesh := cast(^Mesh)object.mesh
			scene_remove_mesh(client.scene, mesh)
			mesh_fini(mesh)
			object.mesh = nil
		}
	}

	resource_trim_texture_cache()
	resource_trim_geometry_cache()
	shadow_release_map()
	client.map_loaded = false
}

client_load_current_map :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}
	phase_mark(.MAP_LOAD)

	// Activate the map's current environment before creating its materials.
	// The browser clears to `sky` and applies the same fog/lighting settings to
	// every map mesh; keeping this state global lets the existing scene API stay
	// lightweight while still matching per-map captures.
	g_lighting_config = client.game.map_inst.lighting
	gpu_set_clear_color(g_lighting_config.sky_color.xyz)

	shared.map_load_meshes(client.game.map_inst, prefab_init_cb)
	client_load_map(client)
	client.map_loaded = true

	renderable := 0
	for object in client.game.map_inst.objects {
		if object.mesh != nil {
			renderable += 1
		}
	}
	fmt.printf(
		"[Map] parsed %d objects, built %d renderable meshes\n",
		len(client.game.map_inst.objects),
		renderable,
	)
	resource_print_stats("map loaded")
}

client_tick_textures :: proc(client: ^Client, now: f32) {
	if client.game.map_inst == nil {
		return
	}

	for object in client.game.map_inst.objects {
		client_animate_object_texture(object, now)
	}
}

client_update_objective_visuals :: proc(client: ^Client) {
	if client.game.map_inst == nil {
		return
	}

	active := client.game.match.objective.active_object_index
	for object, index in client.game.map_inst.objects {
		if (!object.score_zone && !object.objective) || object.mesh == nil {
			continue
		}

		mesh := cast(^Mesh)object.mesh
		// Keep the texture's original yellow and alpha gradient, as in the
		// browser. Multiplying it by team colors destroys the intended tint.
		mesh.visible = i32(index) == active
	}
}

client_tick_impacts :: proc(client: ^Client, delta: f32) {
	// Krunker plays no sound for bullets hitting walls. Another player's
	// bullet passing within 27 units of you whizzes (its tracer's checkSound:
	// whizz_0/1 at 0.12, rate 0.8..1.2), once per bullet.
	whizzes := 0
	for &impact in client.game.impacts {
		if client.audio != nil && whizzes < 2 && (client.me == nil || impact.shooter_uid != client.me.uid) {
			if bullet_passes_within(impact.origin, impact.position, client.audio.listener.position, KRUNKER_WHIZZ_RANGE) {
				audio_play_effect(client.audio, rand.int_max(2) == 0 ? "whizz_0" : "whizz_1", gain = 0.12, priority = 0, rate = rand.float32_range(0.8, 1.2))
				whizzes += 1
			}
		}
		client_add_tracer(client, &impact)
		client_add_bullet_hole(client, &impact)
	}
	when SR_DEV { debug_render_record_impacts(client, glfw.GetTime()) }
	clear(&client.game.impacts)
	client_tick_bullet_holes(client, delta)
	client_tick_tracers(client, delta)
}

client_clear_impacts :: proc(client: ^Client) {
	krunker_client_clear_explosions(client)
	client_clear_projectiles(client)
	client_clear_bullet_holes(client)
	client_clear_tracers(client)
	clear(&client.game.impacts)
}

client_update_freecam :: proc(client: ^Client, mouse_delta: shared.Vec2, delta: f32) {
	rotation := client_mouse_rotation(client, mouse_delta)
	client.camera.rotation.x -= rotation.y
	client.camera.rotation.y -= rotation.x
	client.camera.rotation.x = max(-math.PI * 0.5, min(math.PI * 0.5, client.camera.rotation.x))
	client.camera.rotation.y = math.mod(client.camera.rotation.y, 2.0 * math.PI)

	forward := glfw.GetKey(client.window, glfw.KEY_W) == glfw.PRESS
	back := glfw.GetKey(client.window, glfw.KEY_S) == glfw.PRESS
	left := glfw.GetKey(client.window, glfw.KEY_A) == glfw.PRESS
	right := glfw.GetKey(client.window, glfw.KEY_D) == glfw.PRESS
	up := glfw.GetKey(client.window, glfw.KEY_SPACE) == glfw.PRESS
	down := glfw.GetKey(client.window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS

	move := shared.Vec3{}
	if forward != back {
		move.x += forward ? -math.sin(client.camera.rotation.y) : math.sin(client.camera.rotation.y)
		move.z += forward ? -math.cos(client.camera.rotation.y) : math.cos(client.camera.rotation.y)
	}
	if left != right {
		move.x += left ? -math.cos(client.camera.rotation.y) : math.cos(client.camera.rotation.y)
		move.z += left ? math.sin(client.camera.rotation.y) : -math.sin(client.camera.rotation.y)
	}
	if up != down {
		move.y = up ? 1.0 : -1.0
	}

	length := math.sqrt(move.x * move.x + move.y * move.y + move.z * move.z)
	if length > 0.0 {
		move /= length
		client.camera.position += move * (20.0 * delta)
	}
}

client_enter_game :: proc(client: ^Client) {
	if krunker_client_respawn_remaining(client, glfw.GetTime()) > 0 { return }
	if (!client.game.ready && !(client.krunker.connected && client.krunker_world.ready)) || (client.me != nil && client.me.active) || client.spawn_pending {
		return
	}
	if client.net.connected && !client.net.match_state_received {
		return
	}
	if client.krunker.connected {
		if !client.krunker.spawned {
			client.krunker.class_index = client.selected_class
			client.krunker.secondary_index = client_secondary_request(client, client.selected_class)
			client.krunker.secondary_response_pending = true
			client.krunker.secondary_request_revision = 0
			for player in client.krunker_world.players {
				if player.sid == client.krunker_world.local_sid { client.krunker.secondary_request_revision = player.secondary_revision }
			}
			client.krunker.team = client.lobby_team
			client.spawn_pending = true
			// The entry deadline (lobby tick: 20 s) counts from this request. The
			// death cam's auto respawn enters without the menu's Play button, and
			// an old timestamp cancelled the request right after "en" was sent:
			// the server spawned us, the client never took control.
			client.team_request_time = glfw.GetTime()
			client.krunker.bootstrapped = false
			client.krunker.bootstrap_step = 0
		}
		return
	}

	if client.game.is_local {
		client.in_game = true
		if client.me == nil {
			client.me = shared.player_init(&client.game)

			if client.me == nil {
				client.in_game = false
				return
			}

			shared.game_players_add(&client.game, client.me)
		}

		if client.me.mesh != nil {
			scene_remove_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
			player_meshes_fini(client.me)
		}
		client.has_life = true
		client.me.is_you = true
		client.me.team = client.lobby_team
		shared.player_spawn(client.me, client.selected_class, client_secondary_choice(client))
		player_generate_meshes(client.me, true)
		shared.player_swap_weapon(client.me, 0, true, false, false)
		scene_add_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
	} else if client.net.connected {
		client.spawn_pending = true
		client.spawn_retry_timer = 0.5
		net_client_send_spawn(&client.net, client.selected_class, client_secondary_choice(client))
	}
}

client_frame_time :: proc(client: ^Client, now: f32) -> f64 {
	return client.frame_time > 0 ? client.frame_time : f64(now)
}

client_tick :: proc(client: ^Client, now, delta: f32) {
	when ODIN_OS == .Windows {
		if client.krunker.auth_rejected {
			krunker_ws_disconnect(&client.krunker)
			if !client_access_retry(client, true) { krunker_ws_set_status(client, "Krunker rejected the renewed access token. Sign in again or use Forget browser session.") }
		}
	}
	client_access_tick(client)
	client_mods_tick(client)
	round_sounds_tick(client)
	host_game_tick(client)
	host_link_tick(client)
	game_files_update_tick(client)
	if client.join_queued > 0 {
		client.join_queued -= 1
		if client.join_queued == 0 { client_join_invite(client) }
	}
	if client.net.connected {
		net_client_poll(client, glfw.GetTime())
	}
	if client.krunker.connected {
		phase_mark(.NETWORK)
		if menuui.hud_network_thread(client.hud_settings) && client.krunker.handle != nil { krunker_net_thread_start(&client.krunker) }
		if g_net_thread.running { krunker_ws_poll_threaded(client) } else { krunker_ws_poll(client) }
		krunker_client_sync_match(client, f64(now))
		phase_mark(.GAME_LOGIC)
	}
	chat_channel_tick(client)
	round_hud_tick(client)
	if !client.game.ready && !(client.krunker.connected && client.krunker_world.ready) {
		return
	}

	client_lobby_tick(client)
	client_update_fps(client, delta)
	if client.spawn_pending && client.net.connected {
		client.spawn_retry_timer = max(0.0, client.spawn_retry_timer - delta)
		if client.spawn_retry_timer == 0 {
			net_client_send_spawn(&client.net, client.selected_class, client_secondary_choice(client))
			client.spawn_retry_timer = 0.5
		}
	}

	editing_settings := client.menu.page == .SETTINGS || client.menu.page == .CONTROLS || client.menu.page == .HOST || menuui.login_typing(&client.menu)
	debug_key := !editing_settings && glfw.GetKey(client.window, glfw.KEY_GRAVE_ACCENT) == glfw.PRESS
	freecam_key := glfw.GetKey(client.window, glfw.KEY_RIGHT_BRACKET) == glfw.PRESS

	if debug_key && !client.last_debug_key && !client.net.connected && !client.krunker.connected {
		client_unload_map(client)

		if client.me != nil {
			scene_remove_player_mesh(client.fps_scene, cast(^Player_Mesh)client.me.mesh, int(client.me.loadout_size))
			player_meshes_fini(client.me)
			shared.player_destroy(client.me)
		}

		client.me = nil
		client.in_game = false

		shared.game_init(&client.game, -1, -1, true)
		client_load_current_map(client)
	}

	client.last_debug_key = debug_key
	// Freecam is an offline tool (local practice, map checks). In a live
	// lobby it would let the camera look through walls, so it is never
	// available there and is switched off the moment a connection exists.
	live := client.net.connected || client.krunker.connected
	if live { client.freecam_enabled = false }
	if !live && !editing_settings && !client_binding_used(client, glfw.KEY_RIGHT_BRACKET) && freecam_key && !client.last_freecam_key && client.me != nil && client.me.active {
		client.freecam_enabled = !client.freecam_enabled
	}
	client.last_freecam_key = freecam_key

	x, y := glfw.GetCursorPos(client.window)

	fullscreen_key := !editing_settings && client_action_down(client, .FULLSCREEN)

	if fullscreen_key && !client.last_fullscreen_key {
		client_set_display_mode(client, client.display_mode == .Windowed ? .Fullscreen : .Windowed)
	}

	client.last_fullscreen_key = fullscreen_key
	when SR_DEV {
		if client_perf_overlay_toggle_update(client) { client.settings_dirty = true }
	}
	client.mouse_state.locked = glfw.GetInputMode(client.window, glfw.CURSOR) == glfw.CURSOR_DISABLED

	escape_key := client_action_down(client, .MENU) || glfw.GetKey(client.window, glfw.KEY_ESCAPE) == glfw.PRESS
	if chat_escape_blocked(client) { escape_key = false } // Escape closed the chat box.
	if g_chat.typing && !client.mouse_state.locked { chat_close() }
	if client.mouse_state.locked && escape_key && !client.last_escape_key {
		audio_play_effect(client.audio, "menu_open", .UI, 0.35)
		glfw.SetInputMode(client.window, glfw.CURSOR, glfw.CURSOR_NORMAL)
		client.mouse_state.locked = false
		client.menu.page = .HOME
		client.menu.pressed = 0
		client.menu.previous.escape = true
		client.menu.previous.down = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS
	}

	// A finished match whose lobby then closed keeps its scoreboard; the old
	// invite is cleared (that game no longer exists).
	if client.krunker_was_connected && !client.krunker.connected {
		ended := client.krunker_world.has_match && client.krunker_world.match.phase == .ENDED
		host_ended := strings.contains(client.krunker.server_error, "ended")
		if ended { client.end_hold = true }
		if ended || host_ended { menuui.set_invite(&client.menu, "") }
	}
	client.krunker_was_connected = client.krunker.connected
	// F5: back to the fresh start screen (not while connected).
	refresh_key := glfw.GetKey(client.window, glfw.KEY_F5) == glfw.PRESS
	if refresh_key && !client.last_refresh_key {
		if client.krunker.connected { client_refresh_rejoin(client) }
		else if !client.net.connected && !client.local_practice { client_refresh(client) }
	}
	client.last_refresh_key = refresh_key
	// The end screen replaces the menu until dismissed or the next match.
	end_screen_was_visible := client.end_screen_active && !client.end_screen_dismissed
	end_screen_visible := client_end_screen_update(client, glfw.GetTime(), escape_key && !client.last_escape_key && !client.mouse_state.locked)
	if end_screen_was_visible && !end_screen_visible && client.end_screen_dismissed {
		client.menu.page = .HOME
		client.menu.pressed = 0
		client.menu.previous.escape = true
		if client.end_hold { client_refresh(client) }
	}

	client.last_escape_key = escape_key

	if client.mouse_state.locked && (client.me == nil || !client.me.active) {
		// While dead: respawn automatically, or on click with Auto respawn off.
		if death_cam_wants_respawn(client) { client_enter_game(client) }
	}

	if client.me == nil && client.game.map_inst != nil {
		client.camera.position = client.game.map_inst.camera_position
	}

	noclip_key := !client_binding_used(client, glfw.KEY_N) && glfw.GetKey(client.window, glfw.KEY_N) == glfw.PRESS
	aim_down := client_action_down(client, .AIM)
	scope_input := client_aim_input(client, aim_down, client.me != nil && client.me.active && client.mouse_state.locked && !client.freecam_enabled)
	inspect_down := client_action_down(client, .INSPECT)
	client_scoreboard_update(client)
	inspect_cancel := false

	// A Scroll press is held for exactly one gameplay command, like Krunker
	// releasing key 20000 right after the next input packet. Only the live
	// path can build zero commands in a frame; it then keeps the press.
	scroll_pending := false
	if client.me != nil && client.me.active {
		input := shared.Input{}
		after_scroll: shared.Input
		mouse_delta := shared.Vec2{0, 0}

		mouse_delta.x = f32(x) - client.mouse_state.last_pos.x
		mouse_delta.y = f32(y) - client.mouse_state.last_pos.y
		mouse_delta = client_mouse_delta(mouse_delta)

		input.move_dir = -1
		input.delta = delta

		input.x_dir = client.me.direction.x
		input.y_dir = client.me.direction.y
		after_scroll = input

		if client.mouse_state.locked && !client.freecam_enabled {
			if noclip_key && !client.last_noclip_key && !client.krunker.connected {
				client.me.noclip = !client.me.noclip
			}

			rotation := client_mouse_rotation(client, mouse_delta)
			input.x_dir -= rotation.y
			input.y_dir -= rotation.x

			bound, sustained := client_gameplay_bound_input(client)
			input.jump, input.crouch, input.reload, input.shoot, input.scope = bound.jump, bound.crouch, bound.reload, bound.shoot, scope_input
			input.swap, input.move_dir = bound.swap, bound.move_dir
			after_scroll = input
			after_scroll.jump, after_scroll.crouch, after_scroll.reload, after_scroll.shoot = sustained.jump, sustained.crouch, sustained.reload, sustained.shoot
			after_scroll.move_dir = sustained.move_dir
		}
		inspect_cancel = input.shoot || input.scope || input.reload || input.swap != 0

		if client.mouse_state.locked && client.freecam_enabled {
			client_update_freecam(client, mouse_delta, delta)
		}

		input.seq = client.net_input_seq
		client.net_input_seq += 1
		if client.krunker.connected {
			scroll_pending = krunker_client_predict_frame(client, &input, after_scroll, client_frame_time(client, now))
			krunker_ws_send_input(client)
		} else if client.net.connected {
			append(&client.predicted_inputs, input)
			client_cap_predicted_inputs(client, MAX_PREDICTED_INPUTS)
			shared.player_proc_input(client.me, &input, true, client.game.move_lock, true)
			net_client_send_input(&client.net, &input)
		} else {
			shared.player_queue_input(client.me, &input)
		}

	} else {
		// Freecam is only valid while the player is spawned.
		if !client.spawn_pending { client.freecam_enabled = false }
		// Dead: the mouse still looks around (death cam), and the raw input
		// is consumed so the first frame after respawn does not jump.
		if client.mouse_state.locked {
			mouse_delta := client_mouse_delta({f32(x) - client.mouse_state.last_pos.x, f32(y) - client.mouse_state.last_pos.y})
			death_cam_look(client, client_mouse_rotation(client, mouse_delta))
		}
	}
	client_scroll_frame_end(client, scroll_pending)

	client.mouse_state.last_pos.x = f32(x)
	client.mouse_state.last_pos.y = f32(y)
	client.last_noclip_key = noclip_key

	when TESTER_EXPORT { tester_export_tick(client, delta) }
	if !client.net.connected && !client.krunker.connected {
		shared.game_tick(&client.game, now, delta)
	} else {
		// The local player is predicted above. Remote players remain one snapshot
		// behind and interpolate between authoritative samples.
		if client.krunker.connected { krunker_client_interpolate_remotes(client, client_frame_time(client, now), delta); when HITREG_AUDIT { hitreg_audit_tick(client, client_frame_time(client, now)) } }
		for player in client.game.players {
			if player.active {
				player.idle_anim += shared.GAME_CONSTANTS.idle_anim_speed * delta
				shared.player_update_visual_animations(player, delta)
				// In Krunker games the local player's recoil advances per input
				// inside the prediction (like Krunker's server), not per frame.
				if !(client.krunker.connected && player == client.me) {
					shared.player_update_recoil(player, delta)
				}
				if player != client.me {
					shared.player_interpolate(player, delta)
				}
				if player.mesh != nil && (player != client.me || client.freecam_enabled) {
					player_update_meshes(player, false)
				}
			}
		}
		shared.game_tick_projectiles(&client.game, delta * client.game.config.delta_mlt)
	}
	client_update_inspect(client, inspect_down, client.mouse_state.locked && !client.freecam_enabled, inspect_cancel, delta)
	client_update_objective_visuals(client)

	// Camera and view-model transforms must use the state produced by this
	// frame's input, otherwise fast mouse movement makes the gun trail and jump.
	if client.me != nil && client.me.active && !client.freecam_enabled {
		view_position, view_aim := client.me.position, client.me.aim_val
		if client.krunker.connected {
			sample := krunker_client_render_sample(client)
			view_position, view_aim = sample.position, sample.aim
		}
		third_person := player_uses_third_person_camera(client.me)
		if third_person {
			// Full-body meshes use the map's camera offset. Keeping the camera at
			// the collision origin in this mode places it inside the character.
			client.camera.position = view_position + client.me.game.map_inst.config.cam_offset
			client.camera.position.y += client.me.height - shared.GAME_CONSTANTS.camera_height
		} else {
			client.camera.position = view_position
			client.camera.position.y += client.me.height - shared.GAME_CONSTANTS.camera_height
		}

		// Krunker's camera: aim + recoil kick + 0.1 * landBobY (the landing dip).
		// The bullet does not follow the landing dip, only the camera does.
		client.camera.rotation.x = client.me.direction.x + client.me.recoil_anim_y * shared.GAME_CONSTANTS.recoil_mlt + 0.1 * client.me.land_bob_y
		client.camera.rotation.y = client.me.direction.y
		client.camera.zoom = viewmodel_zoom(client.me.weapon.zoom, view_aim, client_viewmodel_values(client))

		if client.me.mesh != nil {
			player_update_meshes(client.me, false)
		}
	}
	if client.me == nil || !client.me.active { death_cam_update(client, delta) }
	enemy_counter_tick(client)
	client_audio_update_listener(client)
	client_tick_impacts(client, delta)
	client_tick_kill_feed(client, delta)
	client_tick_projectiles(client)
	krunker_client_tick_explosions(client, delta)

	client_tick_textures(client, now)

	phase_mark(.RENDER_WORLD)
	client_render_world(client)
	gl_check("render world", per_phase = true)

	// Overlay pass: bars use the world camera for projection only.
	phase_mark(.HEALTHBARS)
	gpu_pass_mark(.Interface)
	player_healthbars_update_visibility(client, now)
	player_healthbars_render(client)
	phase_mark(.RENDER_OVERLAY)

	ui_update(client.ui, f32(client.viewport_width), f32(client.viewport_height))

	// The debug window takes its input before the menu so a click or scroll
	// over it never reaches the Clay menu underneath; it is drawn last.
	debug_pointer := false
	when SR_DEV { debug_pointer = client.perf_overlay && debug_ui_update(client) }
	if end_screen_visible {
		end_screen_render(client, glfw.GetTime())
	} else if !client.mouse_state.locked {
		hud_render(client, delta, debug_pointer)
	} else {
		overlay_render(client, delta)
	}
	gl_check("hud", per_phase = true)
	when SR_DEV {
		if client.perf_overlay { phase_mark(.DEBUG_WINDOW); debug_ui_render(client) }
	}
}

// World and viewmodel passes. The benchmark mode draws through this too, so its
// numbers cover the same work as a real frame minus the HUD.
client_render_world :: proc(client: ^Client) {
	phase_mark(.PREVIEW_GRAPHICS)
	client_update_graphics(client)
	phase_mark(.RENDER_SCENE)
	_, quality := client_graphics_values(client)
	quality = menuui.quality_settings_validate(quality)
	// MSAA: the world and viewmodel go to a multisampled target, resolved at
	// the end; the interface is drawn after, single-sampled.
	world_target := client_msaa_begin(client, quality)
	gpu_clear(color = true, depth = true)
	g_draw_stats = {}
	client.scene.batching_enabled = client.render_batching
	// After batching_enabled: the shadow pass draws the static map through the
	// same batches. Its draw calls count towards this frame's stats.
	// Self shadow: your third-person rig, drawn only into the player shadow map.
	g_shadow_extra_casters = self_shadow_update(client, quality)
	gpu_pass_mark(.Shadows)
	phase_mark(.SHADOWS)
	shadow_prepare(client.scene, client.game.map_inst, quality, world_target, {0, 0, client.viewport_width, client.viewport_height}, client.camera.position)
	g_shadow_extra_casters = nil
	phase_mark(.RENDER_SCENE)
	saved_fov := client.camera.fov
	client.camera.fov = client_world_fov(client)
	gpu_pass_mark(.World)
	scene_render(client.scene, &client.camera, f32(client.viewport_width), f32(client.viewport_height), client.graphics_sampler)
	// Hitbox/collision wireframes, depth-tested against the world just drawn.
	when SR_DEV { debug_render_after_world(client) }
	client.camera.fov = saved_fov

	phase_mark(.RENDER_VIEWMODEL)
	gpu_pass_mark(.Viewmodel)
	gpu_clear(color = false, depth = true)
	weapon_camera := camera_for_viewmodel(&client.camera, client_viewmodel_values(client))
	// The viewmodel keeps the sun's shadows but not the player map, so your
	// own body (Self shadow) never shades your arms.
	g_shadow_viewmodel_pass = true
	scene_render(client.fps_scene, &weapon_camera, f32(client.viewport_width), f32(client.viewport_height), client.graphics_sampler)
	g_shadow_viewmodel_pass = false
	when SR_DEV { debug_render_after_viewmodel(client) }
	client_msaa_end(client, world_target)
}

// The graphics API a run starts with: --vulkan / --opengl, else the saved
// setting (Vulkan unless turned off).
client_pick_backend :: proc(options: Client_Options, opengl_setting: bool) -> Gpu_Backend {
	if options.backend_set { return options.backend }
	return opengl_setting ? .OpenGL : .Vulkan
}

resize_viewport :: proc "c" (window: glfw.WindowHandle, width, height: i32) {
	if g_client == nil || g_client.window != window { return }
	if g_gpu_backend == .OpenGL && glfw.GetCurrentContext() != window { return }
	context = runtime.default_context()
	// Vulkan resizes the window target and swapchain at the next frame start.
	gpu_set_target(g_client.render_target, width, height)
	g_client.viewport_width = width
	g_client.viewport_height = height
}

// SR Client: when started from a shortcut, Explorer or another folder, switch to
// the folder that holds sr_client.exe if the game files live there. Developer
// runs from the repo root (bin/ without assets) keep the current folder.
client_use_install_directory :: proc() {
	dir, err := os.get_executable_directory(context.temp_allocator)
	if err != nil do return
	assets := strings.concatenate({dir, "/assets"}, context.temp_allocator)
	if os.is_dir(assets) { os.set_working_directory(dir) }
}

main :: proc() {
	client_disable_power_throttling()
	client_use_install_directory()
	shared.mods_init()
	round_sounds_start() // Krunker's countdown sounds, fetched once in the background
	defer round_sounds_stop()
	options, options_ok := parse_client_options()
	if options.show_help {
		print_client_help()
		return
	}
	if !options_ok {
		print_client_help()
		return
	}
	// A tournament link while SR Client already runs: that window hosts it.
	if len(options.host_link) > 0 {
		if host_link_forward(options.host_link) { return }
	} else {
		_ = host_link_other_instance_running() // hold the running marker for later links
	}
	// Before any thread starts, so every thread is placed from the beginning.
	// The benchmark runs pinned too, measuring what the game does.
	// Classic (Vulkan Renderer off, or --opengl) is 0.24's setup: OpenGL and
	// threads placed by Windows. Only Vulkan pins the game thread.
	classic := client_pick_backend(options, client_settings_load().opengl) == .OpenGL
	if options.no_cpu_pinning || classic {
		fmt.println(classic ? "[CPU] pinning off (Classic renderer)" : "[CPU] pinning off (--no-cpu-pinning)")
	} else {
		g_cpu_pinning_text = strings.clone(cpu_pinning_apply())
		fmt.printfln("[CPU] %s", g_cpu_pinning_text)
	}
	if len(options.asset_sweep) > 0 {
		os.exit(asset_sweep_run(options.asset_sweep))
	}
	if len(options.bench_maps) > 0 {
		g_gpu_backend = client_pick_backend(options, client_settings_load().opengl)
		os.exit(bench_run(options.bench_maps, options.bench_seconds, options.bench_sizes))
	}
	// Krunker's current maps, checked in the background (see game_files_update.odin).
	if !options.offline { game_files_update_start() }
	defer game_files_update_stop()
	defer host_game_close()

	if !bool(glfw.Init()) {
		fmt.eprintln("Failed to init GLFW")
		return
	}
	defer glfw.Terminate()
	client_set_timer_precision()
	defer client_restore_timer_precision()

	client := new(Client)
	defer free(client)
	g_client = client
	preferences := client_settings_load()
	client.show_fps = options.show_fps || preferences.show_fps
	// The debug window exists only in developer builds; release builds never
	// open it, even if a dev build saved it as open.
	when SR_DEV { client.perf_overlay = options.perf_overlay || preferences.perf_overlay }
	client.display_mode = Display_Mode(preferences.display_mode)
	client.resolution_index, client.monitor_index = preferences.resolution_index, preferences.monitor_index
	client.fullscreen_resolution = {preferences.fullscreen_width, preferences.fullscreen_height}
	client.sensitivity, client.vsync = preferences.sensitivity, preferences.vsync
	client.opengl = preferences.opengl
	client.menu_fps_limit = preferences.menu_fps_limit
	client.mouse_dpi = preferences.mouse_dpi
	client.ads_sensitivity = preferences.ads_sensitivity
	client.advanced_sensitivity, client.invert_mouse = preferences.advanced_sensitivity, preferences.invert_mouse
	client.bindings, client.hud_settings = preferences.bindings, preferences.hud
	client.visual_settings, client.quality_settings = preferences.visuals, preferences.quality
	client.viewmodel_settings = preferences.viewmodel
	client.trail_settings = preferences.trails
	client.crosshair_settings = preferences.crosshair
	client.hitmarker_settings = preferences.hitmarker
	client.damage_settings = preferences.damage
	defer { if client.settings_dirty { client_settings_save(client_settings_snapshot(client)) } }
	when TESTER_EXPORT { tester_export_recover() }
	client.selected_secondary = 2
	client.render_batching = !options.no_batching

	client.camera.zoom = 1.0
	client.camera.fov = preferences.fov * math.PI / 180
	client.camera.near = 0.1
	client.camera.far = 10000.0

	// Before the window: driver crashes during context creation are reported too.
	phase_mark(.STARTUP)
	crash_handler_install()
	defer crash_handler_uninstall()

	window_title: cstring = "SR Client"
	backend := client_pick_backend(options, client.opengl)
	if backend == .Vulkan {
		// No GL context: the window gets a Vulkan surface. A GPU or driver that
		// cannot run Vulkan 1.3 gets a fresh OpenGL window instead.
		glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
		client.window = glfw.CreateWindow(1280, 720, window_title, nil, nil)
		glfw.DefaultWindowHints()
		g_vk_debug.wanted = options.gpu_debug
		g_gpu_backend = .Vulkan
		if client.window == nil || !gpu_vk_init(client.window) {
			fmt.eprintln("[GPU] Vulkan is not available on this GPU or driver; using OpenGL")
			if client.window != nil { glfw.DestroyWindow(client.window); client.window = nil }
			backend = .OpenGL
		}
	}
	g_gpu_backend = backend
	if backend == .OpenGL {
		glfw.WindowHint(glfw.OPENGL_PROFILE, glfw.OPENGL_CORE_PROFILE)
		if options.gpu_debug { glfw.WindowHint(glfw.OPENGL_DEBUG_CONTEXT, glfw.TRUE) }

		when ODIN_OS == .Darwin {
			glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
			glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 1)
			glfw.WindowHint(glfw.OPENGL_FORWARD_COMPAT, glfw.TRUE) // apple silicon needs this?
		} else {
			glfw.WindowHint(glfw.CONTEXT_VERSION_MAJOR, 4)
			glfw.WindowHint(glfw.CONTEXT_VERSION_MINOR, 5)
		}

		// No multisampled default framebuffer: MSAA (Settings > Visuals) renders
		// the world into its own target, resolved before the interface.
		client.window = glfw.CreateWindow(1280, 720, window_title, nil, nil)
	}
	if client.window == nil {
		fmt.eprintln("Failed to create window")
		return
	}
	defer glfw.DestroyWindow(client.window)
	client.viewport_width = 1280
	client.viewport_height = 720
	client.windowed_rect.x, client.windowed_rect.y = glfw.GetWindowPos(client.window)
	client.windowed_rect.width, client.windowed_rect.height = glfw.GetWindowSize(client.window)

	set_window_icon(client)

	glfw.SetFramebufferSizeCallback(client.window, resize_viewport)
	glfw.SetScrollCallback(client.window, client_scroll)
	glfw.SetCharCallback(client.window, menu_character)
	glfw.SetKeyCallback(client.window, client_binding_key)
	glfw.SetMouseButtonCallback(client.window, client_binding_mouse)
	glfw.SetMonitorCallback(client_monitor_changed)
	if backend == .OpenGL { glfw.MakeContextCurrent(client.window) }

	// The native Windows path owns raw mouse input (and decides whether GLFW's
	// RAW_MOUSE_MOTION may be enabled); other platforms use GLFW's raw motion.
	if client_mouse_init(client.window) {
		fmt.println("[Input] Native Windows raw mouse enabled")
	} else if bool(glfw.RawMouseMotionSupported()) {
		glfw.SetInputMode(client.window, glfw.RAW_MOUSE_MOTION, 1)
	}
	defer client_mouse_fini()

	if backend == .Vulkan {
		if g_vk_debug.log != nil { fmt.printfln("[Vulkan] Validation on; logging to %s", GPU_DEBUG_LOG_PATH) }
		diagnostics_capture_gpu_info()
	} else {
		gl.load_up_to(4, 5, glfw.gl_set_proc_address)
		diagnostics_capture_gpu_info()
		if options.gpu_debug {
			if gl_debug_install() {
				fmt.printf("[GL] Debug output on (debug context: %v); logging to %s\n", g_diag.gl_debug_context, GL_DEBUG_LOG_PATH)
			} else {
				fmt.eprintln("[GL] Debug output is not available on this context")
			}
		}
	}
	// Deferred here, so the device outlives every GPU object freed below.
	defer {
		if g_gpu_backend == .Vulkan { gpu_vk_fini() } else { gl_debug_shutdown() }
	}
	defer gpu_frames_fini()
	// GL draws window frames into the default framebuffer (0); Vulkan into
	// its window target, presented by gpu_present.
	client.render_target = gpu_window_target()
	{
		width, height := glfw.GetFramebufferSize(client.window)
		resize_viewport(client.window, width, height)
	}
	client_graphics_init(client)
	defer client_graphics_fini(client)

	gpu_set_vsync(client.vsync)
	client_apply_display_settings(client)
	defer software_cursor_fini()
	if backend == .OpenGL { gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA) }

	client.scene = scene_init()
	client.fps_scene = scene_init()
	client.ui = ui_init()

	if client.scene == nil || client.fps_scene == nil || client.ui == nil {
		return
	}
	if !menuui.init(&client.menu, menu_measure_text, client.ui) {
		fmt.eprintln("Failed to initialize the menu layout")
		return
	}
	defer menuui.fini(&client.menu)

	config_path := shared.concat(shared.assets_path(), "config/game.toml")
	defer delete(config_path)
	gameplay_config := shared.config_load_gameplay(config_path)
	defer shared.config_destroy_gameplay(gameplay_config)
	client.audio_settings = audio_settings_load()
	client.audio = audio_create(gameplay_config.weapons, client.audio_settings)
	defer {
		if client.audio_settings_dirty { audio_settings_save(client.audio_settings) }
		audio_destroy(client.audio)
	}
	// Hitmarkers and damage feedback read HIT/DAMAGE events even when audio is unavailable.
	client.game.presentation_enabled = true

	if len(options.class_name) > 0 {
		client.selected_class = i32(shared.class_config_index(options.class_name))
	}
	// Sessions start offline.  A live lobby is an explicit user action (for
	// example, pasting a custom-lobby link into the join control), so startup
	// must not probe localhost or any remote server implicitly.

	if len(options.map_name) > 0 {
		g_map_name = options.map_name
		map_path := shared.concat(shared.assets_path(), fmt.tprintf("maps/%s.json", map_asset_name(options.map_name)))
		selected_map, map_ok := shared.map_load_from_file(map_path)
		delete(map_path)

		if !map_ok {
			fmt.eprintf("Failed to load map: %s\n", options.map_name)
			return
		}
		client.offline_custom_map = selected_map

		maps := []^shared.Map{selected_map}
		shared.game_configure(&client.game, &gameplay_config.game, maps, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, 0, -1, !client.net.connected)
	} else {
		shared.load_default_maps()
		shared.game_configure(&client.game, &gameplay_config.game, nil, nil, gameplay_config.weapons, gameplay_config.classes)
		shared.game_init(&client.game, client.net.connected ? 0 : -1, -1, !client.net.connected)
	}

	if client.game.ready && !client.net.connected {
		client_load_current_map(client)
	}

	print_startup_info(client)
	if len(options.host_link) > 0 { host_link_queue(client, options.host_link) }
	// Tests: SR_TEST_SPAWN=<n> spawns Local practice at the same spot every time.
	if text, found := os.lookup_env("SR_TEST_SPAWN", context.temp_allocator); found {
		if n, ok := strconv.parse_int(text); ok && n >= 0 { shared.g_test_spawn = n }
	}
	free_all(context.temp_allocator)

	client_vrr_update(client, force = true)
	last_tick := glfw.GetTime()
	last_frame_start := glfw.GetTime()
	prev_cpu_ms, prev_swap_ms, prev_events_ms: f32

	for !bool(glfw.WindowShouldClose(client.window)) {
		frame_start := glfw.GetTime()
		client.frame_time = frame_start
		now := f32(frame_start)
		delta := f32(frame_start - last_tick) // in f64: f32 times lose precision with uptime

		last_tick = frame_start
		g_draw_calls = 0
		phase_frame_begin()
		gpu_frame_begin()

		software_cursor_update(client.window)
		phase_mark(.TICK)
		client_tick(client, now, delta)
		gl_check("frame")
		client_audio_tick(client, delta)
		// The debug window records the previous frame in full: its duration
		// (start to start), CPU time (tick + render submission), and how long
		// its SwapBuffers and event polling took.
		when SR_DEV {
			cpu_ms := f32((glfw.GetTime()-frame_start)*1000)
			perf_overlay_record(client, f32((frame_start-last_frame_start)*1000), prev_cpu_ms, prev_swap_ms, prev_events_ms)
			prev_cpu_ms = cpu_ms
		}
		last_frame_start = frame_start
		// A lost Vulkan device (driver reset or crash) cannot draw again.
		if gpu_device_lost() {
			fmt.eprintln("[GPU] The Vulkan device was lost (VK_ERROR_DEVICE_LOST); closing. If this repeats, update the graphics driver or turn off Settings > Video > Vulkan Renderer.")
			break
		}
		if client.settings_dirty {
			client.settings_dirty = false
			client_settings_save(client_settings_snapshot(client))
		}
		software_cursor_render(client)
		swap_start := glfw.GetTime()
		phase_mark(.SWAP_BUFFERS)
		gpu_present(client.window)
		gpu_frame_end()
		client_collect_gpu_times(client)
		swap_end := glfw.GetTime()
		client_vrr_frame(client)
		client_vrr_update(client)
		// Wait first, then read window input, so the next frame starts from
		// the newest keyboard state (mouse motion is read in client_tick).
		phase_mark(.IDLE_WAIT)
		client_pace_idle_frame(client, frame_start, client_idle_frame_interval(client))
		client_wait_frame_ready(client)
		events_start := glfw.GetTime()
		phase_mark(.POLL_EVENTS)
		client_poll_events()
		client_alt_f4(client.window)
		when SR_DEV {
			prev_swap_ms = f32((swap_end-swap_start)*1000)
			prev_events_ms = f32((glfw.GetTime()-events_start)*1000)
		}
		free_all(context.temp_allocator)
	}
	phase_mark(.SHUTDOWN)
	// Closing must never hang on a network or browser thread: if cleanup takes
	// longer than a few seconds, the process ends anyway.
	client_exit_watchdog_start()
	// Developer builds: save the tester log of a game still in progress.
	when TESTER_EXPORT { tester_export_shutdown(client) }

	client_access_cancel(client)
	delete(client.access.token)
	delete(client.vrr.name)
	delete(client.vrr.source)
	delete(client.access.assignment_url)
	client_unload_map(client)
	net_client_disconnect(&client.net)
	krunker_ws_disconnect(&client.krunker)
	shared.join_link_free(&client.join_link)
	kproto.network_log_clear_secrets()
	kproto.network_log_close()
	delete(client.join_status)
	delete(client.selection_status)
	kproto.krunker_world_reset(&client.krunker_world)
	client_clear_impacts(client)
	client_clear_players(client)
	shared.game_destroy(&client.game)
	shared.unload_default_maps()
	if client.offline_custom_map != nil { shared.map_destroy(client.offline_custom_map) }
	self_shadow_release()
	shadow_fini()
	scene_fini(client.fps_scene)
	scene_fini(client.scene)
	overlay_fini()
	debug_ui_fini(client)
	when SR_DEV { debug_render_fini(&client.debug_render) }
	ui_fini(client.ui)
	resource_cache_fini()
	delete(menu_portraits)
	menu_portraits = nil
	delete(client.predicted_inputs)
}

prefab_init_cb :: proc(object: ^shared.Object, colors: []shared.Vec4, raw_data: json.Value) -> rawptr {
	return rawptr(prefab_init(object, colors, raw_data))
}

cpu_model_name :: proc() -> string {
	when ODIN_OS == .Windows {
		// /proc/cpuinfo does not exist on Windows: the registry has the name.
		return cpu_model_name_windows()
	} else {
		cpuinfo, err := os.read_entire_file_from_path("/proc/cpuinfo", context.temp_allocator)
		if err != nil {
			return "Unknown CPU"
		}

		found: string
		cpuinfo_text := string(cpuinfo)
		for line in strings.split_lines_iterator(&cpuinfo_text) {
			if strings.has_prefix(line, "model name") {
				colon := strings.index(line, ":")
				if colon >= 0 {
					found = strings.clone(strings.trim_space(line[colon + 1:]))
					break
				}
			}
		}

		if len(found) > 0 {
			return found
		}

		return "Unknown CPU"
	}
}

print_startup_info :: proc(client: ^Client) {
	fmt.println("======================================================")
	fmt.println("  SR Client (Odin) - Startup Info")
	fmt.println("======================================================")

	major, minor, rev := glfw.GetVersion()
	fmt.printf("  Platform       : GLFW %d.%d.%d\n", major, minor, rev)

	if g_gpu_backend == .Vulkan {
		info := gpu_device_info()
		fmt.printf("  GPU            : %s (%s)\n", info.renderer, info.vendor)
		fmt.printf("  Graphics API   : Vulkan %s\n", info.version)
	} else {
		vendor := cstring(gl.GetString(gl.VENDOR))
		renderer := cstring(gl.GetString(gl.RENDERER))
		version := cstring(gl.GetString(gl.VERSION))

		fmt.printf("  GPU Vendor     : %s\n", vendor)
		fmt.printf("  GPU            : %s\n", renderer)
		fmt.printf("  GL Version     : %s\n", version)
	}
	fmt.printf("  CPU            : %s\n", cpu_model_name())

	monitor := glfw.GetPrimaryMonitor()
	if monitor != nil {
		monitor_name := glfw.GetMonitorName(monitor)
		mode := glfw.GetVideoMode(monitor)
		fmt.printf("  Monitor        : %s (%dx%d@%d)\n", monitor_name, mode.width, mode.height, mode.refresh_rate)
	}

	map_name := "default rotation"
	if len(g_map_name) > 0 {
		map_name = g_map_name
	}
	fmt.printf("  Map            : %s\n", map_name)
	fmt.println("======================================================")
}

g_map_name: string

// Alt+F4 closes SR in every window mode, also while the game holds the
// mouse (Windows normally turns it into WM_CLOSE; this covers every case).
client_alt_f4 :: proc(window: glfw.WindowHandle) {
	alt := glfw.GetKey(window, glfw.KEY_LEFT_ALT) == glfw.PRESS || glfw.GetKey(window, glfw.KEY_RIGHT_ALT) == glfw.PRESS
	if alt && glfw.GetKey(window, glfw.KEY_F4) == glfw.PRESS { glfw.SetWindowShouldClose(window, true) }
}

client_exit_watchdog_start :: proc() {
	thread.create_and_start(proc() {
		time.sleep(5 * time.Second)
		os.exit(0)
	})
}

KRUNKER_WHIZZ_RANGE :: 27

// True when the segment from a to b passes within `range` of point p.
bullet_passes_within :: proc(a, b, p: shared.Vec3, range: f32) -> bool {
	ab := b - a
	length2 := ab.x*ab.x + ab.y*ab.y + ab.z*ab.z
	t: f32 = 0
	if length2 > 0 { t = clamp(((p.x-a.x)*ab.x + (p.y-a.y)*ab.y + (p.z-a.z)*ab.z) / length2, 0, 1) }
	d := a + ab*t - p
	return d.x*d.x + d.y*d.y + d.z*d.z <= range*range
}
