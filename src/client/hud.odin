package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:strings"
import gl "vendor:OpenGL"
import glfw "vendor:glfw"
import menuui "../menu"
import clay "../third_party/clay"
import shared "../shared"
import kproto "../krunker"

menu_measure_text :: proc "c" (label: clay.StringSlice, config: ^clay.TextElementConfig, user: rawptr) -> clay.Dimensions {
	context = runtime.default_context()
	ui := cast(^UI)user
	return {ui_measure_text(ui, string(label.chars[:label.length]), f32(config.fontSize)), f32(config.fontSize)}
}

client_join_invite :: proc(client: ^Client, connect_live: proc(^Client, ^shared.Join_Link) -> bool = krunker_ws_connect) {
	if client.access.status == .PENDING { return }
	kproto.network_log_begin()
	invite := menuui.invite(&client.menu)
	kproto.network_log("invite", fmt.tprintf("input bytes=%d link=%s", len(invite), invite))
	if len(invite) == 0 {
		kproto.network_log("invite", "ERROR invite is empty")
		krunker_ws_set_status(client, "Enter or paste a lobby invite first.")
		return
	}

	parsed, ok := shared.join_link_parse(invite)
	if !ok {
		kproto.network_log("invite", "ERROR join_link_parse rejected the invite link")
		krunker_ws_set_status(client, "That is not a supported Krunker lobby link.")
		return
	}
	client_leave_session(client, false)
	shared.join_link_free(&client.join_link)
	client.join_link = parsed
	kproto.krunker_world_reset(&client.krunker_world)

	if parsed.scheme == "http" || parsed.scheme == "https" || parsed.scheme == "game" {
		if len(parsed.game_id) == 0 {
			kproto.network_log("invite", "ERROR browser invite is missing its game id")
			krunker_ws_set_status(client, "The invite URL is missing its game id.")
		} else {
			net_client_disconnect(&client.net)
			connect_live(client, &client.join_link)
		}
		return
	}
	if parsed.scheme == "ws" || parsed.scheme == "wss" {
		net_client_disconnect(&client.net)
		connect_live(client, &client.join_link)
		return
	}
	if len(parsed.host) == 0 {
		krunker_ws_set_status(client, "The lobby link does not contain a server host.")
		return
	}

	port := parsed.port
	if port <= 0 { port = 21015 }
	net_client_disconnect(&client.net)
	client_clear_players(client)
	client.game.is_local = false
	new_net, connected := net_client_connect(parsed.host, int(port))
	client.net = new_net
	if connected {
		krunker_ws_set_status(client, fmt.tprintf("Connected to %s:%d.", parsed.host, port))
	} else {
		krunker_ws_set_status(client, fmt.tprintf("Could not connect to %s:%d; staying offline.", parsed.host, port))
	}
}

menu_color :: proc(color: clay.Color) -> shared.Vec4 { return {color[0] / 255, color[1] / 255, color[2] / 255, color[3] / 255} }

menu_render_commands :: proc(ui: ^UI, commands: clay.ClayArray(clay.RenderCommand)) {
	clips: [32]clay.BoundingBox
	clip_count := 0
	for command in commands.internalArray[:commands.length] {
		box := command.boundingBox
		switch command.commandType {
		case .Rectangle:
			data := command.renderData.rectangle
			if box.width > 0 && box.height > 0 { ui_round_rect(ui, menu_color(data.backgroundColor), box.x, box.y, box.width, box.height, data.cornerRadius.topLeft) }
		case .Text:
			data := command.renderData.text
			// Clay already offsets each line for its configured line height.
			// Add only the font ascent here, otherwise leading is applied twice.
			ascent, descent, gap: i32
			stb_font_metrics(&ascent, &descent, &gap)
			baseline := box.y + f32(data.fontSize) * f32(ascent) / f32(ascent - descent)
			ui_fill_text(ui, menu_color(data.textColor), string(data.stringContents.chars[:data.stringContents.length]), box.x, baseline, f32(data.fontSize))
		case .Border:
			data := command.renderData.border
			color := menu_color(data.color)
			if data.width.left > 0 { ui_fill_rect(ui, color, box.x, box.y, f32(data.width.left), box.height) }
			if data.width.right > 0 { ui_fill_rect(ui, color, box.x + box.width - f32(data.width.right), box.y, f32(data.width.right), box.height) }
			if data.width.top > 0 { ui_fill_rect(ui, color, box.x, box.y, box.width, f32(data.width.top)) }
			if data.width.bottom > 0 { ui_fill_rect(ui, color, box.x, box.y + box.height - f32(data.width.bottom), box.width, f32(data.width.bottom)) }
		case .ScissorStart:
			assert(clip_count < len(clips))
			if clip_count > 0 {
				parent := clips[clip_count - 1]
				right := min(box.x + box.width, parent.x + parent.width)
				bottom := min(box.y + box.height, parent.y + parent.height)
				box.x = max(box.x, parent.x); box.y = max(box.y, parent.y)
				box.width = max(0, right - box.x); box.height = max(0, bottom - box.y)
			}
			clips[clip_count] = box
			clip_count += 1
			ui_clip_set(ui, box)
		case .ScissorEnd:
			clip_count = max(0, clip_count - 1)
			if clip_count == 0 { ui_clip_clear(ui) }
			else { ui_clip_set(ui, clips[clip_count - 1]) }
		case .Image:
			texture := Gpu_Texture(uintptr(command.renderData.image.imageData))
			if texture != 0 { ui_draw_image(ui, texture, box.x, box.y, box.width, box.height) }
		case .Custom:
			if command.id == clay.ID("CrosshairPreview").id && command.renderData.custom.customData != nil {
				data := command.renderData.custom
				preview := cast(^menuui.Crosshair_Preview)data.customData
				// Keep extreme size/gap values inside the preview, intersecting
				// any existing menu clip and restoring it for following commands.
				clip := box
				if clip_count > 0 {
					parent := clips[clip_count-1]
					right, bottom := min(clip.x+clip.width,parent.x+parent.width), min(clip.y+clip.height,parent.y+parent.height)
					clip.x, clip.y = max(clip.x,parent.x), max(clip.y,parent.y)
					clip.width, clip.height = max(0,right-clip.x), max(0,bottom-clip.y)
				}
				ui_clip_set(ui, clip)
				crosshair_render(ui, preview.settings, box.x+box.width*0.5, box.y+box.height*0.5, preview.scale, menuui.crosshair_opacity(preview.settings, 1))
				hit_marker_preview(ui, preview.hitmarker, box.x+box.width*0.5, box.y+box.height*0.5, preview.scale, glfw.GetTime())
				if clip_count > 0 { ui_clip_set(ui, clips[clip_count-1]) } else { ui_clip_clear(ui) }
			}
			if command.id == clay.ID("DamagePreview").id && command.renderData.custom.customData != nil {
				preview := cast(^menuui.Damage_Preview)command.renderData.custom.customData
				ui_clip_set(ui, box)
				damage_preview_render(ui, preview.settings, box.x, box.y, box.width, box.height, glfw.GetTime())
				if clip_count > 0 { ui_clip_set(ui, clips[clip_count-1]) } else { ui_clip_clear(ui) }
			}
		case .None, .OverlayColorStart, .OverlayColorEnd:
		}
	}
	ui_clip_clear(ui)
}

// pointer_blocked is set while the pointer is over (or dragging) the debug
// window, so its clicks and scroll never reach the menu underneath.
hud_render :: proc(client: ^Client, delta: f32, pointer_blocked := false) {
	width, height := glfw.GetWindowSize(client.window)
	x, y := glfw.GetCursorPos(client.window)
	input := menuui.Input{
		pointer = {f32(x) * client.ui.width / f32(max(width, 1)), f32(y) * client.ui.height / f32(max(height, 1))},
		down = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_LEFT) == glfw.PRESS,
		tab = glfw.GetKey(client.window, glfw.KEY_TAB) == glfw.PRESS,
		shift = glfw.GetKey(client.window, glfw.KEY_LEFT_SHIFT) == glfw.PRESS,
		enter = glfw.GetKey(client.window, glfw.KEY_ENTER) == glfw.PRESS,
		escape = glfw.GetKey(client.window, glfw.KEY_ESCAPE) == glfw.PRESS,
		left = glfw.GetKey(client.window, glfw.KEY_LEFT) == glfw.PRESS,
		right = glfw.GetKey(client.window, glfw.KEY_RIGHT) == glfw.PRESS,
		scroll = client.menu_scroll,
		text = string(client.menu_text[:client.menu_text_length]),
		backspace = client_backspace_repeat(client),
		now = glfw.GetTime(),
		delete_key = glfw.GetKey(client.window, glfw.KEY_DELETE) == glfw.PRESS,
		right_down = glfw.GetMouseButton(client.window, glfw.MOUSE_BUTTON_RIGHT) == glfw.PRESS,
		clear_text = glfw.GetKey(client.window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS && glfw.GetKey(client.window, glfw.KEY_A) == glfw.PRESS,
		paste = glfw.GetKey(client.window, glfw.KEY_LEFT_CONTROL) == glfw.PRESS && glfw.GetKey(client.window, glfw.KEY_V) == glfw.PRESS,
		up = glfw.GetKey(client.window, glfw.KEY_UP) == glfw.PRESS,
		down_key = glfw.GetKey(client.window, glfw.KEY_DOWN) == glfw.PRESS,
		binding_pressed = client.binding_event,
	}
	client.binding_event = 0
	if pointer_blocked { debug_ui_block_menu_input(&input) }
	if (client.menu.number_edit != .NONE || client.menu.color_edit != 0 || client.menu.import_open || menuui.settings_search_focused(&client.menu) || menuui.host_typing(&client.menu) || menuui.login_typing(&client.menu)) && input.paste && !client.menu.previous.paste { input.text = glfw.GetClipboardString(client.window) }
	client.menu_scroll = {}
	client.menu_text_length = 0
	phase_mark(.MENU_VIEW)
	view := menu_view(client)
	phase_mark(.MENU_BUILD)
	if client.menu.page == .SETTINGS || client.menu.page == .CONTROLS {
		phase_mark(menuui.settings_searching(&client.menu) ? .SETTINGS_SEARCH : settings_tab_phase(int(client.menu.settings_tab)))
	}
	commands := menuui.build(&client.menu, view, input, client.ui.width, client.ui.height, delta)
	phase_mark(.MENU_RENDER)
	ui_fill_rect(client.ui, {0.015, 0.025, 0.035, 0.55}, 0, 0, client.ui.width, client.ui.height)
	menu_render_commands(client.ui, commands)
	previous_page := client.menu.page
	previous_tab := client.menu.settings_tab
	action := menuui.interact(&client.menu, input, view)
	if client.menu.page != previous_page || client.menu.settings_tab != previous_tab { audio_play_effect(client.audio, "tick_0", .UI, 0.6) }
	phase_mark(.MENU_ACTION)
	menu_apply_action(client, action)
}

// Backspace in menu text fields: the press, then (after 0.4 s held) a repeat
// every 35 ms, like Windows' own key repeat. The menu acts on each rising edge.
client_backspace_repeat :: proc(client: ^Client) -> bool {
	now := glfw.GetTime()
	if glfw.GetKey(client.window, glfw.KEY_BACKSPACE) != glfw.PRESS { client.backspace_since = 0; return false }
	if client.backspace_since == 0 { client.backspace_since, client.backspace_repeat = now, now; return true }
	if now - client.backspace_since < 0.4 { return true }
	if now - client.backspace_repeat >= 0.035 { client.backspace_repeat = now; return false } // release edge, pressed again next frame
	return true
}
