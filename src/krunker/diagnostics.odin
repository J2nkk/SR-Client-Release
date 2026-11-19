package krunker

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:time"

NETWORK_LOG_PATH :: "logs/krunker-network.log"
network_log_attempt: u64
network_log_started: time.Time
network_log_secrets: [dynamic]string
network_log_file_warning: bool
// Tests may point this elsewhere; call network_log_close first so the next
// line opens the new path.
network_log_path := NETWORK_LOG_PATH
// Kept open across lines; network_log_close releases it on shutdown.
network_log_file: ^os.File
// SR Client: echoing every network line to the console is slow on Windows and
// happens on the game thread. Opt in with SR_CONSOLE_LOG=1.
network_log_console_checked: bool
network_log_console: bool
// The log never grows past about twice this: when it is bigger at the first
// write of a run, it moves to krunker-network.old.log (replacing the previous
// one) and a fresh log starts. Checked once per run, nothing per line.
NETWORK_LOG_MAX_BYTES :: 1024 * 1024
network_log_rotated: bool

network_log_rotate :: proc(path: string) {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil || info.size <= NETWORK_LOG_MAX_BYTES { return }
	old := fmt.tprintf("%s.old.log", strings.trim_suffix(path, ".log"))
	_ = os.remove(old)
	_ = os.rename(path, old)
}

network_log_secret :: proc(secret: string) {
	if len(secret) == 0 do return
	for existing in network_log_secrets { if existing == secret do return }
	append(&network_log_secrets, strings.clone(secret))
}

network_log_sensitive_key :: proc(key: string) -> bool {
	keys := []string{"accessToken", "validationToken", "captchaToken", "clientKey", "clientId", "clientUID", "at", "bpt", "token", "authorization", "cookie", "set-cookie", "password", "access_token", "refresh_token"}
	for candidate in keys {
		if strings.equal_fold(key, candidate) do return true
	}
	return false
}

network_log_word :: proc(b: byte) -> bool {
	return b >= 'a' && b <= 'z' || b >= 'A' && b <= 'Z' || b >= '0' && b <= '9' || b == '_' || b == '-'
}

// Redact BEFORE truncating, including secrets echoed outside a JSON/query field.
// The returned string is owned by the caller.
network_log_safe :: proc(input: string, limit: int = 16384) -> string {
	value := strings.clone(input)
	defer delete(value)
	for secret in network_log_secrets {
		replaced, allocated := strings.replace_all(value, secret, "[REDACTED]")
		if allocated { delete(value); value = replaced }
	}
	out: [dynamic]byte
	defer delete(out)
	i := 0
	for i < len(value) {
		start := i
		if network_log_word(value[i]) {
			for i < len(value) && network_log_word(value[i]) { i += 1 }
			key := value[start:i]
			j := i
			if j < len(value) && (value[j] == '"' || value[j] == '\'') { j += 1 }
			for j < len(value) && (value[j] == ' ' || value[j] == '\t') { j += 1 }
			if network_log_sensitive_key(key) && j < len(value) && (value[j] == ':' || value[j] == '=') {
				j += 1
				for j < len(value) && (value[j] == ' ' || value[j] == '\t') { j += 1 }
				quote: byte
				if j < len(value) && (value[j] == '"' || value[j] == '\'') { quote = value[j]; j += 1 }
				append(&out, value[start:j])
				append(&out, "[REDACTED]")
				line_value := strings.equal_fold(key, "authorization") || strings.equal_fold(key, "cookie") || strings.equal_fold(key, "set-cookie")
				for j < len(value) {
					b := value[j]
					if quote != 0 {
						if b == '\\' && j+1 < len(value) { j += 2; continue }
						if b == quote do break
					} else {
						if b == '\r' || b == '\n' do break
						if !line_value && (b == '&' || b == '#' || b == ' ' || b == '\t' || b == ',' || b == '}' || b == ']' || b == '"' || b == '\'') do break
					}
					j += 1
				}
				i = j
				continue
			}
			// JWTs can appear in free text without a field name.
			if strings.has_prefix(key, "eyJ") && len(key) > 12 {
				for i < len(value) && (network_log_word(value[i]) || value[i] == '.' || value[i] == '=') { i += 1 }
				append(&out, "[REDACTED JWT]")
			} else { append(&out, key) }
			continue
		}
		if value[i] < 32 || value[i] == 127 { append(&out, ' ') } else { append(&out, value[i]) }
		i += 1
	}
	if len(out) > limit { return fmt.aprintf("%s ... [truncated; sanitized bytes=%d]", string(out[:limit]), len(out)) }
	return strings.clone(string(out[:]))
}

// Normal builds write the log only when something goes wrong: routine lines
// are kept in memory (the last NETWORK_LOG_CONTEXT of them) and written to the
// file together with the problem that follows them, so a failed join, a
// server error or a disconnect still shows what led up to it. Developer
// builds (-define:SR_DEV=true) write every line. Tests may switch this.
NETWORK_LOG_EVERYTHING_DEFAULT :: #config(SR_DEV, false)
network_log_everything := NETWORK_LOG_EVERYTHING_DEFAULT
NETWORK_LOG_CONTEXT :: 48
network_log_ring: [NETWORK_LOG_CONTEXT]string
network_log_ring_next, network_log_ring_count: int
// network_log is called from the game thread and the network thread.
network_log_mutex: sync.Mutex

// A line worth writing in normal builds: errors, failures, rejections, server
// errors and HTTP failures. Plain progress lines ("HTTP=200 ... No error",
// "limit_exceeded=false") are not.
network_log_is_problem :: proc(stage, message: string) -> bool {
	// login-shape: how Krunker's page logs in (field names only), always kept.
	if stage == "server-error" || stage == "login-shape" { return true }
	if strings.has_prefix(message, "ERROR") || strings.has_prefix(message, "WARNING") { return true }
	if strings.has_prefix(message, "HTTP=") {
		// 101 (WebSocket upgrade), 2xx and 3xx are fine; 4xx, 5xx and "no reply" (0) are not.
		status := 0
		for c in message[5:] {
			if c < '0' || c > '9' { break }
			status = status*10 + int(c - '0')
		}
		return status == 0 || status >= 400
	}
	lower := strings.to_lower(message, context.temp_allocator)
	words := []string{"failed", "failure", "rejected", "could not", "cannot", "unavailable", "invalid", "unexpected", "missing", "denied", "kicked", "banned", "captcha"}
	for word in words { if strings.contains(lower, word) { return true } }
	return false
}

@(private = "file")
network_log_ring_clear :: proc() {
	for &line in network_log_ring { delete(line, runtime.heap_allocator()); line = "" }
	network_log_ring_next, network_log_ring_count = 0, 0
}

network_log :: proc(stage, message: string) {
	safe := network_log_safe(message)
	defer delete(safe)
	stamp, _ := time.time_to_rfc3339(time.now(), include_nanos = false, allocator = context.temp_allocator)
	elapsed := network_log_attempt == 0 ? 0.0 : time.duration_milliseconds(time.since(network_log_started))
	line := fmt.tprintf("[Krunker][%s][attempt=%d +%.1fms][%s] %s\n", stamp, network_log_attempt, elapsed, stage, safe)
	if !network_log_console_checked {
		network_log_console_checked = true
		flag, found := os.lookup_env_alloc("SR_CONSOLE_LOG", context.temp_allocator)
		network_log_console = found && flag == "1"
	}
	if network_log_console do fmt.print(line)
	sync.mutex_lock(&network_log_mutex)
	defer sync.mutex_unlock(&network_log_mutex)
	if !network_log_everything {
		if !network_log_is_problem(stage, safe) {
			// The ring outlives any one caller's allocator (game, network
			// thread, tests), so it always uses the plain heap.
			delete(network_log_ring[network_log_ring_next], runtime.heap_allocator())
			network_log_ring[network_log_ring_next] = strings.clone(line, runtime.heap_allocator())
			network_log_ring_next = (network_log_ring_next + 1) % NETWORK_LOG_CONTEXT
			network_log_ring_count = min(network_log_ring_count + 1, NETWORK_LOG_CONTEXT)
			return
		}
		// A problem: write the lines that led up to it first, oldest first.
		start := (network_log_ring_next - network_log_ring_count + NETWORK_LOG_CONTEXT) % NETWORK_LOG_CONTEXT
		for i in 0 ..< network_log_ring_count {
			network_log_write(network_log_ring[(start + i) % NETWORK_LOG_CONTEXT])
		}
		network_log_ring_clear()
	}
	network_log_write(line)
}

@(private = "file")
network_log_write :: proc(line: string) {
	if network_log_file == nil {
		os.make_directory_all(os.dir(network_log_path))
		if !network_log_rotated { network_log_rotated = true; network_log_rotate(network_log_path) }
		file, err := os.open(network_log_path, {.Write, .Append, .Create})
		if err == nil { network_log_file = file }
	}
	if network_log_file != nil {
		_, write_err := os.write_string(network_log_file, line)
		if write_err == nil do return
		// Reopen on the next line, as before when every line reopened the file.
		network_log_close_unlocked()
	}
	if !network_log_console do fmt.print(line)
	if !network_log_file_warning { fmt.eprintln("[Krunker] Could not write logs/krunker-network.log; diagnostics continue on console."); network_log_file_warning = true }
}

network_log_close :: proc() {
	sync.mutex_lock(&network_log_mutex)
	defer sync.mutex_unlock(&network_log_mutex)
	network_log_close_unlocked()
}

@(private = "file")
network_log_close_unlocked :: proc() {
	if network_log_file != nil { os.close(network_log_file) }
	network_log_file = nil
}

network_log_clear_secrets :: proc() {
	for secret in network_log_secrets { delete(secret) }
	delete(network_log_secrets)
	network_log_secrets = nil
}

network_log_begin :: proc() {
	network_log_clear_secrets()
	network_log_attempt += 1
	network_log_started = time.now()
	cwd, _ := os.get_working_directory(context.temp_allocator)
	network_log("join", fmt.tprintf("BEGIN exe=%s handoff=v2 cwd=%s log=%s/%s", os.args[0], cwd, cwd, NETWORK_LOG_PATH))
}
