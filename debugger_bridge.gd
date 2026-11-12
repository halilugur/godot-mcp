@tool
extends EditorDebuggerPlugin
## Editor half of the game bridge. Uses Godot's existing editor<->game debugger channel;
## it opens no sockets of its own.

const PREFIX := "local_mcp"

var _next_ticket := 1
var _waiting := {}
var _results := {}


func _has_capture(capture: String) -> bool:
	return capture == PREFIX


func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message != PREFIX + ":reply" or data.size() < 2:
		return false
	var ticket := int(data[0])
	if _waiting.has(ticket):
		_waiting.erase(ticket)
		_results[ticket] = data[1]
	return true


## Sends a command to the running game. Returns a ticket, or -1 when no game is connected.
func send(command: String, args: Dictionary) -> int:
	for session in get_sessions():
		if session.is_active():
			var ticket := _next_ticket
			_next_ticket += 1
			_waiting[ticket] = true
			session.send_message(PREFIX + ":cmd", [ticket, command, args])
			return ticket
	return -1


## Returns [true, result] once the game answered, otherwise [false, null].
func take(ticket: int) -> Array:
	if _results.has(ticket):
		var result: Variant = _results[ticket]
		_results.erase(ticket)
		return [true, result]
	return [false, null]


func cancel(ticket: int) -> void:
	_waiting.erase(ticket)
	_results.erase(ticket)


## True when the running game is stopped in the debugger (script error or breakpoint).
func is_breaked() -> bool:
	for session in get_sessions():
		if session.is_active() and session.is_breaked():
			return true
	return false


## Tells a game stopped in the debugger to continue. Returns false when nothing was stopped.
func resume() -> bool:
	var resumed := false
	for session in get_sessions():
		if session.is_active() and session.is_breaked():
			session.send_message("continue", [])
			resumed = true
	return resumed
