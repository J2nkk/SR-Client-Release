package main

import "base:runtime"
import "core:testing"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"

when ODIN_TEST {
	// The wheel must scroll the host page while the pointer is over one of
	// its text fields (each field clips its text sideways, and Clay alone gave
	// the wheel to that field, which cannot scroll up or down).
	@(test)
	menu_wheel_over_text_field :: proc(t: ^testing.T) {
		logger := context.logger
		context = runtime.default_context()
		context.logger = logger
		if !testing.expect(t, bool(glfw.Init()), "GLFW initialization failed") do return
		defer glfw.Terminate()
		test_gpu := test_gpu_open(1600, 900, "Menu wheel")
		if !testing.expect(t, test_gpu.ok, "no GPU device for the test") do return
		defer test_gpu_close(&test_gpu, t)
		g_test_gpu = &test_gpu
		defer g_test_gpu = nil
		ui := ui_init()
		defer { ui_fini(ui); resource_cache_fini() }
		state: menuui.State
		if !testing.expect(t, menuui.init(&state, menu_measure_text, ui), "menu initialization failed") do return
		defer menuui.fini(&state)
		ui_update(ui, 1600, 900)
		view: menuui.View
		menuui.host_open(&state)
		state.host_tab = .ADVANCED
		menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
		menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
		for field in ([]menuui.Host_Text{.TEAM1, .TEAM2}) {
			panel := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
			if !testing.expect(t, panel.found && panel.contentDimensions.height > panel.scrollContainerDimensions.height, "the Advanced host tab must be taller than its panel") do return
			// Bring the field to the middle of the panel, with room to scroll on.
			area := clay.GetElementData(clay.ID("SettingsPanel")).boundingBox
			box := clay.GetElementData(menuui.host_text_id(field)).boundingBox
			span := panel.contentDimensions.height - panel.scrollContainerDimensions.height
			panel.scrollPosition[1] = clamp(panel.scrollPosition[1] - (box.y - area.y - area.height/2), -span + 50, 0)
			menuui.build(&state, view, {}, ui.width, ui.height, 1.0/60.0)
			box = clay.GetElementData(menuui.host_text_id(field)).boundingBox
			if !testing.expectf(t, box.height > 0 && box.y >= area.y && box.y + box.height <= area.y + area.height, "host text field %v must be inside the panel", field) do return
			before := panel.scrollPosition[1]
			pointer := clay.Vector2{box.x + box.width/2, box.y + box.height/2}
			menuui.build(&state, view, {pointer = pointer}, ui.width, ui.height, 1.0/60.0)
			menuui.build(&state, view, {pointer = pointer, scroll = {0, -1}}, ui.width, ui.height, 1.0/60.0)
			after := clay.GetScrollContainerData(clay.ID("SettingsPanel")).scrollPosition[1]
			testing.expectf(t, after < before, "the wheel over host text field %v must scroll the page (before %v, after %v)", field, before, after)
		}
	}
}
