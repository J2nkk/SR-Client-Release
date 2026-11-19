package menu

import "core:fmt"
import "core:math"
import "core:strings"
import clay "../third_party/clay"

SETTINGS_ORANGE :: clay.Color{239, 110, 24, 255}
SETTINGS_BG :: clay.Color{39, 37, 44, 255}
SETTINGS_DARK :: clay.Color{29, 28, 33, 255}
SETTINGS_LINE :: clay.Color{73, 70, 79, 255}
SETTINGS_MUTED :: clay.Color{166, 164, 177, 255}
SETTINGS_TABS := [Settings_Tab]string{.MAIN = "General", .INPUT = "Controls", .VIDEO = "Display", .VISUALS = "Render", .GAMEPLAY = "Game", .AUDIO = "Sound", .EXPERIMENTAL = "Experimental"}

settings_window :: proc(state: ^State, view: View) {
	s := state.scale
	if clay.UI(clay.ID("Overlay"))({
		layout = {sizing = {width = clay.SizingFixed(1360*s), height = clay.SizingFixed(780*s)}, layoutDirection = .TopToBottom},
		backgroundColor = SETTINGS_BG, cornerRadius = clay.CornerRadiusAll(12*s),
		border = {color = {131, 127, 140, 255}, width = clay.BorderOutside(1)},
	}) {
		if clay.UI(clay.ID("SettingsBody"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}}}) {
			if clay.UI(clay.ID("SettingsSidebar"))({
				layout = {sizing = {width = clay.SizingFixed(232*s), height = clay.SizingGrow()}, layoutDirection = .TopToBottom},
				backgroundColor = SETTINGS_DARK, border = {color = SETTINGS_LINE, width = {right = 1}},
			}) {
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(80*s)}, padding = {left = u16(24*s)}, childAlignment = {y = .Center}}}) {
					text("SETTINGS", 28, s, SETTINGS_MUTED)
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(8*s)), childGap = u16(4*s)}}) {
					for tab in Settings_Tab {
						// Like Krunker, no tab is selected while search results are shown.
						settings_button(state, SETTINGS_TABS[tab], "SettingsTab", {kind = .SETTINGS_TAB, index = i32(tab)}, selected = tab == state.settings_tab && !settings_searching(state), align_left = true)
					}
				}
				spacer()
				if state.settings_tab == .VIDEO { settings_crosshair_preview(state) }
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {left = u16(24*s), right = u16(24*s)}, childGap = u16(8*s), childAlignment = {y = .Center}}}) {
					krunker_badge(s)
					text("= same as Krunker", 16, s, SETTINGS_MUTED)
				}
				if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {left = u16(24*s), right = u16(24*s)}, childGap = u16(8*s), childAlignment = {y = .Center}}}) {
					text("*", 20, s, SETTINGS_RESTART_RED)
					text("= needs a restart", 16, s, SETTINGS_MUTED)
				}
				// The window has a fixed height: with the crosshair preview there is no
				// room for this label, and the sidebar grew past the window's bottom
				// border and pushed the footer (Cancel, Save) out of it.
				if state.settings_tab == .VIDEO {
					if clay.UI()({layout = {sizing = {height = clay.SizingFixed(24*s)}}}) {}
				} else {
					if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = clay.PaddingAll(u16(24*s))}}) { text("SR CLIENT", 16, s, SETTINGS_MUTED) }
				}
			}
			if clay.UI(clay.ID("SettingsContent"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom}}) {
				if clay.UI(clay.ID("SettingsHeading"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(80*s)}, padding = {left = u16(32*s), right = u16(32*s)}, childAlignment = {y = .Center}}, backgroundColor = SETTINGS_DARK}) {
					text(settings_searching(state) ? "Search results" : SETTINGS_TABS[state.settings_tab], 28, s)
					spacer()
					// Krunker's header holds a 220px search field (settSearch, placeholder generic.search).
					if clay.UI()({layout = {sizing = {width = clay.SizingFixed(232*s)}, padding = {right = u16(12*s)}}}) { settings_search_field(state) }
					// Krunker's settings header places Reset, Export, then Import (settings.reset/settings.export/settings.import).
					if clay.UI()({layout = {sizing = {width = clay.SizingFixed(132*s)}, padding = {right = u16(12*s)}}}) { settings_button(state, "Reset", "SettingsReset", {kind = .SETTINGS_RESET_OPEN}, enabled = settings_reset_available(state)) }
					if clay.UI()({layout = {sizing = {width = clay.SizingFixed(132*s)}}}) { settings_button(state, "Export", "SettingsExport", {kind = .SETTINGS_EXPORT}) }
					if clay.UI()({layout = {sizing = {width = clay.SizingFixed(132*s), height = clay.SizingFixed(48*s)}, padding = {left = u16(12*s)}}}) { settings_button(state, "Import", "SettingsImport", {kind = .SETTINGS_IMPORT_OPEN}) }
				}
				if clay.UI(clay.ID("SettingsPanel"))({
					layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingGrow()}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(32*s))},
					clip = {vertical = true, childOffset = clay.GetScrollOffset()},
				}) {
					if settings_searching(state) { settings_search_results(state, view) } else { settings_tab_content(state, view, state.settings_tab) }
				}
				settings_scrollbar(state)
			}
		}
		if clay.UI(clay.ID("SettingsFooter"))({
			layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(88*s)}, padding = {left = u16(24*s), right = u16(24*s)}, childGap = u16(24*s), childAlignment = {y = .Center}},
			backgroundColor = SETTINGS_DARK, border = {color = SETTINGS_LINE, width = {top = 1}},
		}) {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(184*s)}}}) { settings_button(state, "Cancel", "SettingsCancel", {kind = .SETTINGS_CANCEL}) }
			spacer()
			message_error := state.number_edit == .NONE && state.settings_message_length > 0 && state.settings_message_error
			text(settings_number_hint(state), 16, s, state.number_invalid || message_error ? clay.Color{255,100,100,255} : SETTINGS_MUTED)
			spacer()
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(184*s)}}}) { settings_button(state, "Save", "SettingsSave", {kind = .SETTINGS_SAVE}, selected = true) }
		}
	}
	settings_dropdown_menu(state, view)
	settings_import_popup(state)
	settings_reset_popup(state)
}

// One tab's sections and rows. Search lays out every tab through this too; the
// row helpers then skip rows that do not match.
settings_tab_content :: proc(state: ^State, view: View, tab: Settings_Tab) {
	values := state.settings_draft
	switch tab {
	case .MAIN:
		settings_mods(state, view)
		settings_section(state, "Performance")
		// Krunker showPing: "Show Ping", interface category, on by default.
		settings_fps_row(state)
		settings_toggle_row(state, "Show Ping", "HudPing", !values.hud.hide_ping, {kind = .HUD_TOGGLE, index = 3})
		// Krunker's Localization > Default Region: where Host creates games.
		settings_section(state, "Localization")
		if settings_search_show(state, "Default Region") {
			if clay.UI(clay.ID("DefaultRegionRow"))(settings_row(state)) {
				settings_label("Default Region", state.scale)
				spacer()
				settings_dropdown_field(state, default_region(values.hud).name, "DefaultRegion", .DEFAULT_REGION)
			}
		}
		settings_note(state, "Import copies your settings from Krunker (Settings > Export there). Export gives you text that Krunker can import.")
	case .INPUT:
		settings_section(state, "Sensitivity")
		settings_sensitivity(state)
		settings_bindings(state)
	case .VIDEO:
		settings_section(state, "Display")
		settings_display_rows(state, view)
		settings_toggle_row(state, "V-Sync", "VSync", values.vsync, {kind = .VSYNC})
		settings_vrr_cap_row(state, view)
		settings_toggle_row(state, "Vulkan Renderer (off = Classic)", "Vulkan", values.vulkan, {kind = .GRAPHICS_API})
		settings_game_fps_limit_row(state)
		if values.show_fps { settings_slider(state, "FPS update rate (ms)", "FpsUpdateRate", f32(fps_update_ms(values.hud)), FPS_UPDATE_MIN_MS, FPS_UPDATE_MAX_MS, {kind = .FPS_UPDATE_RATE}, step = 10) }
		settings_menu_fps_limit_row(state)
		settings_note(state, "Windowed sets the window size and Fullscreen switches the monitor to the chosen resolution. Borderless always uses the monitor's resolution. FPS limit caps the game (Unlimited by default); Menu FPS limit caps menus only. Vulkan Renderer applies on the next start; off is Classic (OpenGL, threads left to Windows, like 0.24).")
		settings_note(state, "VRR cap: with V-Sync on a G-SYNC / FreeSync display, frames are held 3-5 FPS under the refresh rate so V-Sync never adds latency. Auto does this only where VRR is detected; Always does it on any display.")
		settings_section(state, "Interface")
		// Krunker's UI Scale: same values as Krunker (and Krunker settings imports).
		settings_toggle_row(state, "UI Scaling", "UiScaling", !values.hud.ui_scaling_off, {kind = .HUD_TOGGLE, index = 16})
		settings_slider(state, "UI Scale", "UiScale", ui_scale(values.hud), UI_SCALE_MIN, UI_SCALE_MAX, {kind = .HUD_SCALE}, step = 0.1)
		settings_toggle_row(state, "Krunker font", "HudKrunkerFont", !values.hud.classic_font, {kind = .HUD_TOGGLE, index = 12})
		settings_toggle_row(state, "Show HUD", "HudShowHud", !values.hud.hide_hud, {kind = .HUD_TOGGLE, index = 13})
		settings_toggle_row(state, "Timer", "HudTimer", !values.hud.hide_timer, {kind = .HUD_TOGGLE})
		settings_toggle_row(state, "Team round score", "HudRoundScore", !values.hud.hide_round_score, {kind = .HUD_TOGGLE, index = 1})
		settings_toggle_row(state, "Team game score", "HudGameScore", !values.hud.hide_game_score, {kind = .HUD_TOGGLE, index = 2})
		settings_toggle_row(state, "Show nametags", "HudNametags", !values.hud.hide_nametags, {kind = .HUD_TOGGLE, index = 4})
		settings_toggle_row(state, "Show healthbars", "HudHealthbars", !values.hud.hide_healthbars, {kind = .HUD_TOGGLE, index = 5})
		settings_crosshair_color(state, "Team health color", HEALTH_COLOR_FIELD_TEAM)
		settings_crosshair_color(state, "Enemy health color", HEALTH_COLOR_FIELD_ENEMY)
		settings_crosshair_color(state, "Your health (high)", HEALTH_COLOR_FIELD_HUD_HIGH)
		settings_crosshair_color(state, "Your health (low)", HEALTH_COLOR_FIELD_HUD_LOW)
		// Krunker's objOpac / adsObjOpac: the hardpoint marker.
		settings_slider(state, "Objective Info Opacity", "ObjectiveOpacity", objective_opacity(values.hud), 0, 1, {kind = .OBJECTIVE_OPACITY, index = 0}, step = 0.1)
		settings_slider(state, "Objective Info ADS Opacity", "AdsObjectiveOpacity", ads_objective_opacity(values.hud), 0, 1, {kind = .OBJECTIVE_OPACITY, index = 1}, step = 0.1)
		// Krunker's Scope mods: image opacity, borders, size. SR hides both by default.
		settings_slider(state, "Scope opacity", "ScopeOpacity", scope_value(values.hud, 0), 0, 1, {kind = .SCOPE_VALUE, index = 0}, step = 0.1)
		settings_toggle_row(state, "Scope borders", "ScopeBorders", values.hud.scope_borders, {kind = .HUD_TOGGLE, index = 19})
		settings_slider(state, "Scope border opacity", "ScopeBorderOpacity", scope_value(values.hud, 1), 0, 1, {kind = .SCOPE_VALUE, index = 1}, step = 0.1)
		settings_slider(state, "Scope width", "ScopeWidth", scope_value(values.hud, 2), SCOPE_SIZE_MIN, SCOPE_SIZE_MAX, {kind = .SCOPE_VALUE, index = 2}, step = 0.1)
		settings_slider(state, "Scope height", "ScopeHeight", scope_value(values.hud, 3), SCOPE_SIZE_MIN, SCOPE_SIZE_MAX, {kind = .SCOPE_VALUE, index = 3}, step = 0.1)
		settings_note(state, "Krunker's scope mods. SR turns the scope image and the black borders off by default, as competitive players do in Krunker; raise Scope opacity or turn Scope borders on to bring them back.")
		// Krunker showKills ("Display Kill feed", on) and feedLimit ("Killfeed Limit", 1-10, default 8).
		settings_toggle_row(state, "Show killfeed", "HudKillFeed", !values.hud.hide_kill_feed, {kind = .HUD_TOGGLE, index = 6})
		settings_slider(state, "Killfeed limit", "HudKillFeedLimit", f32(kill_feed_limit(values.hud)), 1, KILL_FEED_MAX_LIMIT, {kind = .KILL_FEED_LIMIT}, step = 1)
		settings_crosshair(state)
		settings_hitmarker(state)
		settings_damage(state)
	case .VISUALS:
		settings_quality(state, view)
		settings_visuals(state)
	case .GAMEPLAY:
		settings_viewmodel(state)
		settings_trails(state)
		settings_toggle_row(state, "Bullet holes", "BulletHoles", !values.hud.hide_bullet_holes, {kind = .HUD_TOGGLE, index = 14})
		settings_section(state, "Competitive")
		settings_toggle_row(state, "Auto respawn", "HudAutoRespawn", !values.hud.manual_respawn, {kind = .HUD_TOGGLE, index = 7})
		settings_toggle_row(state, "Enemies on point", "HudEnemyCounter", !values.hud.hide_enemy_counter, {kind = .HUD_TOGGLE, index = 8})
		settings_toggle_row(state, "Leaderboard", "HudLeaderboard", !values.hud.hide_leaderboard, {kind = .HUD_TOGGLE, index = 9})
		settings_toggle_row(state, "Kill counter", "HudKillCounter", !values.hud.hide_kill_counter, {kind = .HUD_TOGGLE, index = 17})
		settings_toggle_row(state, "Death counter", "HudDeathCounter", !values.hud.hide_death_counter, {kind = .HUD_TOGGLE, index = 18})
		settings_toggle_row(state, "Chat", "HudChat", !values.hud.hide_chat, {kind = .HUD_TOGGLE, index = 10})
		settings_note(state, "When you die the camera turns to your killer. With Auto respawn off, click to respawn. Leaderboard: top right like Krunker, with your kills, deaths and the enemies on the point (on 1) under it. Chat: Enter or T to type, Tab switches Team / All, Enter sends, Escape cancels.")
	case .AUDIO:
		settings_section(state, "Volume")
		labels := [4]string{"Master volume", "Effects volume", "Footsteps volume", "UI volume"}
		ids := [4]string{"MasterVolume", "EffectsVolume", "FootstepsVolume", "UiVolume"}
		for label, i in labels { settings_slider(state, label, ids[i], values.audio_volumes[i], 0, 1, {kind = .AUDIO_VOLUME, index = i32(i)}) }
		settings_note(state, "Master volume affects every channel. Set a channel to 0% to mute it.")
	case .EXPERIMENTAL:
		settings_section(state, "Network")
		if settings_search_show(state, "Inputs per second") {
			if clay.UI(clay.ID("InputRateRow"))(settings_row(state)) {
				settings_label("Inputs per second", state.scale)
				spacer()
				settings_dropdown_field(state, INPUT_RATE_LABELS[input_rate_index(values.hud.input_rate)], "InputRate", .INPUT_RATE)
			}
		}
		settings_note(state, "Experimental. How often your movement, aim and shots go to the server, as REAL inputs per second. Krunker's own Network Rate numbers are half the real rate: its 360 really sends up to 720, so 720 is exactly what the browser does (SR's default is 360). 1000 is the most Krunker's protocol allows (1 ms per input). Takes effect right away, no restart.")
		// Dev build: one choice (fixed clock / network thread / off) until testers confirm it,
		// then it moves to the normal client. The normal client keeps the Network thread toggle.
		if SR_DEV {
			if settings_search_show(state, "Input sending") {
				if clay.UI(clay.ID("NetModeRow"))(settings_row(state)) {
					settings_label("Input sending", state.scale)
					spacer()
					settings_dropdown_field(state, NET_MODE_LABELS[net_mode_index(values.hud)], "NetMode", .NET_MODE)
				}
			}
			settings_note(state, "Test the default: it may help hit registration. Fixed clock: your inputs are built and sent at exact intervals on their own thread instead of once per frame, so they never wait for a frame (a hitch, a slow PC, recording). It also does everything Network thread does. Network thread: reads the game connection on its own thread and answers Krunker's ping the moment it arrives; inputs still go out with your frames. Off: everything on the game thread, like before. Changes apply from the next match.")
		} else {
			settings_toggle_row(state, "Network thread", "NetworkThread", values.hud.network_thread, {kind = .HUD_TOGGLE, index = 11})
			settings_note(state, "Reads the game connection on its own thread and answers Krunker's ping the moment it arrives, as the browser does. It does not raise average FPS; it keeps frames smooth when the network spikes and times snapshots by their real arrival. Takes effect right away; switching it off applies from the next match. Turn it off if anything feels wrong.")
		}
		settings_night(state)
	}
}

settings_set_message :: proc(state: ^State, message: string, is_error: bool) {
	state.settings_message_length = copy(state.settings_message[:], message)
	state.settings_message_error = is_error
}

settings_message :: proc(state: ^State) -> string { return string(state.settings_message[:state.settings_message_length]) }

settings_import_close :: proc(state: ^State) {
	state.import_open, state.import_length, state.import_overflow = false, 0, false
}

// Mirrors Krunker's importSettingsPopup: a header, a paste field and one
// Import button. Enter imports; Escape or a click outside closes the popup.
settings_import_popup :: proc(state: ^State) {
	if !state.import_open { return }
	s := state.scale
	state.control_count = 0 // Settings behind the popup ignore Tab and the mouse.
	if clay.UI(clay.ID("ImportPopup"))({
		layout = {sizing = {width = clay.SizingFixed(640*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(28*s)), childGap = u16(16*s), childAlignment = {x = .Center}},
		backgroundColor = SETTINGS_DARK, cornerRadius = clay.CornerRadiusAll(8*s), border = {color = SETTINGS_LINE, width = clay.BorderOutside(1)},
		floating = {attachTo = .ElementWithId, parentId = clay.ID("Overlay").id, zIndex = 20, attachment = {element = .CenterCenter, parent = .CenterCenter}},
	}) {
		text("Import Settings", 28, s)
		text("Copy Paste Settings Text Here", 19, s, SETTINGS_MUTED)
		value := string(state.import_buffer[:state.import_length])
		if clay.UI(clay.ID("ImportText"))({
			layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(96*s)}, padding = clay.PaddingAll(u16(12*s))},
			backgroundColor = {231, 229, 235, 255}, cornerRadius = clay.CornerRadiusAll(4*s), border = {color = WHITE, width = clay.BorderOutside(2)},
			clip = {horizontal = true, vertical = true},
		}) {
			label := len(value) == 0 ? "Press Ctrl+V to paste, or type here." : fmt.tprintf("%s|", shorten(value, 48))
			text(label, 18, s, len(value) == 0 ? SETTINGS_LINE : SETTINGS_DARK)
		}
		// Glorp-style choices: leave keybinds, sensitivity or sound out of the import.
		for part in Import_Part {
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childAlignment = {y = .Center}}}) {
				text(IMPORT_PART_LABELS[part], 20, s)
				spacer()
				on := part not_in state.import_excluded
				if clay.UI()({layout = {sizing = {width = clay.SizingFixed(110*s)}}}) {
					settings_button(state, on ? "On" : "Off", "ImportPart", {kind = .IMPORT_PART, index = i32(part)}, selected = on)
				}
			}
		}
		if state.settings_message_length > 0 && state.settings_message_error { text(settings_message(state), 16, s, {255, 100, 100, 255}) }
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(380*s)}}}) { settings_button(state, "Import", "ImportConfirm", {kind = .SETTINGS_IMPORT}, selected = true) }
	}
}

settings_reset_available :: proc(state: ^State) -> bool { return state.settings_defaults != {} }

// Krunker's resetSettings: confirm("Are you sure you want to reset all your
// settings?"), then every setting and key bind returns to its default. Here
// the reset fills the draft only: Save applies and persists it, Cancel in the
// footer discards it. "Reset <tab> only" is a SR Client extra.
settings_reset_popup :: proc(state: ^State) {
	if !state.reset_open { return }
	s := state.scale
	state.control_count = 0 // Settings behind the popup ignore Tab and the mouse.
	if clay.UI(clay.ID("ResetPopup"))({
		layout = {sizing = {width = clay.SizingFixed(640*s)}, layoutDirection = .TopToBottom, padding = clay.PaddingAll(u16(28*s)), childGap = u16(16*s), childAlignment = {x = .Center}},
		backgroundColor = SETTINGS_DARK, cornerRadius = clay.CornerRadiusAll(8*s), border = {color = SETTINGS_LINE, width = clay.BorderOutside(1)},
		floating = {attachTo = .ElementWithId, parentId = clay.ID("Overlay").id, zIndex = 20, attachment = {element = .CenterCenter, parent = .CenterCenter}},
	}) {
		text("Reset Settings", 28, s)
		text("Are you sure you want to reset all your settings?", 19, s)
		text("Every tab returns to its default, key binds included.", 17, s, SETTINGS_MUTED)
		text("Reset all settings applies and saves at once.", 17, s, SETTINGS_MUTED)
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(380*s)}}}) { settings_button(state, "Reset all settings", "ResetConfirm", {kind = .SETTINGS_RESET}, selected = true) }
		if !settings_searching(state) {
			if clay.UI()({layout = {sizing = {width = clay.SizingFixed(380*s)}}}) { settings_button(state, fmt.tprintf("Reset %s only", SETTINGS_TABS[state.settings_tab]), "ResetTab", {kind = .SETTINGS_RESET, index = 1}) }
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(380*s)}}}) { settings_button(state, "Keep my settings", "ResetCancel", {kind = .SETTINGS_RESET_CLOSE}) }
	}
}

// Escape or a click outside the popup closes it without changing anything.
settings_reset_interact :: proc(state: ^State, input: Input) -> bool {
	if input.escape && !state.previous.escape || input.down && !state.previous.down && !clay.PointerOver(clay.ID("ResetPopup")) {
		state.reset_open, state.pressed, state.focus = false, 0, clay.ID("SettingsReset").id
		return true
	}
	return false // The buttons use the normal press/release and keyboard handling.
}

// Restores the settings one tab shows; HUD flags shown on other tabs keep
// their values.
settings_reset_tab :: proc(draft: ^Settings_Values, defaults: Settings_Values, tab: Settings_Tab) {
	switch tab {
	case .MAIN:
		draft.show_fps, draft.hud.hide_ping = defaults.show_fps, defaults.hud.hide_ping
		draft.hud.default_region = defaults.hud.default_region
	case .INPUT:
		draft.mouse_dpi, draft.sensitivity, draft.ads_sensitivity = defaults.mouse_dpi, defaults.sensitivity, defaults.ads_sensitivity
		draft.invert_mouse, draft.advanced_sensitivity = defaults.invert_mouse, defaults.advanced_sensitivity
		draft.bindings = defaults.bindings
	case .VIDEO:
		draft.display_mode, draft.monitor_index = defaults.display_mode, defaults.monitor_index
		draft.resolution_index, draft.fullscreen_index = defaults.resolution_index, defaults.fullscreen_index
		draft.vsync, draft.vulkan, draft.menu_fps_limit = defaults.vsync, defaults.vulkan, defaults.menu_fps_limit
		hud := defaults.hud
		hud.hide_ping, hud.manual_respawn, hud.hide_enemy_counter = draft.hud.hide_ping, draft.hud.manual_respawn, draft.hud.hide_enemy_counter
		hud.hide_leaderboard, hud.hide_chat, hud.network_thread = draft.hud.hide_leaderboard, draft.hud.hide_chat, draft.hud.network_thread
		hud.input_clock, hud.net_mode = draft.hud.input_clock, draft.hud.net_mode
		hud.input_rate = draft.hud.input_rate
		hud.hide_bullet_holes = draft.hud.hide_bullet_holes
		hud.vrr_cap = defaults.hud.vrr_cap
		hud.hide_kill_counter, hud.hide_death_counter = draft.hud.hide_kill_counter, draft.hud.hide_death_counter
		draft.hud = hud
		draft.crosshair, draft.hitmarker, draft.damage = defaults.crosshair, defaults.hitmarker, defaults.damage
	case .VISUALS:
		night, strength := draft.visuals.night_mode, draft.visuals.night_strength
		draft.visuals, draft.quality = defaults.visuals, defaults.quality
		draft.visuals.night_mode, draft.visuals.night_strength = night, strength
	case .GAMEPLAY:
		draft.fov, draft.viewmodel, draft.trails = defaults.fov, defaults.viewmodel, defaults.trails
		draft.hud.manual_respawn, draft.hud.hide_enemy_counter = defaults.hud.manual_respawn, defaults.hud.hide_enemy_counter
		draft.hud.hide_leaderboard, draft.hud.hide_chat = defaults.hud.hide_leaderboard, defaults.hud.hide_chat
		draft.hud.hide_bullet_holes = defaults.hud.hide_bullet_holes
		draft.hud.hide_kill_counter, draft.hud.hide_death_counter = defaults.hud.hide_kill_counter, defaults.hud.hide_death_counter
	case .AUDIO:
		draft.audio_volumes = defaults.audio_volumes
	case .EXPERIMENTAL:
		draft.hud.network_thread = defaults.hud.network_thread
		draft.hud.input_clock, draft.hud.net_mode = defaults.hud.input_clock, defaults.hud.net_mode
		draft.hud.input_rate = defaults.hud.input_rate
		draft.visuals.night_mode, draft.visuals.night_strength = defaults.visuals.night_mode, defaults.visuals.night_strength
	}
}

settings_import_interact :: proc(state: ^State, input: Input) -> (action: Action, handled: bool) {
	if input.escape && !state.previous.escape {
		settings_import_close(state)
		state.settings_message_length, state.pressed, state.focus = 0, 0, clay.ID("SettingsImport").id
		return {}, true
	}
	if input.clear_text { state.import_length, state.import_overflow = 0, false }
	if input.backspace && !state.previous.backspace && state.import_length > 0 {
		state.import_length -= 1
		state.import_overflow = false
	}
	if len(input.text) > 0 { state.settings_message_length = 0 }
	for i in 0..<len(input.text) {
		c := input.text[i]
		if c < 32 { c = ' ' } // Pasted line breaks and tabs are JSON whitespace.
		if state.import_length >= len(state.import_buffer) { state.import_overflow = true; break }
		state.import_buffer[state.import_length] = c
		state.import_length += 1
	}
	if input.enter && !state.previous.enter { return activate(state, {action = {kind = .SETTINGS_IMPORT}}), true }
	if input.down && !state.previous.down && !clay.PointerOver(clay.ID("ImportPopup")) {
		settings_import_close(state)
		state.settings_message_length, state.pressed = 0, 0
		return {}, true
	}
	return {}, false // The Import button uses the normal press/release handling.
}

settings_button :: proc(state: ^State, label, name: string, action: Action, selected: bool = false, align_left: bool = false, enabled: bool = true) {
	s := state.scale
	// Cycling display mode keeps the same focus target as its action changes.
	id := clay.ID(name, action.kind == .DISPLAY_MODE ? 0 : u32(action.index))
	register(state, {id = id, action = action, enabled = enabled})
	color := selected ? SETTINGS_ORANGE : clay.Color{57, 54, 64, 255}
	if enabled && clay.PointerOver(id) { color = selected ? clay.Color{255, 128, 40, 255} : clay.Color{73, 68, 81, 255} }
	if state.pressed == id.id { color = {177, 76, 18, 255} }
	if clay.UI(id)({
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, padding = {left = u16(20*s), right = u16(20*s)}, childAlignment = {x = align_left ? .Left : .Center, y = .Center}},
		backgroundColor = color, cornerRadius = clay.CornerRadiusAll(3*s),
		border = {color = state.focus == id.id ? WHITE : SETTINGS_LINE, width = clay.BorderOutside(state.focus == id.id ? 2 : 1)},
	}) { text(label, 21, s, enabled ? WHITE : SETTINGS_MUTED) }
}

settings_scrollbar :: proc(state: ^State) {
	data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
	if !data.found || data.contentDimensions.height <= data.scrollContainerDimensions.height+1 { return }
	s := state.scale
	height := data.scrollContainerDimensions.height-24*s
	thumb_height := max(32*s, height*data.scrollContainerDimensions.height/data.contentDimensions.height)
	progress := clamp(-data.scrollPosition[1]/(data.contentDimensions.height-data.scrollContainerDimensions.height), 0, 1)
	if clay.UI(clay.ID("SettingsScrollTrack"))({
		layout = {sizing = {width = clay.SizingFixed(max(14,16*s)), height = clay.SizingFixed(height)}, layoutDirection = .TopToBottom}, backgroundColor = SETTINGS_LINE, cornerRadius = clay.CornerRadiusAll(4*s),
		floating = {attachTo = .ElementWithId, parentId = clay.ID("SettingsPanel").id, zIndex = 11, pointerCaptureMode = .Passthrough, attachment = {element = .RightTop, parent = .RightTop}, offset = {-8*s, 12*s}},
	}) {
		if clay.UI()({layout = {sizing = {height = clay.SizingFixed(progress*(height-thumb_height))}}}) {}
		thumb_color := state.scrollbar_dragging ? SETTINGS_ORANGE : clay.PointerOver(clay.ID("SettingsScrollThumb")) ? WHITE : SETTINGS_MUTED
		if clay.UI(clay.ID("SettingsScrollThumb"))({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(thumb_height)}}, backgroundColor = thumb_color, cornerRadius = clay.CornerRadiusAll(4*s)}) {}
	}
}

settings_scrollbar_interact :: proc(state: ^State, input: Input) -> bool {
	if (state.page != .SETTINGS && state.page != .CONTROLS) || state.settings_dropdown != .NONE || input.escape {
		state.scrollbar_dragging = false
		return false
	}
	data := clay.GetScrollContainerData(clay.ID("SettingsPanel"))
	track := clay.GetElementData(clay.ID("SettingsScrollTrack"))
	thumb := clay.GetElementData(clay.ID("SettingsScrollThumb"))
	if !data.found || !track.found || !thumb.found {
		state.scrollbar_dragging = false
		return false
	}
	span := data.contentDimensions.height-data.scrollContainerDimensions.height
	travel := track.boundingBox.height-thumb.boundingBox.height
	if span <= 0 || travel <= 0 { state.scrollbar_dragging = false; return false }
	if input.down && !state.previous.down && clay.PointerOver(clay.ID("SettingsScrollTrack")) && contains(track.boundingBox, input.pointer) {
		state.scrollbar_dragging = true
		// Grabbing the thumb preserves its position. Clicking the empty track
		// centers it on the pointer, then lets the same press drag it further.
		state.scrollbar_grab = contains(thumb.boundingBox, input.pointer) ? input.pointer[1]-thumb.boundingBox.y : thumb.boundingBox.height/2
		state.pressed = 0
	}
	if !state.scrollbar_dragging { return false }
	if !input.down {
		state.scrollbar_dragging = false
		return true // Consume the release, even outside the scrollbar.
	}
	progress := clamp((input.pointer[1]-track.boundingBox.y-min(state.scrollbar_grab,thumb.boundingBox.height))/travel, 0, 1)
	data.scrollPosition[1] = -progress*span
	return true
}

settings_section :: proc(state: ^State, label: string) {
	if settings_searching(state) {
		// Defer the heading until a row in this section matches.
		state.search_section, state.search_section_pending = label, true
		state.search_section_match = state.search_tab_match || fuzzy_match(settings_search_query(state), label)
		return
	}
	settings_section_label(label, state.scale)
}

settings_section_label :: proc(label: string, s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(48*s)}, childAlignment = {y = .Center}}}) { text(label, 17, s, SETTINGS_ORANGE) }
}

settings_note :: proc(state: ^State, label: string) {
	if settings_searching(state) { return } // Krunker's results list only settings.
	s := state.scale
	if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, padding = {top = u16(20*s), bottom = u16(16*s)}}}) { text(label, 16, s, SETTINGS_MUTED) }
}

// These rows reserve the same label column in every category.
settings_row :: proc(state: ^State) -> clay.ElementDeclaration {
	s := state.scale
	return {
		layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(72*s)}, childGap = u16(24*s), childAlignment = {y = .Center}},
		border = {color = {57, 54, 64, 255}, width = {bottom = 1}},
	}
}

SETTINGS_RESTART_RED :: clay.Color{235, 47, 47, 255}

settings_label :: proc(label: string, s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(304*s)}, childGap = u16(8*s), childAlignment = {y = .Center}}}) {
		text(label, 21, s)
		if krunker_label(label) { krunker_badge(s) }
		if restart_label(label) { text("*", 24, s, SETTINGS_RESTART_RED) }
	}
}

// Settings that only take effect after SR is restarted: marked with a red *.
RESTART_LABELS :: [?]string{"Vulkan Renderer (off = Classic)"}

restart_label :: proc(label: string) -> bool {
	for name in RESTART_LABELS { if name == label { return true } }
	return false
}

// Rows imported 1:1 from Krunker's settings (Settings > Import) and exported
// back the same way. Everything else is SR Client's own.
KRUNKER_MATCHING_LABELS :: [?]string{
	"Default Region", "Type", "Image link", "Image width", "Image height", "Use custom opacity", "Custom opacity", "Always show",
	"Color", "Shadow color", "Shadow thickness", "Thickness", "Size", "Gap", "Dot",
	"Show hitmarkers", "Hitmarker opacity", "Hitmarker length", "Hitmarker thickness", "Hitmarker spacing",
	"Hitmarker anim size", "Hitmarker fade speed", "Hitmarker color", "Hitmarker kill color",
	"Use Damage Overlay", "Show Hit Indicators", "Hit Indicator Color",
	"Weapon FOV", "Weapon bobbing", "Weapon leaning", "Weapon rotation", "Weapon X offset", "Weapon Y offset",
	"Weapon Z offset", "Weapon ADS Y offset", "Weapon swap Y", "Weapon reload Y", "Weapon ADS FOV power",
	"Toggle weapon ADS", "Weapon aim animation", "Hide weapon on ADS", "Show hands", "Show primary",
	"Show secondary", "Show melee", "Left handed",
	"Bullet trails", "Your trails", "Show killfeed", "Killfeed limit", "Show FPS", "Show Ping", "Field of view (FOV)", "Invert mouse",
	"Master volume", "Effects volume", "Footsteps volume", "UI volume", "Saturation",
	"Shadows", "Soft Shadows", "High-Res Shadows", "Dynamic Shadows", "Lighting",
	"Objective Info Opacity", "Objective Info ADS Opacity",
}

krunker_label :: proc(label: string) -> bool {
	for candidate in KRUNKER_MATCHING_LABELS { if candidate == label { return true } }
	return false
}

// The orange "K" next to a row that works exactly like Krunker's setting.
krunker_badge :: proc(s: f32) {
	if clay.UI()({layout = {sizing = {width = clay.SizingFixed(20*s), height = clay.SizingFixed(20*s)}, childAlignment = {x = .Center, y = .Center}}, backgroundColor = SETTINGS_ORANGE, cornerRadius = clay.CornerRadiusAll(3*s)}) {
		text("K", 14, s, clay.Color{20, 18, 24, 255})
	}
}

// Windowed uses the fixed presets; exclusive fullscreen uses the selected
// monitor's video modes. Borderless always covers the monitor at its own size.
settings_resolution_options :: proc(state: ^State, view: View) -> []string {
	switch state.settings_draft.display_mode {
	case 0: return view.resolution_options
	case 2: return view.fullscreen_options
	}
	return nil
}

settings_resolution_label :: proc(state: ^State, view: View) -> string {
	if state.settings_draft.display_mode == 2 && len(view.fullscreen_options) > 0 {
		return view.fullscreen_options[clamp(int(state.settings_draft.fullscreen_index), 0, len(view.fullscreen_options)-1)]
	}
	// Follow the live window until the user explicitly stages a windowed size.
	// The saved preset can differ from a resized or borderless window.
	if len(view.resolution_options) > 0 && (len(view.resolution) == 0 || state.settings_resolution_selected && state.settings_draft.display_mode == 0) {
		return view.resolution_options[clamp(int(state.settings_draft.resolution_index), 0, len(view.resolution_options)-1)]
	}
	return view.resolution
}

// Measured on the test PC (PresentMon): Fullscreen and Borderless both present
// straight to the screen (Legacy Flip, ~0.15 ms); Windowed is composed by
// Windows (Copy with GPU GDI, ~5.6 ms).
DISPLAY_MODE_NOTE :: "Fullscreen or Borderless recommended: both send frames straight to the screen. Windowed goes through the Windows desktop compositor and adds about 5 ms of delay."

settings_display_rows :: proc(state: ^State, view: View) {
	s := state.scale
	values := state.settings_draft
	labels := [3]string{"Windowed", "Borderless", "Fullscreen"}
	if settings_search_show(state, "Video mode") {
		if clay.UI(clay.ID("DisplayModeRow"))(settings_row(state)) {
			settings_label("Video mode", s)
			spacer()
			settings_dropdown_field(state, labels[clamp(values.display_mode, 0, 2)], "DisplayMode", .DISPLAY_MODE)
		}
		settings_note(state, DISPLAY_MODE_NOTE)
	}
	if settings_current_tab(state) == .VIDEO && settings_search_show(state, "Monitor") {
		if clay.UI(clay.ID("MonitorRow"))(settings_row(state)) {
			settings_label("Monitor", s)
			spacer()
			label := len(view.monitor_names) > 0 ? view.monitor_names[clamp(int(values.monitor_index), 0, len(view.monitor_names)-1)] : "Primary monitor"
			settings_dropdown_field(state, shorten(label, 28), "Monitor", .MONITOR, len(view.monitor_names) > 0)
		}
	}
	if settings_search_show(state, "Window resolution") {
		if clay.UI(clay.ID("ResolutionRow"))(settings_row(state)) {
			settings_label("Window resolution", s)
			spacer()
			label := settings_resolution_label(state, view)
			settings_dropdown_field(state, label, "Resolution", .RESOLUTION, len(settings_resolution_options(state, view)) > 0)
		}
	}
}

settings_toggle_row :: proc(state: ^State, label, name: string, value: bool, action: Action) {
	if !settings_search_show(state, label) { return }
	if clay.UI(clay.ID(fmt.tprintf("%sRow", name)))(settings_row(state)) {
		settings_label(label, state.scale)
		spacer()
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(128*state.scale)}}}) {
			settings_button(state, value ? "On" : "Off", name, action, selected = value)
		}
	}
}

settings_fps_row :: proc(state: ^State) {
	if !settings_search_show(state, "Show FPS") { return }
	if clay.UI(clay.ID("FpsRow"))(settings_row(state)) {
		settings_label("Show FPS", state.scale)
		spacer()
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(128*state.scale)}}}) {
			settings_button(state, state.settings_draft.show_fps ? "On" : "Off", "Fps", {kind = .FPS}, selected = state.settings_draft.show_fps)
		}
	}
}

// Curved sliders: a slider's position is |value|^(1/curve) of its range, so
// with curve > 1 small magnitudes get more of the bar (curve 2: the first 20%
// of a 0-100 slider covers 0-4). Ranges spanning zero curve symmetrically
// around it. Dragging a curved slider snaps to its step. curve <= 1 is linear
// and unsnapped, as before.
slider_progress :: proc(value, minimum, maximum, curve: f32) -> f32 {
	if maximum <= minimum { return 0 }
	if curve <= 1 { return clamp((value - minimum) / (maximum - minimum), 0, 1) }
	if minimum < 0 && maximum > 0 {
		t := value < 0 ? -math.pow(clamp(value / minimum, 0, 1), 1 / curve) : math.pow(clamp(value / maximum, 0, 1), 1 / curve)
		return (t + 1) * 0.5
	}
	return math.pow(clamp((value - minimum) / (maximum - minimum), 0, 1), 1 / curve)
}

slider_value_at :: proc(progress, minimum, maximum, curve, step: f32) -> f32 {
	p := clamp(progress, 0, 1)
	value: f32
	if curve <= 1 {
		value = minimum + p * (maximum - minimum)
	} else if minimum < 0 && maximum > 0 {
		t := p * 2 - 1
		value = t < 0 ? -math.pow(-t, curve) * -minimum : math.pow(t, curve) * maximum
	} else {
		value = minimum + math.pow(p, curve) * (maximum - minimum)
	}
	if step > 0 && curve > 1 { value = math.round(value / step) * step }
	places := settings_slider_places(minimum, maximum, step)
	value = math.round(value*places)/places // 0.6, 0.7 (more only where the range needs it)
	return clamp(value, minimum, maximum)
}

// 10^decimals for a slider: one decimal (0.6, 0.7), none for whole steps, two
// on 0..1 ranges (opacity, hitmarker animation 0.14) and four below 0.1
// (Krunker's hitmarker fade is 0.0062). Sensitivity has its own control.
settings_slider_places :: proc(minimum, maximum: f32, step: f32 = 0) -> f32 {
	switch {
	case maximum-minimum < 0.1: return 10000
	case step >= 1: return 1
	case step >= 0.1: return 10
	case maximum-minimum <= 1: return 100 // 0..1 values: opacity 0.55, volume 25%
	}
	return 10
}

// A setting's number with the slider's decimals and no trailing zeros: 0.7, 1.5, 90.
settings_number_text :: proc(value: f32, places: f32 = 1000) -> string {
	text: string
	switch {
	case places >= 10000: text = fmt.tprintf("%.4f", value)
	case places >= 1000: text = fmt.tprintf("%.3f", value)
	case places >= 100: text = fmt.tprintf("%.2f", value)
	case places >= 10: text = fmt.tprintf("%.1f", value)
	case: text = fmt.tprintf("%.0f", value)
	}
	// Only decimals lose their trailing zeros (30 stays 30, 0.50 becomes 0.5).
	if strings.contains_rune(text, '.') {
		for len(text) > 1 && text[len(text)-1] == '0' { text = text[:len(text)-1] }
		if len(text) > 0 && text[len(text)-1] == '.' { text = text[:len(text)-1] }
	}
	if text == "-0" { text = "0" }
	return text
}

settings_slider :: proc(state: ^State, label, name: string, value, minimum, maximum: f32, action: Action, step: f32 = 0.05, curve: f32 = 1) {
	if !settings_search_show(state, label) { return }
	s := state.scale
	if clay.UI(clay.ID(fmt.tprintf("%sRow", name)))(settings_row(state)) {
		settings_label(label, s)
		id := clay.ID(name)
		register(state, {id = id, enabled = true, slider = true, action = action, slider_min = minimum, slider_max = maximum, slider_step = step, slider_curve = curve})
		if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(44*s)}, childAlignment = {y = .Center}}, border = {color = WHITE, width = clay.BorderOutside(state.focus == id.id ? 1 : 0)}}) {
			fill_id := clay.ID(fmt.tprintf("%sFill", name))
			progress := clamp(slider_progress(value, minimum, maximum, curve), 0.001, 0.999)
			if clay.UI(fill_id)({layout = {sizing = {width = clay.SizingPercent(progress), height = clay.SizingFixed(4*s)}}, backgroundColor = SETTINGS_ORANGE}) {
				if clay.UI(clay.ID(fmt.tprintf("%sThumb", name)))({layout = {sizing = {width = clay.SizingFixed(12*s), height = clay.SizingFixed(28*s)}}, backgroundColor = SETTINGS_ORANGE, cornerRadius = clay.CornerRadiusAll(3*s), floating = {attachTo = .ElementWithId, parentId = fill_id.id, zIndex = 11, pointerCaptureMode = .Passthrough, clipTo = .AttachedParent, attachment = {element = .CenterCenter, parent = .RightCenter}}}) {}
			}
			if clay.UI()({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(4*s)}}, backgroundColor = {137, 133, 146, 255}}) {}
		}
		value_id := clay.ID(fmt.tprintf("%sValue", name))
		register(state, {id=value_id, action=action, enabled=true, number=true, slider_min=minimum, slider_max=maximum})
		editing := state.number_edit == .SLIDER && state.number_control.id.id == value_id.id
		if clay.UI(value_id)({
			layout = {sizing = {width = clay.SizingFixed(128*s), height = clay.SizingFixed(44*s)}, padding={left=u16(8*s), right=u16(8*s)}, childAlignment = {x = .Center, y = .Center}},
			backgroundColor = editing && state.number_replace ? SETTINGS_ORANGE : clay.Color{231, 229, 235, 255}, cornerRadius = clay.CornerRadiusAll(4*s),
			border={color=editing && state.number_invalid ? clay.Color{255,70,70,255} : state.focus == value_id.id ? WHITE : SETTINGS_LINE, width=clay.BorderOutside(editing || state.focus == value_id.id ? 2 : 0)},
			clip={horizontal=editing, childOffset=clay.GetScrollOffset()},
		}) {
			label := action.kind == .AUDIO_VOLUME ? fmt.tprintf("%s%%", settings_number_text(math.round(value*100), 1)) : settings_number_text(value, settings_slider_places(minimum, maximum, step))
			if editing { label = fmt.tprintf("%s|", string(state.number_buffer[:state.number_length])) }
			text(label, 20, s, SETTINGS_DARK)
		}
	}
}

// Krunker mods: "Browse mods" opens Krunker's own Mods window; the mod picked
// there (Load Mod) is downloaded and swapped in live.
settings_mods :: proc(state: ^State, view: View) {
	if !settings_search_show(state, "Mods") && !settings_search_show(state, "Browse mods") { return }
	s := state.scale
	settings_section(state, "Mods")
	if clay.UI(clay.ID("ModsRow"))(settings_row(state)) {
		settings_label("Krunker mod", s)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}, childAlignment = {y = .Center}}}) {
			text(len(view.mods_active) > 0 ? shorten(view.mods_active, 30) : "None", 16, s, SETTINGS_MUTED)
		}
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(190*s)}}}) { settings_button(state, view.mods_busy ? "Loading..." : "Browse mods", "ModsBrowse", {kind = .MODS_BROWSE}, enabled = view.mods_supported && !view.mods_busy) }
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(120*s)}}}) { settings_button(state, "Remove", "ModsRemove", {kind = .MODS_REMOVE}, enabled = len(view.mods_active) > 0 && !view.mods_busy) }
	}
	if clay.UI(clay.ID("ModsPasteRow"))(settings_row(state)) {
		settings_label("Mod link or zip", s)
		if clay.UI()({layout = {sizing = {width = clay.SizingGrow()}}}) {}
		if clay.UI()({layout = {sizing = {width = clay.SizingFixed(190*s)}}}) { settings_button(state, "Paste link", "ModsPaste", {kind = .MODS_PASTE}, enabled = !view.mods_busy) }
	}
	note := "Browse mods opens Krunker's Mods window. Press Load Mod on any mod and SR Client loads it right away, in the menu or in a match. Or copy a mod's link (Dropbox, Krunker) or the path of a .zip file and press Paste link. Remove goes back to the default files."
	if view.mods_problems > 0 { note = fmt.tprintf("%s The last mod could not be read.", note) }
	settings_note(state, note)
}
