@tool
extends RefCounted
## Minimal MCP server (Streamable HTTP transport, JSON responses) on 127.0.0.1.
## Polled from the editor main thread; never opens outbound connections.

const SERVER_NAME := "godot-local-mcp"
const SERVER_VERSION := "1.0.0"
const PROTOCOL_VERSIONS := ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
const FALLBACK_PROTOCOL := "2025-06-18"
const MAX_HEADER := 64 * 1024
const MAX_BODY := 16 * 1024 * 1024
const MAX_CLIENTS := 64
const IDLE_TIMEOUT_MS := 10 * 60 * 1000
const PENDING_TIMEOUT_MS := 20 * 1000
const ALLOWED_HOSTS := ["127.0.0.1", "localhost", "[::1]"]

const INSTRUCTIONS := "Tools for a live Godot editor. Node paths are relative to the edited scene root ('.' is the root). " \
	+ "Pass non-JSON values as Godot expressions in strings, e.g. \"Vector2(10, 20)\" or \"Color(1, 0, 0)\"; resources as \"res://\" paths. " \
	+ "Scene edits are in memory until save_scene is called. After writing scripts, check the returned errors."


class Client:
	var peer: StreamPeerTCP
	var buf := PackedByteArray()
	var last_ms := 0
	var sent_continue := false
	var closing := false


var port := 0
var token := ""
var _tcp := TCPServer.new()
var _clients: Array = []
var _pending: Array = []  # Tool calls answered later: [client, rpc_id, ticket, deadline_ms]
var _tools: RefCounted


func _init(tools: RefCounted) -> void:
	_tools = tools


func start(base_port: int, auth_token: String) -> int:
	token = auth_token
	for p in range(base_port, base_port + 10):
		if _tcp.listen(p, "127.0.0.1") == OK:
			port = p
			return p
	port = 0
	return 0


func stop() -> void:
	for c in _clients:
		c.peer.disconnect_from_host()
	_clients.clear()
	_pending.clear()
	if _tcp.is_listening():
		_tcp.stop()
	port = 0


func url() -> String:
	return "http://127.0.0.1:%d/mcp" % port


func poll() -> void:
	if not _tcp.is_listening():
		return
	var now := Time.get_ticks_msec()
	while _tcp.is_connection_available():
		var peer := _tcp.take_connection()
		if peer == null:
			break
		if _clients.size() >= MAX_CLIENTS:
			peer.disconnect_from_host()
			continue
		peer.set_no_delay(true)
		var c := Client.new()
		c.peer = peer
		c.last_ms = now
		_clients.append(c)

	for i in range(_clients.size() - 1, -1, -1):
		var c: Client = _clients[i]
		c.peer.poll()
		if c.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_clients.remove_at(i)
			continue
		var n := c.peer.get_available_bytes()
		if n > 0:
			var r: Array = c.peer.get_data(n)
			if r[0] != OK:
				c.closing = true
			else:
				c.buf.append_array(r[1])
				c.last_ms = now
				while not c.closing and _try_handle(c):
					pass
		elif now - c.last_ms > IDLE_TIMEOUT_MS:
			c.closing = true
		if c.closing:
			c.peer.disconnect_from_host()
			_clients.remove_at(i)

	for i in range(_pending.size() - 1, -1, -1):
		var entry: Array = _pending[i]
		var pc: Client = entry[0]
		if pc.closing or pc.peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_tools.cancel_pending(entry[2])
			_pending.remove_at(i)
			continue
		var result: Variant = _tools.poll_pending(entry[2])
		if result == null and now > entry[3]:
			_tools.cancel_pending(entry[2])
			result = {"content": [{"type": "text", "text": "Timed out waiting for the running game. It may be stopped at an error or breakpoint, or the LocalMcpRuntime autoload is missing (Project Settings > Globals)."}], "isError": true}
		if result != null:
			pc.last_ms = now
			_send_json(pc, 200, _rpc_result(entry[1], result))
			_pending.remove_at(i)


# ---------------------------------------------------------------- HTTP

func _find_seq(buf: PackedByteArray, from: int, double: bool) -> int:
	# Finds "\r\n" (or "\r\n\r\n" when double) starting at `from`.
	var need := 4 if double else 2
	var limit := buf.size() - need
	var i := from
	while i <= limit:
		i = buf.find(13, i)
		if i < 0 or i > limit:
			return -1
		if buf[i + 1] == 10 and (not double or (buf[i + 2] == 13 and buf[i + 3] == 10)):
			return i
		i += 1
	return -1


func _try_handle(c: Client) -> bool:
	var hend := _find_seq(c.buf, 0, true)
	if hend < 0:
		if c.buf.size() > MAX_HEADER:
			_send(c, 431, {}, "", true)
		return false
	var lines := c.buf.slice(0, hend).get_string_from_utf8().split("\r\n")
	var request_line := lines[0].split(" ")
	if request_line.size() < 3:
		_send(c, 400, {}, "", true)
		return false
	var method := request_line[0].to_upper()
	var target := request_line[1]
	var headers := {}
	for li in range(1, lines.size()):
		var idx := lines[li].find(":")
		if idx > 0:
			headers[lines[li].substr(0, idx).strip_edges().to_lower()] = lines[li].substr(idx + 1).strip_edges()

	var body_start := hend + 4
	var body := PackedByteArray()
	var consumed := body_start
	if str(headers.get("transfer-encoding", "")).to_lower().contains("chunked"):
		var r := _decode_chunked(c.buf, body_start)
		if r[0] == 0:
			_maybe_continue(c, headers)
			return false
		if r[0] < 0:
			_send(c, 400, {}, "", true)
			return false
		body = r[1]
		consumed = r[2]
	else:
		var cl_text := str(headers.get("content-length", "0"))
		if not cl_text.is_valid_int() or int(cl_text) < 0:
			_send(c, 400, {}, "", true)
			return false
		var cl := int(cl_text)
		if cl > MAX_BODY:
			_send(c, 413, {}, "", true)
			return false
		if c.buf.size() < body_start + cl:
			_maybe_continue(c, headers)
			return false
		body = c.buf.slice(body_start, body_start + cl)
		consumed = body_start + cl

	c.buf = c.buf.slice(consumed)
	c.sent_continue = false
	_handle_request(c, method, target, headers, body)
	return c.buf.size() > 0


func _maybe_continue(c: Client, headers: Dictionary) -> void:
	if not c.sent_continue and str(headers.get("expect", "")).to_lower() == "100-continue":
		c.sent_continue = true
		c.peer.put_data("HTTP/1.1 100 Continue\r\n\r\n".to_utf8_buffer())


func _decode_chunked(buf: PackedByteArray, start: int) -> Array:
	# Returns [status, body, end]; status 0 = incomplete, 1 = ok, -1 = malformed.
	var out := PackedByteArray()
	var pos := start
	while true:
		var eol := _find_seq(buf, pos, false)
		if eol < 0:
			return [0, out, pos]
		var size_text := buf.slice(pos, eol).get_string_from_ascii().split(";")[0].strip_edges()
		if not size_text.is_valid_hex_number():
			return [-1, out, pos]
		var size := size_text.hex_to_int()
		pos = eol + 2
		if size == 0:
			# Skip optional trailers up to the blank line.
			while true:
				var e := _find_seq(buf, pos, false)
				if e < 0:
					return [0, out, pos]
				var blank := e == pos
				pos = e + 2
				if blank:
					return [1, out, pos]
		if out.size() + size > MAX_BODY:
			return [-1, out, pos]
		if buf.size() < pos + size + 2:
			return [0, out, pos]
		out.append_array(buf.slice(pos, pos + size))
		pos += size + 2
	return [-1, out, pos]


func _host_allowed(host: String) -> bool:
	var h := host.to_lower()
	if h.begins_with("["):
		h = h.substr(0, h.find("]") + 1)
	else:
		h = h.split(":")[0]
	return h in ALLOWED_HOSTS


func _origin_allowed(origin: String) -> bool:
	var o := origin.to_lower()
	var sep := o.find("://")
	if sep < 0:
		return false
	return _host_allowed(o.substr(sep + 3))


func _handle_request(c: Client, method: String, target: String, headers: Dictionary, body: PackedByteArray) -> void:
	# DNS-rebinding and cross-site protection: only local Host/Origin values.
	if not _host_allowed(str(headers.get("host", ""))):
		_send(c, 403, {}, "Forbidden host", true)
		return
	var origin := str(headers.get("origin", ""))
	if origin != "" and not _origin_allowed(origin):
		_send(c, 403, {}, "Forbidden origin", true)
		return
	if token != "" and str(headers.get("authorization", "")) != "Bearer " + token:
		_send(c, 401, {"WWW-Authenticate": "Bearer"}, "Unauthorized")
		return

	var path := target.split("?")[0]
	if path == "/health" and method == "GET":
		_send_json(c, 200, {"status": "ok", "server": SERVER_NAME, "version": SERVER_VERSION})
		return
	if path != "/mcp" and path != "/":
		_send(c, 404, {}, "Not found")
		return
	if method != "POST":
		# No server-initiated SSE stream and no sessions: GET/DELETE are not offered.
		_send(c, 405, {"Allow": "POST"}, "Method not allowed")
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_send_json(c, 400, _rpc_error(null, -32700, "Parse error: " + json.get_error_message()))
		return
	var data: Variant = json.data
	if data is Array:
		var replies := []
		for item in data:
			var reply: Variant = _handle_message(item)
			if reply is Dictionary and reply.has("__pending"):
				_tools.cancel_pending(reply["__pending"])
				reply = _rpc_error(reply["id"], -32600, "This tool cannot be called inside a JSON-RPC batch.")
			if reply != null:
				replies.append(reply)
		if replies.is_empty():
			_send(c, 202, {}, "")
		else:
			_send_json(c, 200, replies)
	elif data is Dictionary:
		var reply: Variant = _handle_message(data)
		if reply is Dictionary and reply.has("__pending"):
			_pending.append([c, reply["id"], reply["__pending"], Time.get_ticks_msec() + PENDING_TIMEOUT_MS])
		elif reply == null:
			_send(c, 202, {}, "")
		else:
			_send_json(c, 200, reply)
	else:
		_send_json(c, 400, _rpc_error(null, -32600, "Invalid request"))


func _send_json(c: Client, status: int, payload: Variant) -> void:
	_send(c, status, {"Content-Type": "application/json"}, JSON.stringify(payload))


func _send(c: Client, status: int, extra_headers: Dictionary, body: String, close := false) -> void:
	const REASONS := {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
		404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large", 431: "Request Header Fields Too Large"}
	var payload := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\n" % [status, REASONS.get(status, "Error")]
	if not extra_headers.has("Content-Type") and body != "":
		head += "Content-Type: text/plain; charset=utf-8\r\n"
	for k in extra_headers:
		head += "%s: %s\r\n" % [k, extra_headers[k]]
	head += "Content-Length: %d\r\n" % payload.size()
	head += "Connection: %s\r\n\r\n" % ("close" if close else "keep-alive")
	var out := head.to_utf8_buffer()
	out.append_array(payload)
	c.peer.put_data(out)
	if close:
		c.closing = true


# ---------------------------------------------------------------- JSON-RPC

func _rpc_error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}


func _rpc_result(id: Variant, result: Variant) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _handle_message(msg: Variant) -> Variant:
	if not (msg is Dictionary) or str(msg.get("jsonrpc", "")) != "2.0":
		return _rpc_error(null, -32600, "Invalid request")
	if not msg.has("method"):
		return null  # A response from the client; nothing to do.
	if not msg.has("id"):
		return null  # Notification (e.g. notifications/initialized).
	var id: Variant = msg["id"]
	# Godot parses every JSON number as float; echo integer ids back as integers.
	if typeof(id) == TYPE_FLOAT and id == floorf(id):
		id = int(id)
	var method := str(msg["method"])
	var params: Variant = msg.get("params", {})
	if not (params is Dictionary):
		params = {}

	match method:
		"initialize":
			var wanted := str(params.get("protocolVersion", ""))
			return _rpc_result(id, {
				"protocolVersion": wanted if wanted in PROTOCOL_VERSIONS else FALLBACK_PROTOCOL,
				"capabilities": {"tools": {"listChanged": false}},
				"serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
				"instructions": INSTRUCTIONS,
			})
		"ping":
			return _rpc_result(id, {})
		"tools/list":
			return _rpc_result(id, {"tools": _tools.list_tools()})
		"tools/call":
			var tool_name := str(params.get("name", ""))
			if not _tools.has_tool(tool_name):
				return _rpc_error(id, -32602, "Unknown tool: " + tool_name)
			var args: Variant = params.get("arguments", {})
			if not (args is Dictionary):
				args = {}
			var outcome: Dictionary = _tools.call_tool(tool_name, args)
			if outcome.has("__pending"):
				return {"__pending": outcome["__pending"], "id": id}
			return _rpc_result(id, outcome)
	return _rpc_error(id, -32601, "Method not found: " + method)
