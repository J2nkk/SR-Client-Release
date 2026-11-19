package main

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import curl "vendor:curl"
import menuui "../menu"
import shared "../shared"
import kproto "../krunker"

// Host game, native: SR Client creates the custom game itself, exactly as
// Krunker's page does. Krunker's page creates a game over the lobby socket it
// already has: it sends ["custom", settings, null, false] and the server
// moves that same connection into the new game (init), confirms it (cust)
// and names it (inst-id). SR Client does the same with its own connection:
// it opens a lobby connection (the matchmaker's lobby for the chosen region,
// never entered: no team, no spawn), sends the host's setup on "ready", and
// is then in its own game as the host. The account is only ever connected
// once, so nothing kicks it. Seen live (2026-11-16).
//
// Performance: nothing in a match. host_game_tick returns at once unless a
// game is being created or the host page is open.

HOST_SETTINGS_FILE :: "cache/host-settings.txt"
HOST_CREATE_TIMEOUT :: 20 * time.Second
// Krunker answers "Invalid User" to a custom message sent the moment the
// lobby is ready (seen live: the account is still being loaded). Krunker's
// page only sends it once the player presses Start Game, so SR waits too,
// and tries again a little later if Krunker still isn't ready.
HOST_SEND_DELAY :: 1500 * time.Millisecond
HOST_RETRY_DELAY :: 2500 * time.Millisecond
HOST_TRIES :: 4
// Longest wait for Krunker's account answer before trying anyway.
HOST_ACCOUNT_WAIT :: 8 * time.Second
// Shown instead of a stale "Creating your custom game..." when the lobby
// connection closes before the game exists ("failed" also keeps it in the log).
HOST_LOST_CONNECTION :: "Hosting failed: the connection to Krunker closed before the game was created. Press Host game to try again."
// Krunker answered "Invalid User" and never sent the account on this connection.
HOST_NOT_LOGGED_IN :: "Hosting failed: Krunker's game server did not log your account in (Invalid User), so it treats you as a guest. Check that hosting works on krunker.io, then log in again and retry."
// While hosting, every packet Krunker sends that is not routine game traffic
// is logged by opcode, so a failed host shows what Krunker did and did not send.
HOST_RECV_LOG_LIMIT :: 64

HOST_IMAGE_DIR :: "img/maps/"
HOST_BANNER_FILE :: "img/maps/comp_banner.png"
HOST_IMAGE_HOST :: "https://assets.krunker.io/img/"

Host_Phase :: enum { NONE, QUEUED, SEEKING, WAITING, CREATING, HOSTED }

Host_Game :: struct {
	phase:    Host_Phase,
	queued:   int, // frames until the lobby connection starts (the status shows first)
	since:    time.Time,
	loaded:   bool, // saved host settings were read
	textures: [menuui.HOST_MAP_COUNT]Gpu_Texture,
	banner:   Gpu_Texture,
	images_tried: bool, // textures were looked for after the download finished
	tries:    int, // custom messages sent for this game
	// Krunker's page sends "custom" only once the socket has logged the
	// account in (ACCOUNT_RESPONSE "a"); sending earlier is "Invalid User".
	account_ready: bool,
	recv_logged: int, // packets logged for this game (HOST_RECV_LOG_LIMIT)
	// Hosting from the Krunker connection SR already has (a lobby or game,
	// e.g. the last hosted one): custom moves it into the new game, as on
	// Krunker's page. No new lobby, so no matchmaker verification.
	reused: bool,
}

// Connected to a Krunker lobby or game that has loaded (ready).
host_game_can_reuse :: proc(client: ^Client) -> bool {
	state := &client.krunker
	return state.connected && state.handle != nil && state.ready_received && client_access_browser_link(&client.join_link)
}

// Every packet while a game is being created: opcode and argument count only
// (account packets can carry personal data).
host_game_log_recv :: proc(packet: []kproto.Krunker_Msgpack_Value) {
	if g_host.phase != .SEEKING && g_host.phase != .WAITING && g_host.phase != .CREATING { return }
	if g_host.recv_logged >= HOST_RECV_LOG_LIMIT || krunker_ws_routine_packet(packet[0]) { return }
	g_host.recv_logged += 1
	kproto.network_log("host-recv", fmt.tprintf("opcode=%v args=%d phase=%v", packet[0], len(packet) - 1, g_host.phase))
}
g_host: Host_Game

// The matchmaker connection is for a new game, not the invite's.
host_game_seeking :: proc() -> bool { return g_host.phase == .SEEKING }
host_game_active :: proc() -> bool { return g_host.phase == .QUEUED || g_host.phase == .SEEKING || g_host.phase == .WAITING || g_host.phase == .CREATING }

// ------------------------------------------------------------ settings

host_settings_load :: proc(settings: ^menuui.Host_Settings) {
	settings^ = menuui.host_settings_default()
	data, err := os.read_entire_file_from_path(HOST_SETTINGS_FILE, context.temp_allocator)
	if err != nil { return }
	for line in strings.split_lines(string(data), context.temp_allocator) {
		key, _, value := strings.partition(strings.trim_space(line), " ")
		if len(key) == 0 { continue }
		number, is_number := strconv.parse_f32(value)
		switch key {
		case "maps":
			maps: bit_set[0..<menuui.HOST_MAP_COUNT]
			for part in strings.split(value, ",", context.temp_allocator) {
				id, ok := strconv.parse_int(part)
				if !ok { continue }
				for host_map, index in menuui.HOST_MAPS { if int(host_map.id) == id { maps += {index} } }
			}
			if card(maps) > 0 { settings.maps = maps }
		case "tmSize": if is_number { settings.team_size = i32(clamp(number, 0, 3)) }
		case "nameTeam1": menuui.host_text_set(settings, .TEAM1, value)
		case "nameTeam2": menuui.host_text_set(settings, .TEAM2, value)
		case "webhook": menuui.host_text_set(settings, .WEBHOOK, value)
		case:
			for info, field in menuui.HOST_VALUES { if key == info.key && is_number { menuui.host_value_set(settings, field, number) } }
			for info, toggle in menuui.HOST_TOGGLES {
				if key == info.key { if value == "true" { settings.toggles += {toggle} } else if value == "false" { settings.toggles -= {toggle} } }
			}
			if strings.has_prefix(key, "classLim") && is_number {
				if index, ok := strconv.parse_int(key[len("classLim"):]); ok && index >= 0 && index < 16 { settings.class_limit[index] = i32(clamp(number, 0, 20)) }
			}
		}
	}
}

host_settings_save :: proc(settings: ^menuui.Host_Settings) {
	builder := strings.builder_make(context.temp_allocator)
	maps := strings.builder_make(context.temp_allocator)
	for host_map, index in menuui.HOST_MAPS {
		if index not_in settings.maps { continue }
		if strings.builder_len(maps) > 0 { strings.write_byte(&maps, ',') }
		strings.write_int(&maps, int(host_map.id))
	}
	fmt.sbprintf(&builder, "maps %s\ntmSize %d\n", strings.to_string(maps), settings.team_size)
	for info, field in menuui.HOST_VALUES { fmt.sbprintf(&builder, "%s %g\n", info.key, settings.values[field]) }
	for info, toggle in menuui.HOST_TOGGLES { fmt.sbprintf(&builder, "%s %v\n", info.key, toggle in settings.toggles) }
	for limit, index in settings.class_limit { fmt.sbprintf(&builder, "classLim%d %d\n", index, limit) }
	fmt.sbprintf(&builder, "nameTeam1 %s\nnameTeam2 %s\nwebhook %s\n", menuui.host_text(settings, .TEAM1), menuui.host_text(settings, .TEAM2), menuui.host_text(settings, .WEBHOOK))
	_ = os.make_directory("cache")
	_ = os.write_entire_file(HOST_SETTINGS_FILE, transmute([]byte)strings.to_string(builder))
}

// The region Host creates games in: Settings > General > Default Region.
host_region :: proc(client: ^Client) -> menuui.Krunker_Region { return menuui.default_region(client.hud_settings) }

// ------------------------------------------------------------ the custom message

@(private = "file") host_pack_bool :: proc(out: ^[dynamic]byte, value: bool) { append(out, value ? 0xC3 : 0xC2) }

// Like Krunker's msgpack: whole numbers as integers, others as float64.
@(private = "file")
host_pack_number :: proc(out: ^[dynamic]byte, value: f64) {
	if value == math.floor(value) && abs(value) < 2147483647 { krunker_ws_pack_int(out, i32(value)); return }
	bits := transmute(u64)value
	append(out, 0xCB)
	for shift := 56; shift >= 0; shift -= 8 { append(out, byte(bits >> uint(shift))) }
}

// Values with one decimal (the 0.1 steps) as the exact doubles JavaScript
// sends (0.1, not 0.100000001...).
@(private = "file") host_decimal :: proc(value: f32) -> f64 { return math.round(f64(value) * 10) / 10 }

// ["custom", settings, null, false]: the settings Krunker's comp setup sends,
// in its key order (captured from Krunker's page). Game Settings and Server
// are locked for comp, so they keep Krunker's comp values.
host_custom_payload :: proc(settings: ^menuui.Host_Settings) -> [dynamic]byte {
	out: [dynamic]byte
	krunker_ws_pack_array(&out, 4)
	krunker_ws_pack_string(&out, "custom")
	append(&out, 0xDE, 0, 0) // map16; the count is filled in below
	count := 0
	key :: proc(out: ^[dynamic]byte, count: ^int, name: string) { krunker_ws_pack_string(out, name); count^ += 1 }
	flag :: proc(out: ^[dynamic]byte, count: ^int, name: string, value: bool) { key(out, count, name); host_pack_bool(out, value) }
	num :: proc(out: ^[dynamic]byte, count: ^int, name: string, value: f64) { key(out, count, name); host_pack_number(out, value) }
	null :: proc(out: ^[dynamic]byte, count: ^int, name: string) { key(out, count, name); krunker_ws_pack_nil(out) }
	str :: proc(out: ^[dynamic]byte, count: ^int, name, value: string) { key(out, count, name); krunker_ws_pack_string(out, value) }
	value :: proc(settings: ^menuui.Host_Settings, field: menuui.Host_Value) -> f64 { return host_decimal(settings.values[field]) }
	on :: proc(settings: ^menuui.Host_Settings, toggle: menuui.Host_Toggle) -> bool { return toggle in settings.toggles }

	flag(&out, &count, "private", false); flag(&out, &count, "krRewards", false)
	flag(&out, &count, "defaultSetts", false); flag(&out, &count, "share", false)
	null(&out, &count, "customMap"); null(&out, &count, "rawMapData")
	key(&out, &count, "maps")
	krunker_ws_pack_array(&out, card(settings.maps))
	for host_map, index in menuui.HOST_MAPS { if index in settings.maps { krunker_ws_pack_int(&out, host_map.id) } }
	null(&out, &count, "modes"); null(&out, &count, "classes")
	num(&out, &count, "override", 1); null(&out, &count, "passCode")
	num(&out, &count, "maxPlayers", 2); num(&out, &count, "minPlayers", 0)
	num(&out, &count, "gameTime", value(settings, .GAME_TIME)); num(&out, &count, "warmupTime", 0)
	num(&out, &count, "gamRounds", value(settings, .ROUNDS)); num(&out, &count, "intermTmr", value(settings, .INTERMISSION))
	for name in ([]string{"forceSpawn", "lives", "scoreLimit", "keepTScore"}) { num(&out, &count, name, 0) }
	num(&out, &count, "objtvTime", value(settings, .OBJECTIVE_TIME))
	for name in ([]string{"forceC", "logTim", "lstChkT"}) { num(&out, &count, name, 0) }
	num(&out, &count, "gravMlt", 1); num(&out, &count, "deltaMlt", 1)
	num(&out, &count, "fallDmg", 0); num(&out, &count, "fallDmgThr", 0)
	num(&out, &count, "jumpMlt", 1); num(&out, &count, "fixMov", 0)
	num(&out, &count, "slidTime", 1); num(&out, &count, "slidSpd", 1)
	num(&out, &count, "impulseMlt", 1); num(&out, &count, "wallJP", 1)
	num(&out, &count, "strafeSpd", 1.2)
	for name in ([]string{"canSlide", "airStrf", "autoJump", "bDrop"}) { num(&out, &count, name, 0) }
	num(&out, &count, "healthMlt", 1)
	num(&out, &count, "hitBoxPad", value(settings, .HITBOX_PAD)); num(&out, &count, "hurtboxScale", value(settings, .HURTBOX_SCALE))
	num(&out, &count, "fiRat", 1); num(&out, &count, "reSpd", 1)
	for name in ([]string{"hpRegen", "killRewards", "noAssists", "headshotOnly", "noSecondary", "noStreaks", "disableB", "throwMel", "chrgWeps", "selTeam", "frFire", "noPvp"}) { num(&out, &count, name, 0) }
	team1, team2 := menuui.host_text(settings, .TEAM1), menuui.host_text(settings, .TEAM2)
	str(&out, &count, "nameTeam1", len(team1) > 0 ? team1 : "Alpha"); str(&out, &count, "nameTeam2", len(team2) > 0 ? team2 : "Bravo")
	for name in ([]string{"nameTeam3", "nameTeam4", "nameTeam5"}) { num(&out, &count, name, 0) }
	for name in ([]string{"t1Dmg", "t2Dmg", "t3Dmg", "t4Dmg", "t5Dmg"}) { num(&out, &count, name, 1) }
	flag(&out, &count, "allowSpect", on(settings, .ALLOW_SPECTATE))
	for name in ([]string{"thirdPerson", "nameTags", "nameTagsFR", "kCams", "aAnon"}) { num(&out, &count, name, 0) }
	flag(&out, &count, "transferHostOnLeave", on(settings, .TRANSFER_HOST))
	num(&out, &count, "specSlots", value(settings, .SPEC_SLOTS))
	num(&out, &count, "tmSize", f64(clamp(settings.team_size, 0, 3)))
	flag(&out, &count, "noCosm", on(settings, .NO_COSMETICS)); flag(&out, &count, "tstCmp", on(settings, .TEST_COMP))
	flag(&out, &count, "noDraws", on(settings, .NO_DRAWS)); flag(&out, &count, "bstOfR", on(settings, .BEST_OF_ROUNDS))
	flag(&out, &count, "headClipFix", on(settings, .HEAD_CLIP_FIX)); flag(&out, &count, "rampFix", on(settings, .RAMP_FIX))
	str(&out, &count, "webhook", menuui.host_text(settings, .WEBHOOK))
	num(&out, &count, "minimaps", 0)
	flag(&out, &count, "limitClasses", on(settings, .LIMIT_CLASSES))
	for limit, index in settings.class_limit { num(&out, &count, fmt.tprintf("classLim%d", index), f64(limit)) }
	// Krunker's comp Team Rosters, after the settings: "teams" when either team
	// has names, "specs" when there are spectators.
	team1_names := menuui.host_roster_names(settings, .ROSTER1)
	team2_names := menuui.host_roster_names(settings, .ROSTER2)
	spec_names := menuui.host_roster_names(settings, .SPECTATORS)
	pack_names :: proc(out: ^[dynamic]byte, names: []string) {
		krunker_ws_pack_array(out, len(names))
		for name in names { krunker_ws_pack_string(out, name) }
	}
	if len(team1_names) > 0 || len(team2_names) > 0 {
		key(&out, &count, "teams")
		krunker_ws_pack_array(&out, 2)
		pack_names(&out, team1_names[:])
		pack_names(&out, team2_names[:])
	}
	if len(spec_names) > 0 {
		key(&out, &count, "specs")
		pack_names(&out, spec_names[:])
	}
	out[9], out[10] = byte(count >> 8), byte(count) // after 0x94, "custom" (7 bytes), 0xDE
	krunker_ws_pack_nil(&out)
	host_pack_bool(&out, false)
	return out
}

host_send_custom :: proc(state: ^Krunker_WS_State, settings: ^menuui.Host_Settings) -> bool {
	if !state.connected || state.handle == nil { return false }
	krunker_net_send_begin()
	defer krunker_net_send_end()
	next_counter := state.ah_num
	packet := krunker_ws_finish_packet(host_custom_payload(settings), "custom", &next_counter)
	defer delete(packet)
	sent: c.size_t
	code := krunker_ws_raw_send(state, packet[:], &sent)
	if code != .E_OK || int(sent) != len(packet) {
		kproto.network_log("host", fmt.tprintf("custom send failed curl=%v sent=%d expected=%d", code, sent, len(packet)))
		return false
	}
	state.ah_num = next_counter
	kproto.network_log("host", fmt.tprintf("sent custom bytes=%d counter=%d", len(packet), state.ah_num))
	return true
}

// ------------------------------------------------------------ flow

// Start Game on the host page.
host_game_start :: proc(client: ^Client) {
	if host_game_active() || client.join_queued > 0 || client.access.status == .PENDING { return }
	if game_files_checking() { krunker_ws_set_status(client, "Checking for Krunker updates... Host in a moment."); return }
	settings := &client.menu.host
	host_settings_save(settings)
	client.menu.page, client.menu.focus = .HOME, client.menu.return_focus
	if host_game_can_reuse(client) { host_game_start_on_connection(client); return }
	g_host.reused = false
	client_leave_session(client, false)
	shared.join_link_free(&client.join_link)
	link, ok := shared.join_link_parse("https://krunker.io/")
	if !ok { krunker_ws_set_status(client, "Could not start hosting."); return }
	client.join_link = link
	menuui.set_invite(&client.menu, "")
	g_host.phase, g_host.queued, g_host.since = .QUEUED, 2, time.now()
	krunker_ws_set_status(client, fmt.tprintf("Creating your custom game (%s)...", host_region(client).name))
}

// Start Game while connected to a Krunker lobby or game: send custom on that
// connection (host_game_tick), as Krunker's page does.
host_game_start_on_connection :: proc(client: ^Client) {
	// Same connection: the match the player is in ends for them here.
	kproto.network_log("host", fmt.tprintf("creating a custom game on the current connection (game %s); no new lobby, no verification", client.join_link.game_id))
	state := &client.krunker
	state.spawned, state.bootstrapped, state.bootstrap_step = false, false, 0
	client.spawn_pending, client.has_life = false, false
	client_clear_players(client)
	kill_feed_clear(&client.kill_feed)
	death_cam_end()
	g_host.reused, g_host.tries, g_host.recv_logged = true, 0, 0
	g_host.account_ready = state.account_loaded
	g_host.phase, g_host.since = .WAITING, time.now()
	krunker_ws_set_status(client, "Creating your custom game on your current connection...")
}

host_game_fail :: proc(client: ^Client, reason: string) {
	kproto.network_log("host", fmt.tprintf("hosting stopped: %s", reason))
	g_host.phase = .NONE
	// A reused connection stays where it was (unless it is already gone).
	if !g_host.reused || !client.krunker.connected { client_leave_session(client, false) }
	krunker_ws_set_status(client, reason)
}

// "ready" on the lobby connection: send the host's setup.
host_game_on_ready :: proc(client: ^Client) -> bool {
	if g_host.phase != .SEEKING { return true }
	g_host.phase, g_host.since, g_host.tries = .WAITING, time.now(), 0
	krunker_ws_set_status(client, "Creating your custom game...")
	return true
}

// "inst-id" [game]: the new game; SR Client is in it as the host.
host_game_on_instance :: proc(client: ^Client, packet: []kproto.Krunker_Msgpack_Value) {
	if g_host.phase != .CREATING || len(packet) < 2 { return }
	game, ok := packet[1].(string)
	if !ok || !shared_game_id_valid(game) { return }
	link, parsed := shared.join_link_parse(fmt.tprintf("https://krunker.io/?game=%s", game))
	if !parsed { return }
	shared.join_link_free(&client.join_link)
	client.join_link = link
	menuui.set_invite(&client.menu, client.join_link.raw)
	g_host.phase = .HOSTED
	kproto.network_log("host", fmt.tprintf("custom game %s created; SR Client is its host", game))
	krunker_ws_set_status(client, fmt.tprintf("Your custom game %s is ready. Copy invite (bottom left) shares it.", game))
}

// "cust" [text, game, ...]: Krunker's answer; without a game it is an error.
host_game_on_custom :: proc(client: ^Client, packet: []kproto.Krunker_Msgpack_Value) {
	if g_host.phase != .CREATING { return }
	text := len(packet) > 1 ? packet[1].(string) or_else "" : ""
	game := len(packet) > 2 ? packet[2].(string) or_else "" : ""
	if len(game) > 0 || len(text) == 0 { return }
	kproto.network_log("host", fmt.tprintf("Krunker answered custom (try %d): %s; account answer (a) received=%v", g_host.tries, text, g_host.account_ready))
	// "Invalid User" with no account answer (a) after the full HOST_ACCOUNT_WAIT:
	// Krunker's game server has no account on this connection and treats SR as
	// a guest, and guests cannot create games. Trying again on the same
	// connection does not change that (seen live 2026-11-19: four tries).
	if text == "Invalid User" && !g_host.account_ready {
		kproto.network_log("host", "ERROR Krunker never logged the account in on the lobby connection (no a packet), so it refused to create the game")
		host_game_fail(client, HOST_NOT_LOGGED_IN)
		return
	}
	if text == "Invalid User" && g_host.tries < HOST_TRIES {
		g_host.phase, g_host.since = .WAITING, time.now()
		krunker_ws_set_status(client, fmt.tprintf("Creating your custom game (Krunker is still loading your account, try %d of %d)...", g_host.tries + 1, HOST_TRIES))
		return
	}
	host_game_fail(client, fmt.tprintf("Krunker: %s", text))
}

shared_game_id_valid :: proc(game: string) -> bool {
	colon := strings.index_byte(game, ':')
	if colon < 2 || colon > 6 || len(game) > 32 || len(game) - colon < 4 { return false }
	for b in transmute([]u8)game {
		if !(b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == ':') { return false }
	}
	return true
}

// Every frame. Returns at once unless a game is being created or the host
// page is open.
host_game_tick :: proc(client: ^Client) {
	if client.menu.page == .HOST { host_images_tick() }
	else if g_host.images_tried { host_images_release() }
	switch g_host.phase {
	case .NONE, .HOSTED: return
	case .QUEUED:
		g_host.queued -= 1
		if g_host.queued > 0 { return }
		kproto.network_log_begin()
		kproto.network_log("host", fmt.tprintf("creating a custom game in region %s", host_region(client).id))
		kproto.krunker_world_reset(&client.krunker_world)
		net_client_disconnect(&client.net)
		g_host.phase, g_host.since = .SEEKING, time.now()
		g_host.account_ready, g_host.recv_logged = false, 0
		if !krunker_ws_connect(client, &client.join_link) && g_host.phase == .SEEKING { g_host.phase = .NONE }
	case .SEEKING:
		// Waiting for the lobby (or for the verification window).
		if !client.krunker.connected && client.access.status != .PENDING && client.join_queued == 0 { g_host.phase = .NONE }
	case .WAITING:
		if !client.krunker.connected { host_game_fail(client, HOST_LOST_CONNECTION); return }
		// No account 2 s after ready: log the connection in as the page does
		// after a fresh login (_0 login), once.
		if !g_host.account_ready && time.since(g_host.since) > 2*time.Second { krunker_ws_send_account_login(client) }
		if !g_host.account_ready && g_host.tries == 0 && time.since(g_host.since) < HOST_ACCOUNT_WAIT { return }
		if time.since(g_host.since) < (g_host.tries == 0 ? (g_host.account_ready ? 300*time.Millisecond : 0) : HOST_RETRY_DELAY) { return }
		if !host_send_custom(&client.krunker, &client.menu.host) { host_game_fail(client, "Could not send the host setup to Krunker."); return }
		g_host.tries += 1
		g_host.phase, g_host.since = .CREATING, time.now()
	case .CREATING:
		if !client.krunker.connected { host_game_fail(client, HOST_LOST_CONNECTION); return }
		if time.since(g_host.since) > HOST_CREATE_TIMEOUT { host_game_fail(client, "Krunker did not create the game. Press Host game to try again.") }
	}
}

// The lobby the matchmaker gave for hosting must never be shown or entered.
host_game_hides_lobby :: proc() -> bool { return g_host.phase == .SEEKING || g_host.phase == .WAITING || g_host.phase == .CREATING }

// Host game button: open the host page.
host_game_open :: proc(client: ^Client) {
	if !g_host.loaded { host_settings_load(&client.menu.host); g_host.loaded = true }
	menuui.host_open(&client.menu)
}

host_game_close :: proc() { host_images_release() }

// ------------------------------------------------------------ map images

host_image_path :: proc(id: i32) -> string { return fmt.tprintf("%s%smap_%d.png", shared.assets_path(), HOST_IMAGE_DIR, id) }

host_images_tick :: proc() {
	if g_host.images_tried || game_files_checking() { return }
	g_host.images_tried = true
	for host_map, index in menuui.HOST_MAPS {
		if g_host.textures[index] == 0 && os.exists(host_image_path(host_map.id)) { g_host.textures[index] = load_texture(host_image_path(host_map.id)) }
	}
	banner := fmt.tprintf("%s%s", shared.assets_path(), HOST_BANNER_FILE)
	if g_host.banner == 0 && os.exists(banner) { g_host.banner = load_texture(banner) }
}

host_images_release :: proc() {
	for &texture in g_host.textures { texture_release(texture); texture = 0 }
	texture_release(g_host.banner); g_host.banner = 0
	g_host.images_tried = false
}

host_view :: proc(client: ^Client, view: ^menuui.View) {
	if client.menu.page != .HOST { return }
	for texture, index in g_host.textures { view.host_maps[index] = texture == 0 ? nil : rawptr(uintptr(texture)) }
	view.host_banner = g_host.banner == 0 ? nil : rawptr(uintptr(g_host.banner))
	view.host_can_start = !game_files_checking() && client.access.status != .PENDING && !host_game_active()
}

@(private = "file")
host_image_write :: proc "c" (buffer: [^]byte, size, count: c.size_t, output: rawptr) -> c.size_t {
	context = runtime.default_context()
	data := cast(^[dynamic]byte)output
	total := int(size*count)
	if len(data)+total > 4*1024*1024 { return 0 }
	append(data, ..buffer[:total])
	return c.size_t(total)
}

// On the start-up check's thread: Krunker's comp map images and banner for
// the host page, once (kept in assets/img/maps).
host_images_download :: proc() {
	directory := fmt.tprintf("%s%s", shared.assets_path(), HOST_IMAGE_DIR)
	_ = os.make_directory_all(directory)
	download :: proc(url, path: string) {
		if os.exists(path) { return }
		handle := curl.easy_init()
		if handle == nil { return }
		data: [dynamic]byte
		defer delete(data)
		curl.easy_setopt(handle, .URL, strings.clone_to_cstring(url, context.temp_allocator))
		curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
		curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(8000))
		curl.easy_setopt(handle, .TIMEOUT_MS, c.long(20000))
		curl.easy_setopt(handle, .USERAGENT, cstring("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"))
		curl.easy_setopt(handle, .REFERER, cstring("https://krunker.io/"))
		curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(host_image_write))
		curl.easy_setopt(handle, .WRITEDATA, rawptr(&data))
		code := curl.easy_perform(handle)
		status: c.long
		curl.easy_getinfo(handle, .RESPONSE_CODE, &status)
		curl.easy_cleanup(handle)
		// Only a real PNG is kept.
		if code != .E_OK || status != 200 || len(data) < 8 || string(data[1:4]) != "PNG" { return }
		temporary := fmt.tprintf("%s.download", path)
		if os.write_entire_file(temporary, data[:]) != nil { return }
		if os.rename(temporary, path) != nil { _ = os.remove(temporary) }
	}
	for host_map in menuui.HOST_MAPS { download(fmt.tprintf("%smaps/map_%d.png", HOST_IMAGE_HOST, host_map.id), host_image_path(host_map.id)) }
	download(fmt.tprintf("%sbackgrounds/gamecats/c_1.png", HOST_IMAGE_HOST), fmt.tprintf("%s%s", shared.assets_path(), HOST_BANNER_FILE))
	free_all(context.temp_allocator)
}

// ACCOUNT_RESPONSE "a" [error, id, name, data...]: the socket's login result.
host_game_on_account :: proc(client: ^Client, packet: []kproto.Krunker_Msgpack_Value) {
	if !host_game_active() { return }
	error := ""
	if len(packet) > 1 { error, _ = packet[1].(string) }
	if len(error) > 0 {
		kproto.network_log("host", fmt.tprintf("ERROR Krunker did not log the account in on the lobby connection: %s", error))
		host_game_fail(client, "Hosting failed: Krunker did not log you in on this connection. Press Login, then Host game again.")
		return
	}
	g_host.account_ready = true
	kproto.network_log("host", "account loaded on the lobby connection")
}
