package main

import "core:encoding/hex"
import "core:strings"
import "core:testing"
import menuui "../menu"
import kproto "../krunker"
import shared "../shared"
import curl "vendor:curl"

// Krunker's own Comp setup with its defaults (Burg, 4v4), captured from its
// page on 2026-11-16 without the 2-byte counter. SR Client must send exactly this.
@(private = "file")
HOST_CAPTURED_DEFAULT :: "94a6637573746f6dde0065a770726976617465c2a96b7252657761726473c2ac64656661756c745365747473c2a57368617265c2a9637573746f6d4d6170c0aa7261774d617044617461c0a46d6170739100a56d6f646573c0a7636c6173736573c0a86f7665727269646501a870617373436f6465c0aa6d6178506c617965727302aa6d696e506c617965727300a867616d6554696d6504aa7761726d757054696d6500a967616d526f756e647303a9696e7465726d546d721eaa666f726365537061776e00a56c6976657300aa73636f72654c696d697400aa6b6565705453636f726500a96f626a747654696d6501a6666f7263654300a66c6f6754696d00a76c737443686b5400a7677261764d6c7401a864656c74614d6c7401a766616c6c446d6700aa66616c6c446d6754687200a76a756d704d6c7401a66669784d6f7600a8736c696454696d6501a7736c696453706401aa696d70756c73654d6c7401a677616c6c4a5001a9737472616665537064cb3ff3333333333333a863616e536c69646500a76169725374726600a86175746f4a756d7000a56244726f7000a96865616c74684d6c7401a9686974426f78506164cb3fb999999999999aac68757274626f785363616c6501a5666952617401a5726553706401a76870526567656e00ab6b696c6c5265776172647300a96e6f4173736973747300ac6865616473686f744f6e6c7900ab6e6f5365636f6e6461727900a96e6f53747265616b7300a864697361626c654200a87468726f774d656c00a8636872675765707300a773656c5465616d00a666724669726500a56e6f50767000a96e616d655465616d31a5416c706861a96e616d655465616d32a5427261766fa96e616d655465616d3300a96e616d655465616d3400a96e616d655465616d3500a57431446d6701a57432446d6701a57433446d6701a57434446d6701a57435446d6701aa616c6c6f775370656374c3ab7468697264506572736f6e00a86e616d655461677300aa6e616d6554616773465200a56b43616d7300a561416e6f6e00b37472616e73666572486f73744f6e4c65617665c3a973706563536c6f747302a6746d53697a6503a66e6f436f736dc3a6747374436d70c3a76e6f4472617773c3a66273744f6652c3ab68656164436c6970466978c3a772616d70466978c3a7776562686f6f6ba0a86d696e696d61707300ac6c696d6974436c6173736573c3a9636c6173734c696d3001a9636c6173734c696d3101a9636c6173734c696d3201a9636c6173734c696d3301a9636c6173734c696d3401a9636c6173734c696d3501a9636c6173734c696d3601a9636c6173734c696d3700a9636c6173734c696d3801a9636c6173734c696d3900aa636c6173734c696d313000aa636c6173734c696d313100aa636c6173734c696d313201aa636c6173734c696d313301aa636c6173734c696d313400aa636c6173734c696d313501c0c2"

@(test)
host_default_setup_matches_krunker :: proc(t: ^testing.T) {
	settings := menuui.host_settings_default()
	payload := host_custom_payload(&settings)
	defer delete(payload)
	expected, ok := hex.decode(transmute([]byte)string(HOST_CAPTURED_DEFAULT))
	defer delete(expected)
	testing.expect(t, ok)
	testing.expect_value(t, len(payload), len(expected))
	testing.expect(t, string(payload[:]) == string(expected))
}

@(test)
host_setup_carries_the_players_choices :: proc(t: ^testing.T) {
	settings := menuui.host_settings_default()
	settings.maps = {3, 11} // Shipment, Frontier
	settings.team_size = 0
	menuui.host_value_set(&settings, .OBJECTIVE_TIME, 1.5)
	menuui.host_value_set(&settings, .HITBOX_PAD, -0.3)
	settings.toggles -= {.NO_DRAWS}
	menuui.host_text_set(&settings, .TEAM1, "Reds")
	payload := host_custom_payload(&settings)
	defer delete(payload)
	messages, _, error_text := kproto.krunker_msgpack_decode_packet(append_counter(payload[:]))
	testing.expect_value(t, error_text, "")
	testing.expect_value(t, len(messages), 1)
	packet := messages[0].([]kproto.Krunker_Msgpack_Value)
	testing.expect_value(t, packet[0].(string), "custom")
	entries := packet[1].([]kproto.Krunker_Msgpack_Map_Entry)
	testing.expect_value(t, len(entries), 101)
	find :: proc(entries: []kproto.Krunker_Msgpack_Map_Entry, key: string) -> kproto.Krunker_Msgpack_Value {
		for entry in entries { if name, ok := entry.key.(string); ok && name == key { return entry.value } }
		return nil
	}
	maps := find(entries, "maps").([]kproto.Krunker_Msgpack_Value)
	testing.expect_value(t, len(maps), 2)
	testing.expect_value(t, maps[0].(i64), 5)
	testing.expect_value(t, maps[1].(i64), 42)
	testing.expect_value(t, find(entries, "tmSize").(i64), 0)
	testing.expect_value(t, find(entries, "objtvTime").(f64), 1.5)
	testing.expect_value(t, find(entries, "hitBoxPad").(f64), -0.3)
	testing.expect_value(t, find(entries, "noDraws").(bool), false)
	testing.expect_value(t, find(entries, "nameTeam1").(string), "Reds")
}

// DrEvil's tournament link (Glorp's host-comp parameters) with SR's scheme.
HOST_LINK_EXAMPLE :: "srclient://game?action=host-comp&mapId=Sandstorm&team1Name=lunarzthemoon&team2Name=motorlifefn&teamSize=2v2&team1Players=Lunarz%2C+realIy&team2Players=C6Z06%2C+Vxmpleo&comp=true&webhook=https%3A%2F%2Fkrunkeresports.com%2Fapi%2Fwebhook%2Fkrunker&compRosterT1=Lunarz%2C+realIy&compRosterT2=C6Z06%2C+Vxmpleo&spectators=Asokra%2C+bankloot"

@(test)
host_link_fills_the_comp_setup_like_krunkers_page :: proc(t: ^testing.T) {
	settings := menuui.host_settings_default()
	ok, problem := host_link_parse(HOST_LINK_EXAMPLE, &settings)
	testing.expectf(t, ok, "the example link must parse: %s", problem)
	testing.expect(t, settings.maps == {1}, "mapId=Sandstorm selects only Sandstorm")
	testing.expect_value(t, settings.team_size, 1) // 2v2
	testing.expect_value(t, menuui.host_text(&settings, .TEAM1), "lunarzthemoon")
	testing.expect_value(t, menuui.host_text(&settings, .TEAM2), "motorlifefn")
	testing.expect_value(t, menuui.host_text(&settings, .WEBHOOK), "https://krunkeresports.com/api/webhook/krunker")
	testing.expect_value(t, menuui.host_text(&settings, .ROSTER1), "Lunarz, realIy")
	testing.expect_value(t, menuui.host_text(&settings, .SPECTATORS), "Asokra, bankloot")

	payload := host_custom_payload(&settings)
	defer delete(payload)
	messages, _, error_text := kproto.krunker_msgpack_decode_packet(append_counter(payload[:]))
	testing.expect_value(t, error_text, "")
	entries := messages[0].([]kproto.Krunker_Msgpack_Value)[1].([]kproto.Krunker_Msgpack_Map_Entry)
	find :: proc(entries: []kproto.Krunker_Msgpack_Map_Entry, key: string) -> kproto.Krunker_Msgpack_Value {
		for entry in entries { if name, ok := entry.key.(string); ok && name == key { return entry.value } }
		return nil
	}
	testing.expect_value(t, find(entries, "maps").([]kproto.Krunker_Msgpack_Value)[0].(i64), 2)
	testing.expect_value(t, find(entries, "tmSize").(i64), 1)
	testing.expect_value(t, find(entries, "nameTeam1").(string), "lunarzthemoon")
	testing.expect_value(t, find(entries, "webhook").(string), "https://krunkeresports.com/api/webhook/krunker")
	// Krunker: teams = [team 1 names, team 2 names], specs = names; trimmed, after the settings.
	teams := find(entries, "teams").([]kproto.Krunker_Msgpack_Value)
	testing.expect_value(t, len(teams), 2)
	t1 := teams[0].([]kproto.Krunker_Msgpack_Value)
	t2 := teams[1].([]kproto.Krunker_Msgpack_Value)
	testing.expect(t, len(t1) == 2 && t1[0].(string) == "Lunarz" && t1[1].(string) == "realIy", "team 1 roster split and trimmed")
	testing.expect(t, len(t2) == 2 && t2[0].(string) == "C6Z06" && t2[1].(string) == "Vxmpleo", "team 2 roster split and trimmed")
	specs := find(entries, "specs").([]kproto.Krunker_Msgpack_Value)
	testing.expect(t, len(specs) == 2 && specs[0].(string) == "Asokra" && specs[1].(string) == "bankloot", "spectators split and trimmed")
	last, _ := entries[len(entries) - 1].key.(string)
	testing.expect_value(t, last, "specs")
}

@(test)
host_link_rejects_what_it_cannot_host :: proc(t: ^testing.T) {
	settings := menuui.host_settings_default()
	ok, _ := host_link_parse("srclient://game?action=host-comp&mapId=Nowhere", &settings)
	testing.expect(t, !ok, "a map outside the comp pool is refused")
	ok, _ = host_link_parse("srclient://game?action=join&mapId=Burg", &settings)
	testing.expect(t, !ok, "only host-comp is supported")
	ok, _ = host_link_parse("srclient://game?action=host-comp&teamSize=5v5", &settings)
	testing.expect(t, !ok, "team sizes stop at 4v4")
	ok, _ = host_link_parse("srclient://game?action=host-comp&mapId=14&teamSize=4v4", &settings)
	testing.expect(t, ok && settings.maps == {6} && settings.team_size == 3, "a numeric Krunker map id (14 = Site) works")
	ok, _ = host_link_parse("SRCLIENT://game/?action=host-comp&mapId=eterno+simulator", &settings)
	testing.expect(t, ok && settings.maps == {10}, "scheme case, a trailing slash and spaced map names are accepted")
	testing.expect(t, host_link_is("srclient://x") && !host_link_is("glorp://game"), "only srclient:// links are taken")
}

// Krunker's init packet carries the custom game's config at index 7; its
// browser reads the team names from config.nameTeam1 / nameTeam2.
@(test)
krunker_team_names_come_from_name_team_keys :: proc(t: ^testing.T) {
	state: kproto.Krunker_World_State
	defer kproto.krunker_world_reset(&state)
	entries := []kproto.Krunker_Msgpack_Map_Entry{{key = "nameTeam1", value = "SR Test A"}, {key = "nameTeam2", value = "   "}}
	packet := []kproto.Krunker_Msgpack_Value{"init", nil, nil, nil, nil, nil, nil, entries}
	kproto.krunker_world_apply_game_config(&state, packet)
	testing.expect_value(t, state.lobby_team_names[0], "SR Test A")
	client: Client
	client.krunker.connected = true
	client.krunker_world = state
	names := client_team_names(&client)
	client.krunker_world = {}
	testing.expect(t, names[0] == "SR Test A" && names[1] == "Bravo", "a blank name falls back to Krunker's team letter, as the browser does")
}

@(private = "file")
append_counter :: proc(payload: []byte) -> []byte {
	out := make([]byte, len(payload)+2, context.temp_allocator)
	copy(out, payload)
	return out
}

@(test)
host_game_ids_are_checked :: proc(t: ^testing.T) {
	testing.expect(t, shared_game_id_valid("FRA:4llbw"))
	testing.expect(t, !shared_game_id_valid("FRA:"))
	testing.expect(t, !shared_game_id_valid("FRA:4ll/bw"))
	testing.expect(t, !shared_game_id_valid("nothing"))
}

@(test)
host_region_is_krunkers_default_region :: proc(t: ^testing.T) {
	hud: menuui.HUD_Settings
	testing.expect_value(t, menuui.default_region(hud).id, "de-fra") // unset = Frankfurt
	hud.default_region = 8
	testing.expect_value(t, menuui.default_region(hud).id, "us-tx")
	testing.expect_value(t, menuui.default_region(hud).name, "Dallas")
}

// Hosting while already connected (e.g. in the last hosted game) reuses that
// connection: no disconnect, no new lobby, so no matchmaker verification.
@(test)
host_game_reuses_the_current_connection :: proc(t: ^testing.T) {
	saved := g_host
	defer g_host = saved
	g_host = {}
	client: Client
	defer { shared.join_link_free(&client.join_link); delete(client.join_status) }
	link, ok := shared.join_link_parse("https://krunker.io/?game=NY:abcde")
	if !testing.expect(t, ok) { return }
	client.join_link = link
	testing.expect(t, !host_game_can_reuse(&client), "not connected: a new lobby is needed")
	client.krunker.connected, client.krunker.ready_received = true, true
	client.krunker.handle = cast(^curl.CURL)rawptr(uintptr(1)) // never used: nothing is sent here
	client.krunker.account_loaded = true
	client.krunker.spawned = true
	testing.expect(t, host_game_can_reuse(&client), "a loaded Krunker connection can host")
	host_game_start_on_connection(&client)
	testing.expect(t, g_host.phase == .WAITING && g_host.reused && g_host.account_ready, "custom goes out on this connection, with the account already loaded")
	testing.expect(t, client.krunker.connected && !client.krunker.spawned && client.join_link.game_id == "NY:abcde", "the connection stays; the match state is cleared")
	host_game_fail(&client, "Krunker: test")
	testing.expect(t, client.krunker.connected && g_host.phase == .NONE, "a failed host on a reused connection keeps the player where they were")
	client.krunker.handle = nil
}

@(test)
krunker_account_login_message_matches_the_page :: proc(t: ^testing.T) {
	// The page's message: ["_0", 0, "login", token] (login_watch.js capture).
	token := strings.repeat("t", 300, context.temp_allocator)
	payload := krunker_ws_account_login_payload(token)
	defer delete(payload)
	messages, _, error_text := kproto.krunker_msgpack_decode_packet(append_trailer(payload[:]))
	if !testing.expect(t, len(error_text) == 0 && len(messages) == 1, "the login message must decode as one msgpack message") { return }
	packet, ok := messages[0].([]kproto.Krunker_Msgpack_Value)
	if !testing.expect(t, ok && len(packet) == 4) { return }
	testing.expect(t, (packet[0].(string) or_else "") == "_0")
	testing.expect(t, kproto.krunker_world_i32(packet[1], -1) == KRUNKER_ACCOUNT_LOGIN_ID)
	testing.expect(t, (packet[2].(string) or_else "") == "login")
	testing.expect(t, (packet[3].(string) or_else "") == token)
}
@(private = "file") append_trailer :: proc(payload: []byte) -> []byte {
	out := make([]byte, len(payload) + 2, context.temp_allocator)
	copy(out, payload)
	return out
}
