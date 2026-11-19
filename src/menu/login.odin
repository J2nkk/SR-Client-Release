package menu

import clay "../third_party/clay"

// Krunker login in SR's Account window: the account email with its password,
// or a code FRVR emails (the client calls FRVR's API; see
// src/client/frvr_auth.odin). The password is shown masked and wiped after
// every login attempt.

Login_Field :: enum { EMAIL, PASSWORD, CODE }
LOGIN_FIELD_MAX := [Login_Field]int{.EMAIL = 254, .PASSWORD = 128, .CODE = 32}
LOGIN_TEXT_CAPACITY :: 256

login_field_id :: proc(field: Login_Field) -> clay.ElementId { return clay.ID("LoginField", u32(field)) }

login_text :: proc(state: ^State, field: Login_Field) -> string { return string(state.login_text[field][:state.login_text_length[field]]) }

login_text_set :: proc(state: ^State, field: Login_Field, value: string) {
	// Wipe the old bytes too (the password must not linger in memory).
	for &b in state.login_text[field] { b = 0 }
	state.login_text_length[field] = 0
	for c in transmute([]u8)value {
		if c < 32 || c >= 127 || state.login_text_length[field] >= LOGIN_FIELD_MAX[field] { continue }
		state.login_text[field][state.login_text_length[field]] = c
		state.login_text_length[field] += 1
	}
}

login_field_focused :: proc(state: ^State) -> (Login_Field, bool) {
	if state.page != .ACCOUNT { return {}, false }
	for field in Login_Field { if state.focus == login_field_id(field).id { return field, true } }
	return {}, false
}

login_typing :: proc(state: ^State) -> bool { _, ok := login_field_focused(state); return ok }

// Typing in the focused field; Enter sends the code or logs in.
login_text_input :: proc(state: ^State, input: Input) -> Action {
	field, ok := login_field_focused(state)
	if !ok { return {} }
	length := &state.login_text_length[field]
	if input.clear_text { login_text_set(state, field, "") }
	if input.backspace && !state.previous.backspace && length^ > 0 { length^ -= 1; state.login_text[field][length^] = 0 }
	for c in input.text {
		// Passwords may hold spaces and backticks; emails and codes may not.
		allowed := field == .PASSWORD ? c >= 32 && c < 127 : c > 32 && c < 127 && c != '`'
		if allowed && length^ < LOGIN_FIELD_MAX[field] {
			state.login_text[field][length^] = u8(c); length^ += 1
		}
	}
	if input.enter && !state.previous.enter {
		switch field {
		case .EMAIL: return {kind = state.login_text_length[.PASSWORD] > 0 ? .LOGIN_PASSWORD : .LOGIN_SEND_CODE}
		case .PASSWORD: return {kind = .LOGIN_PASSWORD}
		case .CODE: return {kind = .LOGIN_CODE}
		}
	}
	return {}
}

login_field :: proc(state: ^State, field: Login_Field, label, placeholder: string) {
	s := state.scale
	text(label, 18, s, MUTED)
	id := login_field_id(field)
	register(state, {id = id, enabled = true, action = {kind = .LOGIN_FIELD, index = i32(field)}})
	focused := state.focus == id.id
	if clay.UI(id)({layout = {sizing = {width = clay.SizingGrow(), height = clay.SizingFixed(56*s)}, padding = clay.PaddingAll(u16(12*s)), childAlignment = {y = .Center}}, backgroundColor = SURFACE, cornerRadius = clay.CornerRadiusAll(4*s), border = {color = WHITE, width = clay.BorderOutside(focused ? 1 : 0)}}) {
		value := login_text(state, field)
		if field == .PASSWORD { value = login_mask(len(value)) }
		if len(value) > 60 { value = value[len(value)-60:] }
		shown := focused ? value : len(value) == 0 ? placeholder : value
		text(focused ? concat_cursor(shown) : shown, 20, s, len(value) == 0 && !focused ? MUTED : WHITE)
	}
}

@(private = "file")
login_mask :: proc(count: int) -> string {
	out := make([]u8, count, context.temp_allocator)
	for &b in out { b = '*' }
	return string(out)
}

@(private = "file")
concat_cursor :: proc(value: string) -> string {
	out := make([]u8, len(value) + 1, context.temp_allocator)
	copy(out, value)
	out[len(value)] = '|'
	return string(out)
}
