package main

import "core:encoding/json"
import "core:fmt"
import "core:strings"
import "core:time"
import access "../browser_access"
import kproto "../krunker"

// Krunker accounts are FRVR accounts. SR talks to FRVR's auth API directly,
// as Krunker's page does through its SDK (frvr-sdk.min.js, AuthServiceClient):
//   POST /login   {platform:"frvr", credentials:{email, method:"code"}}        -> {flowId}  (FRVR emails a code)
//   POST /login?flow=ID {platform:"frvr", credentials:{email, method:"code", code}} -> {accessToken, refreshToken}
//   POST /login   {platform:"frvr", credentials:{email, password}}             -> {accessToken, refreshToken}
//   POST /refresh {refreshToken}                                               -> {accessToken, refreshToken}
// Password login: the SDK's login(platform, credentials) posts the page's
// credentials unchanged. FRVR answers {email, password} with 400 "missing
// credentials" (1002) when the password is empty and 400 "bad credentials"
// (1003) when it is wrong (checked 2026-11-19 with an example.com address).
// The browser is only opened for Krunker's verification (CAPTCHA), or when
// the account signs in with Google/Discord/... (Browser login).
//
// Tokens, codes and the email address are registered as log secrets before
// any request, and request bodies are never logged.

FRVR_AUTH_URL :: "https://crucible.frvr.com/v1/auth"
FRVR_PLATFORM :: "frvr"

Frvr_Result :: enum { OK, REJECTED, BAD_INPUT, FAILED }

Frvr_HTTP :: proc(url, method, body, stage: string) -> ([dynamic]byte, i64, bool)

@(private = "file")
Frvr_Credentials :: struct {
	email:    string,
	method:   string `json:",omitempty"`,
	code:     string `json:",omitempty"`,
	password: string `json:",omitempty"`,
}
@(private = "file")
Frvr_Login :: struct { platform: string, credentials: Frvr_Credentials }
@(private = "file")
Frvr_Refresh :: struct { refreshToken: string }

@(private = "file")
frvr_post :: proc(http: Frvr_HTTP, path: string, body: $T, stage: string) -> (response: [dynamic]byte, status: i64, ok: bool) {
	data, err := json.marshal(body, allocator = context.temp_allocator)
	if err != nil { return {}, 0, false }
	return http(fmt.tprintf("%s%s", FRVR_AUTH_URL, path), "POST", string(data), stage)
}

// {accessToken, refreshToken}: an account (not guest) access token with a
// usable expiry, and a refresh token. The caller owns both strings.
frvr_token_pair :: proc(body: []byte) -> (access_token, refresh_token: string, ok: bool) {
	value, err := json.parse(body, parse_integers = true)
	if err != .None { return }
	defer json.destroy_value(value)
	object, is_object := value.(json.Object)
	if !is_object { return }
	a, a_ok := object["accessToken"].(json.String)
	r, r_ok := object["refreshToken"].(json.String)
	if !a_ok || !r_ok || len(a) == 0 || len(r) == 0 || len(a) > 32768 || len(r) > 32768 { return }
	if access.token_state(string(a), time.time_to_unix(time.now())) != .READY { return }
	return strings.clone(string(a)), strings.clone(string(r)), true
}

frvr_status_result :: proc(status: i64, transport_ok: bool) -> Frvr_Result {
	switch {
	case !transport_ok: return .FAILED
	case status == 400: return .BAD_INPUT
	case status == 401 || status == 403 || status == 404: return .REJECTED
	}
	return .FAILED
}

// New tokens for a refresh token. REJECTED: FRVR no longer accepts the
// session (log in again).
frvr_refresh :: proc(refresh_token: string, http: Frvr_HTTP = kproto.network_http) -> (access_token, new_refresh: string, result: Frvr_Result) {
	kproto.network_log_secret(refresh_token)
	body, status, transport_ok := frvr_post(http, "/refresh", Frvr_Refresh{refresh_token}, "frvr-refresh")
	defer delete(body)
	if transport_ok && (status == 200 || status == 201) {
		a, r, ok := frvr_token_pair(body[:])
		if !ok { kproto.network_log("frvr-refresh", "ERROR FRVR answered without a usable token pair"); return "", "", .FAILED }
		kproto.network_log_secret(a); kproto.network_log_secret(r)
		return a, r, .OK
	}
	return "", "", frvr_status_result(status, transport_ok)
}

// Asks FRVR to email a login code. The flow id goes with the code.
frvr_request_code :: proc(email: string, http: Frvr_HTTP = kproto.network_http) -> (flow: string, result: Frvr_Result) {
	kproto.network_log_secret(email)
	body, status, transport_ok := frvr_post(http, "/login", Frvr_Login{FRVR_PLATFORM, {email = email, method = "code"}}, "frvr-login")
	defer delete(body)
	if transport_ok && (status == 200 || status == 201) {
		value, err := json.parse(body[:])
		if err != .None { return "", .FAILED }
		defer json.destroy_value(value)
		object, ok := value.(json.Object)
		if !ok { return "", .FAILED }
		id, id_ok := object["flowId"].(json.String)
		if !id_ok || len(id) == 0 || len(id) > 1024 { return "", .FAILED }
		kproto.network_log_secret(string(id))
		return strings.clone(string(id)), .OK
	}
	return "", frvr_status_result(status, transport_ok)
}

// The emailed code for the flow from frvr_request_code. REJECTED: wrong or
// expired code.
// Email and password. REJECTED: wrong email or password, or an account that
// has no password (it logs in with a code or Google/Discord).
// The password is only ever in the request body, which is never logged.
frvr_login_password :: proc(email, password: string, http: Frvr_HTTP = kproto.network_http) -> (access_token, refresh_token: string, result: Frvr_Result) {
	kproto.network_log_secret(email); kproto.network_log_secret(password)
	body, status, transport_ok := frvr_post(http, "/login", Frvr_Login{FRVR_PLATFORM, {email = email, password = password}}, "frvr-login")
	defer delete(body)
	if transport_ok && (status == 200 || status == 201) {
		a, r, ok := frvr_token_pair(body[:])
		if !ok { kproto.network_log("frvr-login", "ERROR FRVR answered without a usable account token pair"); return "", "", .FAILED }
		kproto.network_log_secret(a); kproto.network_log_secret(r)
		return a, r, .OK
	}
	result = frvr_status_result(status, transport_ok)
	if result == .BAD_INPUT { result = .REJECTED } // 400 "bad credentials": wrong email or password
	return "", "", result
}

frvr_login_code :: proc(email, flow, code: string, http: Frvr_HTTP = kproto.network_http) -> (access_token, refresh_token: string, result: Frvr_Result) {
	kproto.network_log_secret(email); kproto.network_log_secret(code)
	body, status, transport_ok := frvr_post(http, fmt.tprintf("/login?flow=%s", krunker_ws_url_encode_temp(flow)), Frvr_Login{FRVR_PLATFORM, {email = email, method = "code", code = code}}, "frvr-login")
	defer delete(body)
	if transport_ok && (status == 200 || status == 201) {
		a, r, ok := frvr_token_pair(body[:])
		if !ok { kproto.network_log("frvr-login", "ERROR FRVR answered without a usable account token pair"); return "", "", .FAILED }
		kproto.network_log_secret(a); kproto.network_log_secret(r)
		return a, r, .OK
	}
	return "", "", frvr_status_result(status, transport_ok)
}

@(private = "file")
krunker_ws_url_encode_temp :: proc(value: string) -> string {
	encoded := krunker_ws_url_encode(value)
	defer delete(encoded)
	return strings.clone(encoded, context.temp_allocator)
}
