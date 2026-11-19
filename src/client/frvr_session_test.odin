package main

import "core:strings"
import "core:testing"
import "core:time"
import menuui "../menu"
import kproto "../krunker"

when ODIN_TEST {
	// Stubs only: no network, no real session file.
	@(private = "file") g_frvr_saved_access, g_frvr_saved_refresh: string
	@(private = "file") g_frvr_refresh_calls, g_frvr_invalidated: int
	@(private = "file") frvr_test_save :: proc(a, r: string) -> bool {
		delete(g_frvr_saved_access); delete(g_frvr_saved_refresh)
		g_frvr_saved_access, g_frvr_saved_refresh = strings.clone(a), strings.clone(r)
		return true
	}
	@(private = "file") frvr_test_persist :: proc(token: string) -> bool { return true }
	@(private = "file") frvr_test_invalidate :: proc() { g_frvr_invalidated += 1 }
	@(private = "file") frvr_test_none :: proc() -> (string, string, bool) { return "", "", false }
	@(private = "file") frvr_test_fresh :: proc() -> (string, string, bool) { return access_test_token(), access_test_token(30*86400), true }
	@(private = "file") frvr_test_expiring :: proc() -> (string, string, bool) { return access_test_token(10), access_test_token(30*86400), true }
	@(private = "file") frvr_test_dead :: proc() -> (string, string, bool) { return access_test_token(10), access_test_token(-10), true }
	@(private = "file") frvr_test_refresh_ok :: proc(r: string) -> (string, string, Frvr_Result) { g_frvr_refresh_calls += 1; return access_test_token(86400), access_test_token(30*86400), .OK }
	@(private = "file") frvr_test_refresh_rejected :: proc(r: string) -> (string, string, Frvr_Result) { g_frvr_refresh_calls += 1; return "", "", .REJECTED }
	@(private = "file") frvr_test_refresh_unreachable :: proc(r: string) -> (string, string, Frvr_Result) { g_frvr_refresh_calls += 1; return "", "", .FAILED }

	@(test)
	frvr_session_renews_without_a_browser :: proc(t: ^testing.T) {
		// Log secrets live in a global list; leaving this test's strings in it
		// crashes later tests once the test allocator frees them.
		defer kproto.network_log_clear_secrets()
		now := time.time_to_unix(time.now())
		defer { delete(g_frvr_saved_access); delete(g_frvr_saved_refresh); g_frvr_saved_access, g_frvr_saved_refresh = "", "" }
		client: Client
		defer delete(client.access.token)

		testing.expect(t, !client_access_renew(&client, now, false, frvr_test_none, frvr_test_refresh_ok, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "no session: login needed")
		testing.expect(t, !client.access.has_session)

		g_frvr_refresh_calls = 0
		testing.expect(t, client_access_renew(&client, now, false, frvr_test_fresh, frvr_test_refresh_ok, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "a fresh stored access token is used as is")
		testing.expect(t, g_frvr_refresh_calls == 0 && client.access.status == .READY, "no FRVR call while the access token is fresh")

		testing.expect(t, client_access_renew(&client, now, false, frvr_test_expiring, frvr_test_refresh_ok, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "an expiring session renews through FRVR")
		testing.expect(t, g_frvr_refresh_calls == 1 && client.access.token == g_frvr_saved_access && client.access.has_session, "the renewed pair is stored and used")

		testing.expect(t, client_access_renew(&client, now, true, frvr_test_fresh, frvr_test_refresh_ok, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "force renews even a fresh token (Krunker rejected it)")
		testing.expect(t, g_frvr_refresh_calls == 2)

		g_frvr_invalidated = 0
		testing.expect(t, !client_access_renew(&client, now, false, frvr_test_expiring, frvr_test_refresh_rejected, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "FRVR rejecting the session means login")
		testing.expect(t, g_frvr_invalidated == 1 && !client.access.has_session, "a rejected session is forgotten")

		g_frvr_invalidated = 0
		testing.expect(t, !client_access_renew(&client, now, false, frvr_test_expiring, frvr_test_refresh_unreachable, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "FRVR unreachable: no access")
		testing.expect(t, g_frvr_invalidated == 0, "a network failure keeps the session for later")

		g_frvr_refresh_calls = 0
		testing.expect(t, !client_access_renew(&client, now, false, frvr_test_dead, frvr_test_refresh_ok, frvr_test_save, frvr_test_persist, frvr_test_invalidate), "an expired refresh token is not sent")
		testing.expect(t, g_frvr_refresh_calls == 0)
	}

	@(private = "file") g_frvr_login_email, g_frvr_login_code: string
	@(private = "file") frvr_test_request_code :: proc(email: string) -> (string, Frvr_Result) {
		delete(g_frvr_login_email); g_frvr_login_email = strings.clone(email)
		return strings.clone("flow-1"), .OK
	}
	@(private = "file") frvr_test_login :: proc(email, flow, code: string) -> (string, string, Frvr_Result) {
		if flow != "flow-1" || email != g_frvr_login_email { return "", "", .FAILED }
		if code != "123456" { return "", "", .REJECTED }
		return access_test_token(86400), access_test_token(30*86400), .OK
	}

	@(test)
	frvr_email_code_login :: proc(t: ^testing.T) {
		// Log secrets live in a global list; leaving this test's strings in it
		// crashes later tests once the test allocator frees them.
		defer kproto.network_log_clear_secrets()
		defer { delete(g_frvr_saved_access); delete(g_frvr_saved_refresh); g_frvr_saved_access, g_frvr_saved_refresh = "", "" }
		defer { delete(g_frvr_login_email); g_frvr_login_email = "" }
		client: Client
		defer { delete(client.access.token); delete(client.access.login_flow); delete(client.access.login_email); delete(client.join_status) }
		testing.expect(t, !client_login_email_valid("nope") && !client_login_email_valid("a@b") && client_login_email_valid("player@example.com"))

		menuui.login_text_set(&client.menu, .EMAIL, "not-an-email")
		client_login_send_code(&client, frvr_test_request_code)
		testing.expect(t, !client.menu.login_code_sent, "an invalid email is not sent to FRVR")

		menuui.login_text_set(&client.menu, .EMAIL, "  player@example.com ")
		client_login_send_code(&client, frvr_test_request_code)
		testing.expect(t, client.menu.login_code_sent && client.access.login_flow == "flow-1" && g_frvr_login_email == "player@example.com", "Send code starts FRVR's flow with the trimmed email")

		menuui.login_text_set(&client.menu, .CODE, "000000")
		client_login_with_code(&client, frvr_test_login, frvr_test_save, frvr_test_persist)
		testing.expect(t, client.access.status != .READY && client.menu.login_code_sent, "a wrong code keeps the flow open")

		menuui.login_text_set(&client.menu, .CODE, "123456")
		client_login_with_code(&client, frvr_test_login, frvr_test_save, frvr_test_persist)
		testing.expect(t, client.access.status == .READY && client.access.has_session && !client.menu.login_code_sent, "the right code logs in")
		testing.expect(t, client.access.token == g_frvr_saved_access && len(g_frvr_saved_refresh) > 0, "the session (both tokens) is saved")
	}

	@(private = "file") g_frvr_password_seen: string
	@(private = "file") frvr_test_login_password :: proc(email, password: string) -> (string, string, Frvr_Result) {
		delete(g_frvr_password_seen); g_frvr_password_seen = strings.clone(password)
		if email != "player@example.com" || password != "correct horse `1" { return "", "", .REJECTED }
		return access_test_token(86400), access_test_token(30*86400), .OK
	}

	@(test)
	frvr_password_login :: proc(t: ^testing.T) {
		// Log secrets live in a global list; leaving this test's strings in it
		// crashes later tests once the test allocator frees them.
		defer kproto.network_log_clear_secrets()
		defer { delete(g_frvr_saved_access); delete(g_frvr_saved_refresh); g_frvr_saved_access, g_frvr_saved_refresh = "", "" }
		defer { delete(g_frvr_password_seen); g_frvr_password_seen = "" }
		client: Client
		defer { delete(client.access.token); delete(client.access.login_flow); delete(client.access.login_email); delete(client.join_status) }
		client.menu.page = .ACCOUNT

		// Typing: spaces and backticks reach the password, Enter logs in.
		client.menu.focus = menuui.login_field_id(.PASSWORD).id
		action := menuui.login_text_input(&client.menu, {text = "correct horse `1"})
		testing.expect(t, menuui.login_text(&client.menu, .PASSWORD) == "correct horse `1" && action.kind == .NONE)
		client.menu.previous = {}
		action = menuui.login_text_input(&client.menu, {enter = true})
		testing.expect(t, action.kind == .LOGIN_PASSWORD, "Enter in the password field logs in")

		menuui.login_text_set(&client.menu, .EMAIL, "player@example.com")
		menuui.login_text_set(&client.menu, .PASSWORD, "wrong")
		client_login_with_password(&client, frvr_test_login_password, frvr_test_save, frvr_test_persist)
		testing.expect(t, client.access.status != .READY && client.menu.login_text_length[.PASSWORD] == 0, "a wrong password does not log in, and the field is wiped")
		for b in client.menu.login_text[.PASSWORD] { if b != 0 { testing.expect(t, false, "the password bytes must be wiped"); break } }

		menuui.login_text_set(&client.menu, .PASSWORD, "correct horse `1")
		client_login_with_password(&client, frvr_test_login_password, frvr_test_save, frvr_test_persist)
		testing.expect(t, g_frvr_password_seen == "correct horse `1", "the password goes to FRVR as typed")
		testing.expect(t, client.access.status == .READY && client.access.has_session && client.access.token == g_frvr_saved_access, "the right password logs in and saves the session")
		testing.expect(t, client.menu.login_text_length[.PASSWORD] == 0, "the password is never kept")
		testing.expect(t, !strings.contains(g_frvr_saved_access, "horse") && !strings.contains(g_frvr_saved_refresh, "horse"), "only tokens are saved")
	}

	@(private = "file") g_frvr_bodies: [dynamic]string
	@(private = "file") frvr_test_http :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool) {
		append(&g_frvr_bodies, strings.concatenate({method, " ", url, " ", body}))
		out := make([dynamic]byte)
		append(&out, `{"error":{"message":"bad credentials err","code":1003}}`)
		return out, 400, true
	}

	@(test)
	frvr_requests_match_the_sdk :: proc(t: ^testing.T) {
		// Log secrets live in a global list; leaving this test's strings in it
		// crashes later tests once the test allocator frees them.
		defer kproto.network_log_clear_secrets()
		defer { for b in g_frvr_bodies { delete(b) }; delete(g_frvr_bodies); g_frvr_bodies = {} }
		_, _, password_result := frvr_login_password("player@example.com", "pw", frvr_test_http)
		flow, code_result := frvr_request_code("player@example.com", frvr_test_http)
		delete(flow)
		_, _, refresh_result := frvr_refresh("refresh", frvr_test_http)
		testing.expect(t, password_result == .REJECTED && code_result == .BAD_INPUT, "400 bad credentials: wrong password")
		testing.expect(t, refresh_result == .BAD_INPUT)
		if !testing.expect(t, len(g_frvr_bodies) == 3) { return }
		testing.expect_value(t, g_frvr_bodies[0], `POST https://crucible.frvr.com/v1/auth/login {"platform":"frvr","credentials":{"email":"player@example.com","password":"pw"}}`)
		testing.expect_value(t, g_frvr_bodies[1], `POST https://crucible.frvr.com/v1/auth/login {"platform":"frvr","credentials":{"email":"player@example.com","method":"code"}}`)
		testing.expect_value(t, g_frvr_bodies[2], `POST https://crucible.frvr.com/v1/auth/refresh {"refreshToken":"refresh"}`)
	}
}
