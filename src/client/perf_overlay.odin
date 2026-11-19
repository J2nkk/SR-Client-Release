package main

import glfw "vendor:glfw"
import menuui "../menu"

// Statistics behind the debug performance window (debug_ui.odin). Everything
// here is fixed-size: recording a frame never allocates, and nothing is
// recorded while the window is closed. GPU time comes from the frame timing
// every backend keeps (gpu_frame_begin/end, gpu_frames_take).

// Developer-only tools (this debug window). Release and tester builds leave
// it false, so the window, its F3 toggle and --perf-overlay are compiled out
// of the frame loop. Build with -define:SR_DEV=true (build.bat dev).
SR_DEV :: #config(SR_DEV, false)

PERF_HISTORY :: 1024 // Frames kept for the time-windowed statistics.
PERF_GRAPH_FRAMES :: 240 // Frames shown as bars in the graph.
PERF_FPS_WINDOW_MS :: 1000 // Average FPS window.
PERF_FRAME_WINDOW_MS :: 2000 // Frame-time average and max window.
PERF_LOW_WINDOW_MS :: 5000 // 1% low window (capped by PERF_HISTORY).
PERF_REFERENCE_FPS := [3]f32{60, 144, 240} // Graph reference lines.
// The window's numbers refresh four times a second (the graph still updates
// every frame); "current" values are the mean over that interval.
PERF_TEXT_REFRESH_MS :: 250

// Counted in scene_draw_mesh and ui_fill_rect_; reset at the start of each frame.
g_draw_calls: u32

Perf_Level :: enum u8 { GOOD, WARN, BAD }

// Parts of the frame outside the CPU (tick + render submission) time:
// SwapBuffers, event polling (window messages and raw mouse input), and the
// remainder (settings saves, the idle wait, allocator reset).
Perf_Split :: enum u8 { SWAP, EVENTS, OTHER }

Perf_Stats :: struct {
	frame_ms, cpu_ms: [PERF_HISTORY]f32,
	split_ms: [Perf_Split][PERF_HISTORY]f32,
	head, count: int, // head is the next write index.
	draw_calls: u32, // Draw calls of the last recorded frame.
	world: Draw_Stats, // World/viewmodel batching and culling stats of that frame.
	gpu_ms: f32, // GPU time of the newest finished frame
	gpu_valid: bool,
	gpu_frames: int, // Finished frames whose GPU time reached the window (tests use it).
	// GPU ms per frame section (gpu_pass_mark), smoothed; 0 = not run.
	pass_ms: [Gpu_Pass]f32,
	// Values shown in the window, refreshed every PERF_TEXT_REFRESH_MS.
	shown: Perf_Summary,
	shown_gpu_ms: f32,
	shown_gpu_valid: bool,
	shown_draw_calls: u32,
	shown_world: Draw_Stats,
	shown_valid: bool,
	since_refresh_ms: f32,
}

Perf_Summary :: struct {
	fps, fps_avg, fps_low: f32,
	frame_ms, frame_avg, frame_max: f32,
	cpu_ms, cpu_avg, cpu_max: f32,
	split_ms, split_avg, split_max: [Perf_Split]f32,
	frames: int,
}

perf_push :: proc(stats: ^Perf_Stats, frame_ms, cpu_ms: f32) {
	stats.frame_ms[stats.head] = max(0, frame_ms)
	stats.cpu_ms[stats.head] = max(0, cpu_ms)
	for part in Perf_Split { stats.split_ms[part][stats.head] = 0 }
	stats.head = (stats.head + 1) % PERF_HISTORY
	stats.count = min(stats.count + 1, PERF_HISTORY)
}

// age 0 is the newest sample; the caller keeps age < stats.count.
perf_sample_index :: proc(stats: ^Perf_Stats, age: int) -> int {
	return (stats.head - 1 - age + PERF_HISTORY) % PERF_HISTORY
}

perf_frame_sample :: proc(stats: ^Perf_Stats, age: int) -> f32 { return stats.frame_ms[perf_sample_index(stats, age)] }

perf_reset :: proc(stats: ^Perf_Stats) {
	stats.head, stats.count, stats.draw_calls, stats.world = 0, 0, 0, {}
	stats.gpu_ms, stats.gpu_valid = 0, false
	stats.shown, stats.shown_valid, stats.since_refresh_ms = {}, false, 0
}

// All values describe the same (previous) frame: its duration, its CPU time,
// and how long its SwapBuffers and event polling took.
perf_overlay_record :: proc(client: ^Client, frame_ms, cpu_ms: f32, swap_ms: f32 = 0, events_ms: f32 = 0) {
	if !client.perf_overlay { return }
	perf_push(&client.perf, frame_ms, cpu_ms)
	newest := perf_sample_index(&client.perf, 0)
	client.perf.split_ms[.SWAP][newest] = max(0, swap_ms)
	client.perf.split_ms[.EVENTS][newest] = max(0, events_ms)
	client.perf.split_ms[.OTHER][newest] = max(0, frame_ms - cpu_ms - swap_ms - events_ms)
	client.perf.draw_calls = g_draw_calls
	client.perf.world = g_draw_stats // Reset per frame by client_render_world.
	perf_refresh_shown(&client.perf)
}

// Snapshots the displayed values once PERF_TEXT_REFRESH_MS of frames have
// passed since the last snapshot (immediately when nothing is shown yet, or
// when forced). "Current" FPS, frame and CPU time become the mean over the
// refresh interval, so the numbers are readable instead of flickering.
perf_refresh_shown :: proc(stats: ^Perf_Stats, force := false) {
	if stats.count > 0 && stats.shown_valid && !force {
		stats.since_refresh_ms += perf_frame_sample(stats, 0)
		if stats.since_refresh_ms < PERF_TEXT_REFRESH_MS { return }
	}
	summary := perf_summary(stats)
	if stats.count > 0 {
		recent := perf_window_frames(stats, PERF_TEXT_REFRESH_MS)
		frame_total, cpu_total: f32
		split_total: [Perf_Split]f32
		for age in 0..<recent {
			index := perf_sample_index(stats, age)
			frame_total += stats.frame_ms[index]
			cpu_total += stats.cpu_ms[index]
			for part in Perf_Split { split_total[part] += stats.split_ms[part][index] }
		}
		summary.frame_ms = frame_total / f32(recent)
		summary.cpu_ms = cpu_total / f32(recent)
		for part in Perf_Split { summary.split_ms[part] = split_total[part] / f32(recent) }
		summary.fps = summary.frame_ms > 0 ? 1000 / summary.frame_ms : 0
	}
	stats.shown = summary
	stats.shown_gpu_ms, stats.shown_gpu_valid = stats.gpu_ms, stats.gpu_valid
	stats.shown_draw_calls = stats.draw_calls
	stats.shown_world = stats.world
	stats.shown_valid = true
	stats.since_refresh_ms = 0
}

// Number of newest frames whose summed time first reaches window_ms (all of
// them when the history is shorter).
perf_window_frames :: proc(stats: ^Perf_Stats, window_ms: f32) -> int {
	total: f32
	for age in 0..<stats.count {
		total += perf_frame_sample(stats, age)
		if total >= window_ms { return age + 1 }
	}
	return stats.count
}

perf_summary :: proc(stats: ^Perf_Stats) -> (summary: Perf_Summary) {
	summary.frames = stats.count
	if stats.count == 0 { return }
	newest := perf_sample_index(stats, 0)
	summary.frame_ms, summary.cpu_ms = stats.frame_ms[newest], stats.cpu_ms[newest]
	for part in Perf_Split { summary.split_ms[part] = stats.split_ms[part][newest] }
	if summary.frame_ms > 0 { summary.fps = 1000 / summary.frame_ms }

	fps_frames := perf_window_frames(stats, PERF_FPS_WINDOW_MS)
	fps_total: f32
	for age in 0..<fps_frames { fps_total += perf_frame_sample(stats, age) }
	if fps_total > 0 { summary.fps_avg = f32(fps_frames) * 1000 / fps_total }

	frame_frames := perf_window_frames(stats, PERF_FRAME_WINDOW_MS)
	frame_total, cpu_total: f32
	split_total: [Perf_Split]f32
	for age in 0..<frame_frames {
		index := perf_sample_index(stats, age)
		frame_total += stats.frame_ms[index]
		cpu_total += stats.cpu_ms[index]
		summary.frame_max = max(summary.frame_max, stats.frame_ms[index])
		summary.cpu_max = max(summary.cpu_max, stats.cpu_ms[index])
		for part in Perf_Split {
			split_total[part] += stats.split_ms[part][index]
			summary.split_max[part] = max(summary.split_max[part], stats.split_ms[part][index])
		}
	}
	summary.frame_avg = frame_total / f32(frame_frames)
	summary.cpu_avg = cpu_total / f32(frame_frames)
	for part in Perf_Split { summary.split_avg[part] = split_total[part] / f32(frame_frames) }

	// 1% low: the FPS of the mean of the slowest 1% of frames (at least one).
	low_frames := perf_window_frames(stats, PERF_LOW_WINDOW_MS)
	worst: [PERF_HISTORY/100 + 1]f32
	keep := clamp(low_frames / 100, 1, len(worst))
	kept := 0
	for age in 0..<low_frames {
		value := perf_frame_sample(stats, age)
		// Insertion into a descending list of the `keep` largest frame times.
		if kept < keep { kept += 1 } else if value <= worst[kept-1] { continue }
		i := kept - 1
		for i > 0 && worst[i-1] < value { worst[i] = worst[i-1]; i -= 1 }
		worst[i] = value
	}
	worst_total: f32
	for value in worst[:kept] { worst_total += value }
	if worst_total > 0 { summary.fps_low = f32(kept) * 1000 / worst_total }
	return
}

// Graph top in ms: the slowest graphed frame with headroom, never below the
// 60 FPS line so the reference lines stay meaningful when frames are fast.
perf_graph_top :: proc(stats: ^Perf_Stats) -> f32 {
	slowest: f32
	for age in 0..<min(stats.count, PERF_GRAPH_FRAMES) { slowest = max(slowest, perf_frame_sample(stats, age)) }
	return max(slowest, 1000.0/60) * 1.15
}

perf_graph_bar_height :: proc(frame_ms, top_ms: f32, height: i32) -> i32 {
	if top_ms <= 0 || height <= 0 { return 0 }
	return clamp(i32(frame_ms / top_ms * f32(height) + 0.5), frame_ms > 0 ? 1 : 0, height)
}

// Green at 144 FPS or better, yellow down to 60 FPS, red below; a frame far
// slower than the recent average is flagged even at high frame rates so a
// hitch stands out.
perf_frame_level :: proc(frame_ms, average_ms: f32) -> Perf_Level {
	if frame_ms > 1000.0/60 || average_ms > 0 && frame_ms > average_ms * 2.5 && frame_ms > 4 { return .BAD }
	if frame_ms > 1000.0/144 || average_ms > 0 && frame_ms > average_ms * 1.5 && frame_ms > 2 { return .WARN }
	return .GOOD
}

perf_level_color :: proc(level: Perf_Level) -> [4]u8 {
	switch level {
	case .GOOD: return {110, 220, 90, 255}
	case .WARN: return {245, 200, 60, 255}
	case .BAD:  return {240, 70, 60, 255}
	}
	return {255, 255, 255, 255}
}

// GPU times (ms, oldest first) of frames that finished since the last call.
perf_gpu_record :: proc(stats: ^Perf_Stats, gpu_ms: []f64) {
	if len(gpu_ms) == 0 { return }
	stats.gpu_ms, stats.gpu_valid = f32(gpu_ms[len(gpu_ms) - 1]), true
	stats.gpu_frames += len(gpu_ms)
}

// Forget the last GPU time (stale once the window reopens).
perf_gpu_reset :: proc(stats: ^Perf_Stats) {
	stats.gpu_valid = false
}

perf_gpu_fini :: proc(stats: ^Perf_Stats) {
	perf_gpu_reset(stats)
}

// Once per frame, after gpu_frame_end: the debug window shows the newest
// finished frame's GPU time (the whole frame, debug window included); while it
// is closed (always, without SR_DEV), the times are discarded.
client_collect_gpu_times :: proc(client: ^Client) {
	passes := gpu_pass_times_take()
	if client.perf_overlay {
		times := make([dynamic]f64, context.temp_allocator)
		gpu_frames_take(&times)
		perf_gpu_record(&client.perf, times[:])
		for ms, pass in passes {
			shown := &client.perf.pass_ms[pass]
			if ms <= 0 { continue }
			shown^ = shown^ <= 0 ? f32(ms) : shown^ * 0.9 + f32(ms) * 0.1
		}
		return
	}
	gpu_frames_take(nil)
}

perf_overlay_set :: proc(client: ^Client, enabled: bool) {
	if enabled == client.perf_overlay { return }
	client.perf_overlay = enabled
	if enabled { perf_reset(&client.perf) } else { perf_gpu_reset(&client.perf) }
}

// The toggle works in gameplay and menus, except while a key bind is being
// captured or a menu text field has the keyboard. Returns true on a toggle.
client_perf_overlay_toggle_update :: proc(client: ^Client, read: proc(glfw.WindowHandle, i32) -> bool = client_binding_down) -> bool {
	typing := client.menu.binding_capture != 0 || client.menu.number_edit != .NONE || client.menu.color_edit != 0 || client.menu.import_open || menuui.settings_search_focused(&client.menu) || menuui.host_typing(&client.menu) || menuui.login_typing(&client.menu)
	// Track the raw key so a key still held after capturing it as a new bind
	// does not toggle the window when the capture ends.
	down := client_action_down(client, .DEBUG_OVERLAY, read)
	pressed := down && !client.last_perf_overlay_key && !typing
	client.last_perf_overlay_key = down
	if pressed { perf_overlay_set(client, !client.perf_overlay) }
	return pressed
}
