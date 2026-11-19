package main

import "core:strings"
import "core:time"
import access "../browser_access"
import menuui "../menu"
import kproto "../krunker"

// SR's own Krunker (FRVR) session: logging in, keeping and renewing it
// through FRVR's API (frvr_auth.odin). The browser only opens for Krunker's
// verification, or for Browser login (Google/Discord/... accounts).

Frvr_Refresh_Proc :: proc(refresh_token: string) -> (string, string, Frvr_Result)
client_frvr_refresh :: proc(refresh_token: string) -> (string, string, Frvr_Result) { return frvr_refresh(refresh_token) }
Session_Load_Proc :: proc() -> (string, string, bool)
Session_Save_Proc :: proc(access_token, refresh_token: string) -> bool
client_session_load :: proc() -> (string, string, bool) {
	when ODIN_OS == .Windows { return access.session_load() } else { return "", "", false }
}
client_session_save :: proc(access_token, refresh_token: string) -> bool {
	when ODIN_OS == .Windows { return access.session_save(access_token, refresh_token) } else { return false }
}
client_session_invalidate :: proc() {
	when ODIN_OS == .Windows { _ = access.session_invalidate() }
}

// Keeps a new FRVR token pair: the session (both tokens) and the access cache.
client_session_store :: proc(client: ^Client, access_token, refresh_token: string, save: Session_Save_Proc = client_session_save, persist: proc(string) -> bool = client_browser_save) -> bool {
	if !save(access_token, refresh_token) {
		client_access_log(&client.access, "FRVR session could not be saved (encrypted file under LOCALAPPDATA/SR-Client); it lasts until SR closes.")
		return false
	}
	_ = persist(access_token)
	client.access.session_checked, client.access.has_session = true, true
	return true
}

// Signed in, as far as SR knows without asking FRVR: a stored session.
client_access_has_session :: proc(client: ^Client) -> bool {
	if !client.access.session_checked {
		client.access.session_checked = true
		a, r, ok := client_session_load()
		client.access.has_session = ok
		delete(a); delete(r)
	}
	return client.access.has_session
}

// Usable access from the stored FRVR session, renewed through FRVR's API when
// it is about to expire (or force: Krunker rejected it). No browser. False:
// no session, or FRVR no longer accepts it (then the session is forgotten).
client_access_renew :: proc(client: ^Client, now: i64, force := false, load: Session_Load_Proc = client_session_load, refresh: Frvr_Refresh_Proc = client_frvr_refresh, save: Session_Save_Proc = client_session_save, persist: proc(string) -> bool = client_browser_save, invalidate: proc() = client_session_invalidate) -> bool {
	state := &client.access
	session_access, session_refresh, ok := load()
	defer { delete(session_access); delete(session_refresh) }
	if !ok {
		client_access_log(state, "No stored FRVR session; Krunker login needed (email code, or Browser login).")
		state.session_checked, state.has_session = true, false
		return false
	}
	kproto.network_log_secret(session_access); kproto.network_log_secret(session_refresh)
	if !force && access.token_state(session_access, now) == .READY {
		delete(state.token); state.token, state.from_browser, state.status = strings.clone(session_access), true, .READY
		_ = persist(session_access)
		client_access_log(state, "Using the stored FRVR session's access token; no browser.")
		return true
	}
	if access.token_state(session_refresh, now) != .READY {
		client_access_log(state, "The stored FRVR session has expired; Krunker login needed.")
		invalidate()
		state.session_checked, state.has_session = true, false
		return false
	}
	new_access, new_refresh, result := refresh(session_refresh)
	switch result {
	case .OK:
		delete(state.token); state.token, state.from_browser, state.status = new_access, true, .READY
		client_session_store(client, new_access, new_refresh, save, persist)
		delete(new_refresh)
		client_access_log(state, "Renewed access through FRVR's API (crucible.frvr.com/v1/auth/refresh); no browser.")
		return true
	case .REJECTED, .BAD_INPUT:
		client_access_log(state, "ERROR FRVR rejected the stored session (refresh); Krunker login needed.")
		invalidate()
		state.session_checked, state.has_session = true, false
	case .FAILED:
		client_access_log(state, "ERROR could not renew the FRVR session (network or FRVR error); see the frvr-refresh lines.")
	}
	delete(new_access); delete(new_refresh)
	return false
}

// Krunker rejected the access token: renew it whatever its expiry says.
client_access_renew_forced :: proc(client: ^Client) -> bool { return client_access_renew(client, time.time_to_unix(time.now()), force = true) }

// No usable access: ask for a login in SR's Account window instead of
// opening a browser.
CLIENT_LOGIN_NEEDED :: "Log in to Krunker first: your account email and password, Email me a code, or Username / Google login. Then join or host again."
client_access_need_login :: proc(client: ^Client) {
	client.join_queued = 0
	client.access.status = .IDLE
	client.menu.page = .ACCOUNT
	client.menu.focus = menuui.login_field_id(.EMAIL).id
	krunker_ws_set_status(client, CLIENT_LOGIN_NEEDED)
}

FRVR_EMAIL_MAX :: 254

client_login_email_valid :: proc(email: string) -> bool {
	at := strings.index_byte(email, '@')
	return len(email) <= FRVR_EMAIL_MAX && at > 0 && at < len(email) - 3 && strings.contains(email[at:], ".") && !strings.contains_any(email, " \t\r\n")
}

Frvr_Request_Code_Proc :: proc(email: string) -> (string, Frvr_Result)
Frvr_Login_Code_Proc :: proc(email, flow, code: string) -> (string, string, Frvr_Result)
client_frvr_request_code :: proc(email: string) -> (string, Frvr_Result) { return frvr_request_code(email) }
client_frvr_login_code :: proc(email, flow, code: string) -> (string, string, Frvr_Result) { return frvr_login_code(email, flow, code) }

// Account window, Send code: FRVR emails a login code.
client_login_send_code :: proc(client: ^Client, request: Frvr_Request_Code_Proc = client_frvr_request_code) {
	if client.access.status == .PENDING { return }
	email := strings.trim_space(menuui.login_text(&client.menu, .EMAIL))
	if !client_login_email_valid(email) { krunker_ws_set_status(client, "Enter the email address of your Krunker account."); return }
	kproto.network_log_begin()
	client_access_log(&client.access, "Requesting a login code from FRVR (email omitted).")
	flow, result := request(email)
	switch result {
	case .OK:
		delete(client.access.login_flow); client.access.login_flow = flow
		delete(client.access.login_email); client.access.login_email = strings.clone(email)
		client.menu.login_code_sent = true
		menuui.login_text_set(&client.menu, .CODE, "")
		client.menu.focus = menuui.login_field_id(.CODE).id
		krunker_ws_set_status(client, "FRVR sent a login code to your email. Enter it and press Log in.")
	case .BAD_INPUT: krunker_ws_set_status(client, "FRVR did not accept that email address.")
	case .REJECTED: krunker_ws_set_status(client, "FRVR has no account for that email, or refused the login.")
	case .FAILED: krunker_ws_set_status(client, "Could not reach FRVR's login service. Check your connection; see logs/krunker-network.log.")
	}
}

Frvr_Login_Password_Proc :: proc(email, password: string) -> (string, string, Frvr_Result)
client_frvr_login_password :: proc(email, password: string) -> (string, string, Frvr_Result) { return frvr_login_password(email, password) }

// Account window, Log in with email and password. The password field is
// cleared whatever the answer; SR never stores the password.
client_login_with_password :: proc(client: ^Client, login: Frvr_Login_Password_Proc = client_frvr_login_password, save: Session_Save_Proc = client_session_save, persist: proc(string) -> bool = client_browser_save) {
	if client.access.status == .PENDING { return }
	defer menuui.login_text_set(&client.menu, .PASSWORD, "")
	email := strings.trim_space(menuui.login_text(&client.menu, .EMAIL))
	password := menuui.login_text(&client.menu, .PASSWORD)
	if !client_login_email_valid(email) { krunker_ws_set_status(client, "Enter the email address of your Krunker account."); return }
	if len(password) == 0 { krunker_ws_set_status(client, "Enter your password, or press Email me a code."); return }
	kproto.network_log_begin()
	client_access_log(&client.access, "Logging in to FRVR with email and password (both omitted).")
	access_token, refresh_token, result := login(email, password)
	switch result {
	case .OK:
		delete(client.access.token)
		client.access.token, client.access.from_browser, client.access.status, client.access.retried = access_token, true, .READY, false
		client_session_store(client, access_token, refresh_token, save, persist)
		delete(refresh_token)
		delete(client.access.login_flow); client.access.login_flow = ""
		client.menu.login_code_sent = false
		client_access_log(&client.access, "Logged in through FRVR's API with a password; session saved (encrypted), password not kept. No browser.")
		krunker_ws_set_status(client, "Logged in to Krunker. You can now join or host.")
	case .BAD_INPUT, .REJECTED:
		client.menu.focus = menuui.login_field_id(.PASSWORD).id
		krunker_ws_set_status(client, "Wrong email or password. Accounts without a password log in with Email me a code (or Browser login for Google/Discord).")
	case .FAILED:
		krunker_ws_set_status(client, "Could not reach FRVR's login service. Check your connection; see logs/krunker-network.log.")
	}
}

// Account window, Log in: the emailed code for the flow from Send code.
client_login_with_code :: proc(client: ^Client, login: Frvr_Login_Code_Proc = client_frvr_login_code, save: Session_Save_Proc = client_session_save, persist: proc(string) -> bool = client_browser_save) {
	if client.access.status == .PENDING { return }
	code := strings.trim_space(menuui.login_text(&client.menu, .CODE))
	if len(client.access.login_flow) == 0 { krunker_ws_set_status(client, "Press Send code first."); return }
	if len(code) == 0 { krunker_ws_set_status(client, "Enter the code from the email."); return }
	client_access_log(&client.access, "Logging in to FRVR with the emailed code (code and email omitted).")
	access_token, refresh_token, result := login(client.access.login_email, client.access.login_flow, code)
	switch result {
	case .OK:
		delete(client.access.token)
		client.access.token, client.access.from_browser, client.access.status, client.access.retried = access_token, true, .READY, false
		client_session_store(client, access_token, refresh_token, save, persist)
		delete(refresh_token)
		delete(client.access.login_flow); client.access.login_flow = ""
		client.menu.login_code_sent = false
		menuui.login_text_set(&client.menu, .CODE, "")
		client_access_log(&client.access, "Logged in through FRVR's API; session saved (encrypted). No browser.")
		krunker_ws_set_status(client, "Logged in to Krunker. You can now join or host.")
	case .BAD_INPUT, .REJECTED:
		krunker_ws_set_status(client, "Wrong or expired code. Check the email, or press Send code for a new one.")
	case .FAILED:
		krunker_ws_set_status(client, "Could not reach FRVR's login service. Check your connection; see logs/krunker-network.log.")
	}
}
