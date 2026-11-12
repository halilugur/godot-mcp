@tool
extends RefCounted
## Captures editor-process output so tools can report script errors.
## Godot 4.5+: uses the Logger API. Older versions: reads the editor Output panel.

# Compiled at runtime only when the Logger class exists, so this addon still parses on 4.3/4.4.
const LOGGER_SOURCE := """extends Logger

const MAX_LINES := 4000
var lines: PackedStringArray = PackedStringArray()
var total := 0
var mutex := Mutex.new()


func _push(text: String) -> void:
	mutex.lock()
	lines.append(text)
	total += 1
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES / 2)
	mutex.unlock()


func _log_message(message: String, error: bool) -> void:
	_push(message.strip_edges(false, true))


func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var kinds := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
	var text := rationale if rationale != "" else code
	_push("%s: %s (at %s:%d in %s)" % [kinds[clampi(error_type, 0, 3)], text, file, line, function])


func snapshot() -> Array:
	mutex.lock()
	var copy := [total, lines.duplicate()]
	mutex.unlock()
	return copy
"""

var _logger: Object
var _panel: RichTextLabel


func setup() -> void:
	if ClassDB.class_exists("Logger") and OS.has_method("add_logger"):
		var script := GDScript.new()
		script.source_code = LOGGER_SOURCE
		if script.reload() == OK:
			_logger = script.new()
			OS.call("add_logger", _logger)


func teardown() -> void:
	if _logger != null:
		OS.call("remove_logger", _logger)
		_logger = null


func uses_logger() -> bool:
	return _logger != null


func _find_panel() -> RichTextLabel:
	if _panel != null and is_instance_valid(_panel):
		return _panel
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	for log_node in base.find_children("*", "EditorLog", true, false):
		var labels := log_node.find_children("*", "RichTextLabel", true, false)
		if not labels.is_empty():
			_panel = labels[0]
			return _panel
	return null


## Returns an opaque marker for the current end of the output.
func mark() -> int:
	if _logger != null:
		return _logger.snapshot()[0]
	var panel := _find_panel()
	return panel.get_parsed_text().length() if panel != null else 0


## Returns the lines produced after `marker`.
func since(marker: int) -> PackedStringArray:
	if _logger != null:
		var snap: Array = _logger.snapshot()
		var lines: PackedStringArray = snap[1]
		var fresh: int = mini(snap[0] - marker, lines.size())
		return lines.slice(lines.size() - fresh) if fresh > 0 else PackedStringArray()
	var panel := _find_panel()
	if panel == null:
		return PackedStringArray()
	var text := panel.get_parsed_text()
	if marker > text.length():
		marker = 0
	return _clean(text.substr(marker).split("\n"))


func tail(count: int) -> PackedStringArray:
	var lines: PackedStringArray
	if _logger != null:
		lines = _logger.snapshot()[1]
	else:
		var panel := _find_panel()
		lines = _clean(panel.get_parsed_text().split("\n")) if panel != null else PackedStringArray()
	return lines.slice(maxi(lines.size() - count, 0))


func _clean(lines: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for line in lines:
		if line.strip_edges() != "":
			out.append(line)
	return out
