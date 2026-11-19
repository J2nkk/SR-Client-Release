package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:testing"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"

when ODIN_TEST {
	// The Account window (email, password, emailed code and the username /
	// Google button) must fit on screen with every control reachable.
	@(test)
	account_window_fits :: proc(t: ^testing.T) {
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		test_gpu := test_gpu_open(1600, 900, "Account window")
		if !testing.expect(t, test_gpu.ok, "no GPU device for the test") do return
		defer test_gpu_close(&test_gpu, t)
		g_test_gpu = &test_gpu
		defer g_test_gpu = nil
		ui := ui_init()
		defer { ui_fini(ui); resource_cache_fini() }
		state: menuui.State
		if !testing.expect(t, menuui.init(&state, menu_measure_text, ui), "menu initialization failed") do return
		defer menuui.fini(&state)
		view: menuui.View
		view.join_status = "FRVR sent a login code to your email. Enter it and press Log in."
		for size in ([][2]i32{{1280, 720}, {1920, 1080}, {2560, 1600}}) {
			test_gpu_resize(size[0], size[1])
			glfw.PollEvents()
			gpu_set_target(test_gpu_current_target(), size[0], size[1])
			ui_update(ui, f32(size[0]), f32(size[1]))
			state.page = .ACCOUNT
			state.login_code_sent = true
			menuui.login_text_set(&state, .EMAIL, "player@example.com")
			menuui.login_text_set(&state, .PASSWORD, "password")
			menuui.login_text_set(&state, .CODE, "123456")
			commands := menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
			commands = menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
			overlay := clay.GetElementData(clay.ID("Overlay")).boundingBox
			testing.expectf(t, overlay.y >= 0 && overlay.y + overlay.height <= ui.height + 1, "the Account window must fit the screen at %v", size)
			found := 0
			for control in state.controls[:state.control_count] {
				box := clay.GetElementData(control.id).boundingBox
				testing.expectf(t, box.width > 0 && box.height > 0 && box.x >= overlay.x - 1 && box.x + box.width <= overlay.x + overlay.width + 1 && box.y >= overlay.y - 1 && box.y + box.height <= overlay.y + overlay.height + 1, "control %v must sit inside the Account window at %v", control.action.kind, size)
				#partial switch control.action.kind {
				case .LOGIN_FIELD, .LOGIN_PASSWORD, .LOGIN_SEND_CODE, .LOGIN_CODE, .LOGIN, .FORGET_BROWSER_SESSION: found += 1
				}
			}
			testing.expectf(t, found == 8, "three fields and five login buttons must be shown at %v (found %d)", size, found)
			testing.expect(t, state.errors == 0, "menu layout reported an error")
			when #config(MENU_PREVIEW, false) {
				gpu_set_clear_color({0.17, 0.17, 0.17})
				gpu_clear(color = true, depth = false)
				menu_render_commands(ui, commands)
				pixels := make([]u8, int(size[0] * size[1] * 3)); defer delete(pixels)
				test_read_rgb(0, 0, size[0], size[1], raw_data(pixels))
				file := make([dynamic]u8); defer delete(file)
				append(&file, ..transmute([]u8)fmt.tprintf("P6\n%d %d\n255\n", size[0], size[1]))
				for row := size[1] - 1; row >= 0; row -= 1 { append(&file, ..pixels[int(row * size[0] * 3):int((row + 1) * size[0] * 3)]) }
				_ = os.write_entire_file(fmt.tprintf("bin/account_%dx%d.ppm", size[0], size[1]), file[:])
			}
		}
	}
}
