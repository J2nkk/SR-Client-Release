package main

import "base:runtime"
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import win "core:sys/windows"
import access "../browser_access"
import wv "../webview2"

// ABI slots are from Microsoft.Web.WebView2 1.0.3650.58, WebView2.h.
COM :: wv.COM
Handler :: wv.Handler
init_handler :: wv.init_handler
add_ref :: wv.add_ref
release_com :: wv.release_com
get_text :: wv.get_text
Browser :: struct {
	window: win.HWND,
	controller, view: ^COM,
	id, navigation, executing_navigation: u64,
	input, output: win.HANDLE,
	buffer: [dynamic]byte,
	started: time.Time,
	visible, done, executing, probe, sdk_seen, rejected, remembered: bool,
	executing_since: time.Time, // a check that never answers is given up after a few seconds
	waiting_for_login: bool,
	captcha: bool,
	captcha_game: string,
	// SR Client's FRVR session for the verification page (written to its
	// localStorage before the page's scripts run, so its SDK never renews it).
	session_access, session_refresh: string,
	login_requests_sent: int, // login_watch.js lines already sent to SR Client
	ready_since: time.Time,   // first READY answer, while the recorder finishes
	login_rpc_seen: time.Time, // the page's lobby account login (_0 login) was recorded
	// SR Client: Krunker's Mods window; copies the zip of the mod the player
	// loads into SR Client's mods folder (mod_file) and reports it.
	mods: bool,
	mod_file: ^os.File,
	mod_path, mod_url: string,
	mod_size, mod_offset: int,
	mod_debug: string,
	session_path: string,
	last_script_diagnostic: string,
}
browser: Browser
env_handler, controller_handler, script_handler, navigation_handler, popup_handler: Handler
env_vtable, controller_vtable, script_vtable, navigation_vtable, popup_vtable: [4]rawptr
install_handler, message_handler: Handler
message_vtable: [4]rawptr
install_vtable: [4]rawptr

notify :: proc(kind, value: string) {
	if browser.probe {
		fmt.println(kind == "TOKEN" || kind == "SESSION_REFRESH" ? "TOKEN_REDACTED" : kind == "TRACE" ? access.diagnostic_text(value) : access.status_text(value))
		return
	}
	if !access.send(browser.output, access.Message{browser.id, kind, value}) { browser.done = true }
}
login_dump_enabled :: proc() -> bool {
	value, found := os.lookup_env_alloc("SR_LOGIN_DUMP", context.temp_allocator)
	return found && value == "1"
}

// Only state transitions cross IPC; the half-second polling loop stays quiet.
trace_script :: proc(code: string) -> bool {
	text := access.diagnostic_text(code)
	if text == browser.last_script_diagnostic { return false }
	browser.last_script_diagnostic = text
	notify("TRACE", code)
	return true
}
fail :: proc(code: string) { mods_log(fmt.tprintf("ERROR %s", code)); notify("ERROR", code); browser.done = true }

// %LOCALAPPDATA%\SR-Client\mods-log.txt: every step of the Mods window,
// written by the helper itself (not the page), so a failed Load Mod shows
// exactly where it stopped. Repeated lines are written once.
// {"state":"MOD","url":"https://...", ...}: the link without a JSON parser.
mods_link_from_text :: proc(text: string) -> (string, bool) {
	if !strings.contains(text, `"state":"MOD"`) { return "", false }
	key :: `"url":"`
	start := strings.index(text, key)
	if start < 0 { return "", false }
	rest := text[start+len(key):]
	end := strings.index_byte(rest, '"')
	if end <= 0 || end > 4096 { return "", false }
	url := rest[:end]
	if !strings.has_prefix(url, "https://") && !strings.has_prefix(url, "http://") { return "", false }
	return url, true
}

mods_log_last: string
mods_first_check: bool
mods_heartbeat: time.Time
mods_log :: proc(line: string) {
	if !browser.mods || line == mods_log_last { return }
	delete(mods_log_last)
	mods_log_last = strings.clone(line)
	local, found := os.lookup_env_alloc("LOCALAPPDATA", context.temp_allocator)
	if !found || len(local) == 0 { return }
	_ = os.make_directory_all(fmt.tprintf("%s\\SR-Client", local))
	path := fmt.tprintf("%s\\SR-Client\\mods-log.txt", local)
	file, err := os.open(path, {.Write, .Create, .Append})
	if err != nil { return }
	defer os.close(file)
	stamp := time.since(browser.started)
	_, _ = os.write_string(file, fmt.tprintf("[%.1fs] %s\r\n", time.duration_seconds(stamp), line))
}

// %LOCALAPPDATA%\SR-Client\downloads\mod.zip; the client unpacks it from there.
mods_incoming_path :: proc() -> string {
	local, found := os.lookup_env_alloc("LOCALAPPDATA", context.temp_allocator)
	if !found || len(local) == 0 { return "" }
	directory := fmt.tprintf("%s\\SR-Client\\downloads", local)
	_ = os.make_directory_all(directory)
	return fmt.aprintf("%s\\mod.zip", directory)
}

// One base64 chunk of the mod Krunker loaded, at browser.mod_offset.
mods_receive_chunk :: proc(object: json.Object) {
	number :: proc(value: json.Value) -> (int, bool) {
		#partial switch v in value {
		case json.Integer: return int(v), true
		case json.Float: return int(v), true
		}
		return 0, false
	}
	size, has_size := number(object["size"])
	offset, has_offset := number(object["offset"])
	data, has_data := object["data"].(json.String)
	if !has_size || !has_offset || !has_data || offset != browser.mod_offset || size <= 0 || size > 256*1024*1024 { return }
	if browser.mod_file == nil {
		browser.mod_path = mods_incoming_path()
		if len(browser.mod_path) == 0 { fail("MOD_SAVE_FAILED"); return }
		file, err := os.open(browser.mod_path, {.Write, .Create, .Trunc})
		if err != nil { fail("MOD_SAVE_FAILED"); return }
		browser.mod_file, browser.mod_size = file, size
		if url, ok := object["url"].(json.String); ok && len(url) <= 4096 { browser.mod_url = strings.clone(string(url)) }
		win.SetWindowTextW(browser.window, win.L("SR Client - loading the mod..."))
	}
	bytes, err := base64.decode(string(data), allocator = context.temp_allocator)
	if err != nil || len(bytes) == 0 || browser.mod_offset+len(bytes) > browser.mod_size { os.close(browser.mod_file); browser.mod_file = nil; fail("MOD_SAVE_FAILED"); return }
	if written, werr := os.write(browser.mod_file, bytes); werr != nil || written != len(bytes) { os.close(browser.mod_file); browser.mod_file = nil; fail("MOD_SAVE_FAILED"); return }
	browser.mod_offset += len(bytes)
	if browser.mod_offset < browser.mod_size { return }
	os.close(browser.mod_file); browser.mod_file = nil
	if len(browser.mod_url) > 0 { notify("MOD_URL", browser.mod_url) }
	notify("MOD_FILE", browser.mod_path)
	browser.done = true
}
show :: proc() {
	if browser.visible { return }
	browser.visible = true
	win.ShowWindow(browser.window, win.SW_SHOW)
	win.SetForegroundWindow(browser.window)
	notify("STATUS", "VISIBLE")
}
resize :: proc() {
	if browser.controller == nil { return }
	bound: win.RECT
	win.GetClientRect(browser.window, &bound)
	(cast(proc "system" (^COM, win.RECT) -> win.HRESULT)browser.controller.v[6])(browser.controller, bound)
}
window_proc :: proc "system" (window: win.HWND, message: u32, w: win.WPARAM, l: win.LPARAM) -> win.LRESULT {
	context = runtime.default_context()
	switch message {
	case win.WM_CLOSE: notify("ERROR", "CANCELLED"); browser.done = true; return 0
	case win.WM_SIZE: resize(); return 0
	case win.WM_DESTROY: browser.done = true; return 0
	}
	return win.DefWindowProcW(window, message, w, l)
}

environment_ready :: proc "system" (this: rawptr, result: win.HRESULT, env: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 || env == nil { fail("PROFILE_FAILED"); return 0 }
	notify("TRACE", "ENVIRONMENT_READY")
	hr := (cast(proc "system" (^COM, win.HWND, ^Handler) -> win.HRESULT)env.v[3])(env, browser.window, &controller_handler)
	if hr < 0 { fail("PROFILE_FAILED") }
	return 0
}
controller_ready :: proc "system" (this: rawptr, result: win.HRESULT, controller: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 || controller == nil { fail("PROFILE_FAILED"); return 0 }
	browser.controller = controller; add_ref(controller)
	if (cast(proc "system" (^COM, ^^COM) -> win.HRESULT)controller.v[25])(controller, &browser.view) < 0 { fail("HELPER_FAILED"); return 0 }
	notify("TRACE", "CONTROLLER_READY")
	mods_log("browser ready")
	resize()
	(cast(proc "system" (^COM, win.BOOL) -> win.HRESULT)controller.v[4])(controller, true)
	event: i64
	if (cast(proc "system" (^COM, ^Handler, ^i64) -> win.HRESULT)browser.view.v[7])(browser.view, &navigation_handler, &event) < 0 { fail("HELPER_FAILED"); return 0 }
	if (cast(proc "system" (^COM, ^Handler, ^i64) -> win.HRESULT)browser.view.v[44])(browser.view, &popup_handler, &event) < 0 { fail("HELPER_FAILED"); return 0 }
	if browser.captcha {
		game_json, err := json.marshal(browser.captcha_game)
		if err != nil { fail("CAPTCHA_SETUP_FAILED"); return 0 }
		defer delete(game_json)
		script := fmt.tprintf("window.__srCaptchaGame = %s;\n%s", string(game_json), string(#load("captcha.js")))
		if len(browser.session_access) > 0 && len(browser.session_refresh) > 0 {
			access_json, access_err := json.marshal(browser.session_access, allocator = context.temp_allocator)
			refresh_json, refresh_err := json.marshal(browser.session_refresh, allocator = context.temp_allocator)
			if access_err == nil && refresh_err == nil {
				// Concatenation, not fmt: the script's braces are not format braces.
				// Stored JSON-encoded, the FRVR SDK's own format ("\"eyJ...\"").
				script = strings.concatenate({`(() => { try { if (window === window.top && location.origin === 'https://krunker.io') { localStorage.setItem('__FRVR_auth_access_token', JSON.stringify(`, string(access_json), `)); localStorage.setItem('__FRVR_auth_refresh_token', JSON.stringify(`, string(refresh_json), `)); } } catch {} })();`, "\n", script}, context.temp_allocator)
			}
		}
		if (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[27])(browser.view, raw_data(win.utf8_to_utf16(script)), &install_handler) < 0 { fail("CAPTCHA_SETUP_FAILED") }
	} else if browser.mods {
		// add_WebMessageReceived: mods.js pushes the mod link here.
		if (cast(proc "system" (^COM, ^Handler, ^i64) -> win.HRESULT)browser.view.v[34])(browser.view, &message_handler, &event) < 0 { mods_log("message channel could not be opened (polling only)") } else { mods_log("message channel open") }
		if (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[27])(browser.view, raw_data(win.utf8_to_utf16(string(#load("mods.js")))), &install_handler) < 0 { fail("HELPER_FAILED") }
	} else {
		// Browser login: record how the page logs in (field names only), then
		// open Krunker once the recorder is in place (handoff_installed).
		if (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[27])(browser.view, raw_data(win.utf8_to_utf16(string(#load("login_watch.js")))), &install_handler) < 0 {
			if (cast(proc "system" (^COM, ^u16) -> win.HRESULT)browser.view.v[5])(browser.view, win.L("https://krunker.io/")) < 0 { fail("HELPER_FAILED") }
		}
	}
	return 0
}
handoff_installed :: proc "system" (this: rawptr, result: win.HRESULT, data: ^u16) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done { return 0 }
	if result < 0 && !browser.captcha && !browser.mods {
		// The login recorder is optional: open Krunker without it.
		if (cast(proc "system" (^COM, ^u16) -> win.HRESULT)browser.view.v[5])(browser.view, win.L("https://krunker.io/")) < 0 { fail("HELPER_FAILED") }
		return 0
	}
	if result < 0 { fail("CAPTCHA_SETUP_FAILED"); return 0 }
	mods_log("watcher script installed, opening https://krunker.io/")
	notify("TRACE", browser.mods ? "MODS_ARMED" : browser.captcha ? "CAPTCHA_ARMED" : "LOGIN_WATCH_ARMED")
	// An empty game is SR Client's Host: the verification is for the lobby
	// the new custom game is created from.
	url := browser.mods || len(browser.captcha_game) == 0 ? "https://krunker.io/" : fmt.tprintf("https://krunker.io/?game=%s", browser.captcha_game)
	if (cast(proc "system" (^COM, ^u16) -> win.HRESULT)browser.view.v[5])(browser.view, raw_data(win.utf8_to_utf16(url))) < 0 { fail("HELPER_FAILED") }
	return 0
}
// chrome.webview.postMessage from mods.js: '{"state":"MOD","url":"..."}'.
web_message_received :: proc "system" (this: rawptr, sender, args: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	if browser.done || !browser.mods { return 0 }
	text := get_text(args, 5) // TryGetWebMessageAsString
	if len(text) == 0 { text = get_text(args, 4) } // WebMessageAsJson
	if url, found := mods_link_from_text(text); found {
		mods_log(fmt.tprintf("mod link received: %s, sent to SR Client", url))
		notify("MOD", url)
		browser.done = true
	} else {
		mods_log(fmt.tprintf("page message without a mod link: %s", text[:min(len(text), 200)]))
	}
	return 0
}
navigation_starting :: proc "system" (this: rawptr, sender, args: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	browser.navigation += 1
	browser.last_script_diagnostic = ""
	mods_log(fmt.tprintf("page navigating to %s", get_text(args, 3)))
	notify("TRACE", access.official_source(get_text(args, 3)) ? "NAVIGATING_OFFICIAL" : "NAVIGATING_LOGIN")
	// Login redirects may leave the official origin. They receive no native token bridge.
	return 0
}
popup_requested :: proc "system" (this: rawptr, sender, args: ^COM) -> win.HRESULT {
	context = runtime.default_context()
	uri := get_text(args, 3)
	(cast(proc "system" (^COM, win.BOOL) -> win.HRESULT)args.v[6])(args, true)
	if strings.has_prefix(uri, "https://") {
		show()
		wide := win.utf8_to_utf16(uri)
		(cast(proc "system" (^COM, ^u16) -> win.HRESULT)sender.v[5])(sender, raw_data(wide))
	}
	return 0
}
script_completed :: proc "system" (this: rawptr, result: win.HRESULT, data: ^u16) -> win.HRESULT {
	context = runtime.default_context()
	browser.executing = false
	if browser.done || browser.executing_navigation != browser.navigation { mods_log("check skipped: the page navigated meanwhile"); return 0 }
	if result < 0 || data == nil { mods_log(fmt.tprintf("check failed: ExecuteScript error 0x%x", u32(result))); trace_script("SCRIPT_FAILED"); return 0 }
	if !access.official_source(get_text(browser.view, 4)) { mods_log(fmt.tprintf("check ignored: page is %s", get_text(browser.view, 4))); return 0 }
	count := 0
	for count < access.MAX_MESSAGE && (cast([^]u16)data)[count] != 0 { count += 1 }
	if count >= access.MAX_MESSAGE { fail("BAD_TOKEN"); return 0 }
	text := win.utf16_to_utf8((cast([^]u16)data)[:count]) or_else ""
	value, err := json.parse_string(text)
	if err != .None {
		if browser.mods {
			mods_log(fmt.tprintf("check answer could not be read (%v): %s", err, text[:min(len(text), 400)]))
			// The answer's own text still carries the link: take it directly.
			if url, found := mods_link_from_text(text); found {
				mods_log(fmt.tprintf("mod link found: %s, sent to SR Client", url))
				notify("MOD", url)
				browser.done = true
			}
		}
		trace_script("SCRIPT_INVALID_RESULT"); return 0
	}
	defer json.destroy_value(value)
	object, valid := value.(json.Object)
	if !valid { mods_log(fmt.tprintf("check answer is not an object: %s", text[:min(len(text), 200)])); trace_script("SCRIPT_INVALID_RESULT"); return 0 }
	state, ok := object["state"].(json.String)
	if !ok { mods_log(fmt.tprintf("check answer has no state: %s", text[:min(len(text), 200)])); trace_script("SCRIPT_INVALID_RESULT"); return 0 }
	changed := trace_script(string(state))
	if browser.mods {
		_, has_debug := object["debug"].(json.String)
		if string(state) != "WAIT_MODS" || !has_debug { mods_log(fmt.tprintf("check: state=%s watcher=%s", string(state), has_debug ? "running" : "MISSING (page has no __srMods)")) }
		else { mods_log("watcher running, waiting for Load Mod") }
		// A readable record of what the page loaded, for when a mod is missed:
		// %LOCALAPPDATA%\SR-Client\mods-debug.txt
		if debug, ok := object["debug"].(json.String); ok && len(debug) > 0 && string(debug) != browser.mod_debug {
			delete(browser.mod_debug)
			browser.mod_debug = strings.clone(string(debug))
			if local, found := os.lookup_env_alloc("LOCALAPPDATA", context.temp_allocator); found && len(local) > 0 {
				_ = os.write_entire_file(fmt.tprintf("%s\\SR-Client\\mods-debug.txt", local), transmute([]byte)string(debug))
			}
		}
		switch string(state) {
		case "MOD":
			url, valid := object["url"].(json.String)
			if !valid || len(url) == 0 || len(url) > 4096 || !(strings.has_prefix(string(url), "https://") || strings.has_prefix(string(url), "http://")) { mods_log("mod state without a usable link"); return 0 }
			mods_log(fmt.tprintf("mod link found: %s, sent to SR Client", string(url)))
			notify("MOD", string(url))
			browser.done = true
		case "MOD_DATA":
			mods_receive_chunk(object)
		}
		return 0
	}
	if browser.captcha {
		switch string(state) {
		case "CAPTCHA_ASSIGNMENT":
			assignment, valid := object["assignment"].(json.String)
			if !valid || len(string(assignment)) == 0 { fail("CAPTCHA_SETUP_FAILED"); return 0 }
			notify("STATUS", "CAPTCHA_ASSIGNMENT")
			notify("ASSIGNMENT", string(assignment))
			browser.done = true
		case "CAPTCHA_READY":
			token, valid := object["token"].(json.String)
			if !valid || !access.captcha_token_valid(string(token)) { fail("CAPTCHA_BAD_TOKEN"); return 0 }
			notify("CAPTCHA", string(token)); browser.done = true
		case "CAPTCHA_BAD_TOKEN", "CAPTCHA_NO_CHALLENGE", "CAPTCHA_LOGIN_REQUIRED", "CAPTCHA_SOCKET_MISMATCH": fail(string(state))
		case "CAPTCHA_WRONG_INVITE": fail("CAPTCHA_SETUP_FAILED")
		}
		return 0
	}
	// Full login dump (complete requests/responses, password blanked): only to
	// a local file, %LOCALAPPDATA%\SR-Client\login-dump.txt, never over IPC.
	// Only with SR_LOGIN_DUMP=1 set: the file holds login tokens.
	if entries, has_dump := object["dump"].(json.Array); has_dump && len(entries) > 0 && login_dump_enabled() {
		if local, found := os.lookup_env_alloc("LOCALAPPDATA", context.temp_allocator); found && len(local) > 0 {
			if file, err := os.open(fmt.tprintf("%s\\SR-Client\\login-dump.txt", local), {.Write, .Append, .Create}); err == nil {
				for entry in entries {
					if text, ok := entry.(json.String); ok { _, _ = os.write_string(file, string(text)); _, _ = os.write_string(file, "\r\n") }
				}
				os.close(file)
			}
		}
	}
	// New lines from the login recorder: request shapes, no values.
	if requests, has_requests := object["requests"].(json.Array); has_requests {
		for i := browser.login_requests_sent; i < len(requests) && i < 120; i += 1 {
			line, is_text := requests[i].(json.String)
			printable := is_text && len(line) > 0 && len(line) <= 600
			if printable { for c in transmute([]u8)string(line) { if c < 32 || c > 126 { printable = false; break } } }
			if printable { notify("LOGIN_REQUEST", string(line)) }
			if printable && strings.has_prefix(string(line), "WS SEND lobby _0 ") && browser.login_rpc_seen == {} { browser.login_rpc_seen = time.now() }
			browser.login_requests_sent = i + 1
		}
	}
	browser.waiting_for_login = state == "WAIT_LOGIN" || state == "WAIT_TOKEN" || state == "WAIT_STORAGE" || state == "GUEST_TOKEN"
	switch string(state) {
	case "SDK_AVAILABLE": browser.sdk_seen = true; notify("STATUS", "SDK_AVAILABLE"); browser.done = true
	case "READY":
		browser.sdk_seen = true
		token, valid := object["token"].(json.String)
		if !valid || !access.usable(string(token), time.time_to_unix(time.now())) { fail("BAD_TOKEN"); return 0 }
		// After a fresh login, give the login recorder 3 seconds to see what
		// the page then sends on its lobby socket (login_watch.js).
		// Wait until the page has logged its lobby connection in (_0 login) and
		// the recorder relabelled it (2 s), or 20 s at most.
		// (Diagnostics only, SR_LOGIN_DUMP=1: a normal login closes at once.)
		if !browser.probe && browser.login_requests_sent > 0 && login_dump_enabled() {
			if browser.ready_since == {} { browser.ready_since = time.now() }
			waited := time.since(browser.ready_since)
			if browser.login_rpc_seen == {} && waited < 20*time.Second { return 0 }
			if browser.login_rpc_seen != {} && time.since(browser.login_rpc_seen) < 3*time.Second { return 0 }
		}
		_ = os.write_entire_file(browser.session_path, []byte{1})
		// The page's refresh token goes first: SR renews the session itself.
		if refresh, has_refresh := object["refresh"].(json.String); has_refresh && len(refresh) > 0 && len(refresh) <= 32768 {
			notify("SESSION_REFRESH", string(refresh))
		}
		notify("TOKEN", string(token)); browser.done = true
	case "SESSION_REJECTED":
		browser.sdk_seen, browser.rejected = true, true
		show()
		if changed { notify("STATUS", "SESSION_REJECTED") }
	case "PENDING": browser.sdk_seen = true
	case "WAIT_LOGIN", "WAIT_TOKEN": show()
	case "GUEST_TOKEN":
		show()
		if changed { notify("STATUS", "GUEST_TOKEN") }
	case "WAIT_STORAGE": // Let the page finish its storage write without blocking the helper's event loop.
	case "STORAGE_UNAVAILABLE": fail("STORAGE_UNAVAILABLE")
	case "BAD_TOKEN": fail("BAD_TOKEN")
	}
	return 0
}

main :: proc() {
	browser.probe = len(os.args) > 1 && os.args[1] == "--probe"
	browser.input, browser.output = win.GetStdHandle(win.STD_INPUT_HANDLE), win.GetStdHandle(win.STD_OUTPUT_HANDLE)
	request: access.Message
	if !browser.probe {
		// Parent writes one small request before launch returns. No browser is created without it.
		for {
			message, ready, alive := access.receive(browser.input, &browser.buffer)
			if !alive { return }
			if ready { request = message; break }
			time.sleep(10*time.Millisecond)
		}
		if request.id == 0 || (request.kind != "JOIN" && request.kind != "REFRESH" && request.kind != "CAPTCHA" && request.kind != "MODS") { return }
		browser.id = request.id
		browser.captcha = request.kind == "CAPTCHA"
		browser.mods = request.kind == "MODS"
		if browser.captcha {
			// The game alone, or {game, access, refresh} with SR's FRVR session.
			game := request.value
			if strings.has_prefix(request.value, "{") {
				Captcha_Request :: struct { game, access, refresh: string }
				parsed: Captcha_Request
				if json.unmarshal(transmute([]byte)request.value, &parsed, allocator = context.temp_allocator) != nil { fail("CAPTCHA_SETUP_FAILED"); return }
				game = parsed.game
				if len(parsed.access) <= 32768 && len(parsed.refresh) <= 32768 && access.token_state(parsed.access, time.time_to_unix(time.now())) == .READY {
					browser.session_access, browser.session_refresh = strings.clone(parsed.access), strings.clone(parsed.refresh)
				}
			}
			if len(game) > 0 && !access.captcha_game_valid(game) { fail("CAPTCHA_SETUP_FAILED"); return }
			browser.captcha_game = strings.clone(game)
		}
	}
	defer delete(request.kind); defer delete(request.value)
	defer delete(browser.buffer)
	if browser.mods {
		browser.started = time.now() // for the log's timestamps; set again below
		if local, found := os.lookup_env_alloc("LOCALAPPDATA", context.temp_allocator); found && len(local) > 0 {
			_ = os.make_directory_all(fmt.tprintf("%s\\SR-Client", local))
			_ = os.write_entire_file(fmt.tprintf("%s\\SR-Client\\mods-log.txt", local), transmute([]byte)string("SR Client Mods window log\r\n"))
		}
		mods_log("helper started (MODS)")
	}
	notify("TRACE", "HELPER_STARTED")
	if win.CoInitializeEx(nil, .APARTMENTTHREADED) < 0 { fail("HELPER_FAILED"); return }
	defer win.CoUninitialize()
	directory, err := os.get_executable_directory(context.temp_allocator)
	if err != nil { fail("LOADER_MISSING"); return }
	loader_path := win.utf8_to_utf16(fmt.tprintf("%s\\WebView2Loader.dll", directory))
	loader := win.LoadLibraryExW(cast(cstring16)raw_data(loader_path), nil, {.LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR, .LOAD_LIBRARY_SEARCH_SYSTEM32})
	if loader == nil { fail("LOADER_MISSING"); return }
	defer win.FreeLibrary(loader)
	version_fn := cast(proc "system" (^u16, ^^u16) -> win.HRESULT)win.GetProcAddress(loader, "GetAvailableCoreWebView2BrowserVersionString")
	create_fn := cast(proc "system" (^u16, ^u16, rawptr, ^Handler) -> win.HRESULT)win.GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions")
	if version_fn == nil || create_fn == nil { fail("LOADER_MISSING"); return }
	notify("TRACE", "LOADER_READY")
	version: ^u16
	if version_fn(nil, &version) < 0 { fail("RUNTIME_MISSING"); return }
	win.CoTaskMemFree(version)
	notify("TRACE", "RUNTIME_READY")
	root := access.root_path(); defer delete(root)
	if len(root) == 0 { fail("PROFILE_FAILED"); return }
	profile := fmt.tprintf("%s\\Browser", root)
	// Probes use a separate profile and never call the token method.
	if browser.probe { profile = fmt.tprintf("%s\\BrowserProbe", directory) }
	browser.session_path = fmt.aprintf("%s\\sr-session", profile)
	defer delete(browser.session_path)
	browser.remembered = os.is_file(browser.session_path)
	first := !browser.remembered
	notify("TRACE", first ? "PROFILE_NEW" : "PROFILE_REMEMBERED")
	os.make_directory(root)
	init_handler(&env_handler, &env_vtable, win.L("{4e8a3389-c9d8-4bd2-b6b5-124fee6cc14d}"), rawptr(environment_ready))
	init_handler(&controller_handler, &controller_vtable, win.L("{6c4819f3-c9b7-4260-8127-c9f5bde7f68c}"), rawptr(controller_ready))
	init_handler(&script_handler, &script_vtable, win.L("{49511172-cc67-4bca-9923-137112f4c4cc}"), rawptr(script_completed))
	init_handler(&navigation_handler, &navigation_vtable, win.L("{9adbe429-f36d-432b-9ddc-f8881fbd76e3}"), rawptr(navigation_starting))
	init_handler(&popup_handler, &popup_vtable, win.L("{d4c185fe-c81c-4989-97af-2d3fa7ab5651}"), rawptr(popup_requested))
	init_handler(&install_handler, &install_vtable, win.L("{b99369f3-9b11-47b5-bc6f-8e7895fcea17}"), rawptr(handoff_installed))
	init_handler(&message_handler, &message_vtable, win.L("{57213f19-00e6-49fa-8e07-898ea01ecbd2}"), rawptr(web_message_received))
	instance := win.HANDLE(win.GetModuleHandleW(nil))
	class := win.WNDCLASSEXW{cbSize = size_of(win.WNDCLASSEXW), lpfnWndProc = window_proc, hInstance = instance, lpszClassName = win.L("SR ClientBrowserAccess")}
	if win.RegisterClassExW(&class) == 0 { fail("HELPER_FAILED"); return }
	browser.window = win.CreateWindowExW(0, class.lpszClassName, win.L("SR Client - Krunker browser access"), win.WS_OVERLAPPEDWINDOW, win.CW_USEDEFAULT, win.CW_USEDEFAULT, 1100, 800, nil, nil, instance, nil)
	if browser.window == nil { fail("HELPER_FAILED"); return }
	if browser.captcha { win.SetWindowTextW(browser.window, win.L("SR Client - Verification for native Join")) }
	if browser.mods { win.SetWindowTextW(browser.window, win.L("SR Client - Krunker mods (press Load Mod)")) }
	defer win.DestroyWindow(browser.window)
	// Verification starts hidden: Krunker's check usually passes on its own in
	// a few seconds. The window appears only if it needs the player (12 s, or
	// when the page opens a popup).
	if !browser.captcha && (first || request.kind != "REFRESH" || browser.probe) { show() }
	if create_fn(nil, raw_data(win.utf8_to_utf16(profile)), nil, &env_handler) < 0 { fail("PROFILE_FAILED"); return }
	defer {
		if browser.controller != nil { (cast(proc "system" (^COM) -> win.HRESULT)browser.controller.v[24])(browser.controller) }
		release_com(browser.view); release_com(browser.controller)
	}
	browser.started = time.now()
	last_poll := time.Time{}
	for !browser.done {
		// At most 64 window messages per pass: a busy page (Krunker's game
		// running in the Mods window) keeps the queue full, and an unbounded
		// loop here never got to the checks below - SR never saw Load Mod.
		message: win.MSG
		for pumped := 0; pumped < 64 && win.PeekMessageW(&message, nil, 0, 0, win.PM_REMOVE); pumped += 1 {
			win.TranslateMessage(&message); win.DispatchMessageW(&message)
		}
		if !browser.probe {
			message, ready, alive := access.receive(browser.input, &browser.buffer)
			if !alive { break }
			if ready {
				cancel := message.id == browser.id && message.kind == "CANCEL"
				delete(message.kind); delete(message.value)
				if cancel { mods_log("cancelled by SR Client"); notify("ERROR", "CANCELLED"); break }
			}
		}
		elapsed := time.since(browser.started)
		if browser.mods && time.since(mods_heartbeat) > 5*time.Second {
			mods_heartbeat = time.now()
			source := browser.view != nil ? get_text(browser.view, 4) : "(no view)"
			mods_log(fmt.tprintf("alive %.0fs: view=%v executing=%v page=%s", time.duration_seconds(elapsed), browser.view != nil, browser.executing, source))
		}
		if elapsed > (browser.mods ? 1800 : 180)*time.Second { fail(browser.rejected ? "SESSION_REJECTED" : "TIMEOUT"); break }
		if !browser.captcha && !browser.mods && elapsed > 45*time.Second && (browser.probe || browser.remembered) && !browser.sdk_seen && !browser.waiting_for_login && (browser.view == nil || access.official_source(get_text(browser.view, 4))) { fail("SDK_UNAVAILABLE"); break }
		if elapsed > 12*time.Second { show() }
		// While a mod's bytes are copied, the next chunk is asked for at once.
		poll_wait := browser.mod_size > 0 ? time.Duration(0) : 500*time.Millisecond
		// WebView2 can drop the answer of a check sent while the page loads
		// (the document it ran in is replaced). Waiting for that answer
		// forever stopped all later checks: the Mods window never noticed
		// Load Mod (seen live on a real Krunker page: zero checks reached it
		// while the page had the mod link ready). Give up after 3 seconds.
		if browser.executing && time.since(browser.executing_since) > 3*time.Second {
			browser.executing = false
			mods_log("check got no answer in 3 s; sending a new one")
		}
		if browser.mods && browser.view != nil && !browser.executing && time.since(last_poll) > poll_wait {
			if source := get_text(browser.view, 4); !access.official_source(source) { mods_log(fmt.tprintf("not checking: page is %s", source)) }
		}
		if browser.view != nil && !browser.executing && time.since(last_poll) > poll_wait && access.official_source(get_text(browser.view, 4)) {
			script := fmt.tprintf("window.__srProbeOnly = %s;\n%s", browser.probe ? "true" : "false", string(#load("auth.js")))
			// With the login recorder's lines (login_watch.js) added to the answer.
			script = strings.concatenate({"(() => { const __srResult = ", strings.trim_right(strings.trim_space(script[strings.index(script, "\n")+1:]), ";"), "; try { if (__srResult && typeof __srResult === 'object') { __srResult.requests = (window.__srLoginWatch || []).slice(0, 120); const d = window.__srLoginDump || []; let i = window.__srDumpCursor || 0; const out = []; let size = 0; while (i < d.length && size + d[i].length < 30000) { out.push(d[i]); size += d[i].length; i++; } window.__srDumpCursor = i; __srResult.dump = out; } } catch {} return __srResult; })()"}, context.temp_allocator)
			if browser.probe { script = fmt.tprintf("window.__srProbeOnly = true;\n%s", script) }
			if browser.captcha { script = `(() => { const s = window.__srCaptchaHandoff; return s ? {state:s.state, token:s.token, assignment:s.assignment || ''} : {state:'WAIT_CAPTCHA'}; })()` }
			// Built by concatenation, NOT fmt: Odin's fmt reads "{...}" as its own
			// format braces and mangled this script into a syntax error, so every
			// check answered null and Load Mod was never seen (0.12 - 0.17.3).
			if browser.mods {
				offset := fmt.tprint(browser.mod_offset)
				script = strings.concatenate({`(() => { const s = window.__srMods; if (!s) return {state:'WAIT_MODS'}; if (s.state === 'MOD_DATA') return {state:'MOD_DATA', url:s.url || '', size:s.size, offset:`, offset, `, data:s.chunk(`, offset, `)}; return {state:s.state, url:s.url || '', debug: s.debug ? s.debug() : ''}; })()`}, context.temp_allocator)
			}
			browser.executing, browser.executing_navigation = true, browser.navigation
			browser.executing_since = time.now()
			if !mods_first_check { mods_first_check = true; mods_log("first check sent to the page") }
			hr := (cast(proc "system" (^COM, ^u16, ^Handler) -> win.HRESULT)browser.view.v[29])(browser.view, raw_data(win.utf8_to_utf16(script)), &script_handler)
			if hr < 0 { browser.executing = false; trace_script("SCRIPT_FAILED"); mods_log(fmt.tprintf("check could not start: 0x%x", u32(hr))) }
			last_poll = time.now()
		}
		free_all(context.temp_allocator)
		time.sleep(10*time.Millisecond)
	}
	browser.done = true
}
