@tool
extends EditorPlugin
## Local MCP - a localhost-only MCP server inside the Godot editor.
## Nothing in this addon opens an outbound connection or collects telemetry.

const McpServer := preload("mcp_server.gd")
const McpTools := preload("mcp_tools.gd")
const OutputCapture := preload("output_capture.gd")
const DebuggerBridge := preload("debugger_bridge.gd")

const SETTING_PORT := "local_mcp/port"
const SETTING_TOKEN := "local_mcp/auth_token"
const SETTING_RUNTIME := "local_mcp/enable_game_runtime"
const SETTING_READ_ONLY := "local_mcp/read_only"
const SETTING_COMPACT := "local_mcp/compact_mode"
const DEFAULT_PORT := 9777
const RUNTIME_AUTOLOAD := "LocalMcpRuntime"
const MENU_ITEM := "Local MCP: Copy connection info"

var _server: RefCounted
var _capture: RefCounted
var _bridge: EditorDebuggerPlugin


func _enter_tree() -> void:
	_register_setting(SETTING_PORT, DEFAULT_PORT, TYPE_INT)
	_register_setting(SETTING_TOKEN, "", TYPE_STRING)
	_register_setting(SETTING_RUNTIME, true, TYPE_BOOL)
	_register_setting(SETTING_READ_ONLY, false, TYPE_BOOL)
	_register_setting(SETTING_COMPACT, false, TYPE_BOOL)

	_capture = OutputCapture.new()
	_capture.setup()
	_bridge = DebuggerBridge.new()
	add_debugger_plugin(_bridge)
	_sync_runtime_autoload()

	var port := int(ProjectSettings.get_setting(SETTING_PORT, DEFAULT_PORT))
	var env_port := OS.get_environment("LOCAL_MCP_PORT")
	if env_port.is_valid_int():
		port = int(env_port)

	var tools := McpTools.new(self, _capture)
	tools.set_bridge(_bridge)
	_server = McpServer.new(tools)
	var bound: int = _server.start(port, str(ProjectSettings.get_setting(SETTING_TOKEN, "")))
	if bound == 0:
		push_error("[Local MCP] Could not listen on 127.0.0.1:%d-%d. Change Project Settings > local_mcp/port." % [port, port + 9])
	else:
		print("[Local MCP] Listening on %s (localhost only, %d tools)" % [_server.url(), tools.list_tools().size()])
	add_tool_menu_item(MENU_ITEM, _copy_info)
	set_process(true)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_ITEM)
	if _server:
		_server.stop()
		_server = null
	if _bridge:
		remove_debugger_plugin(_bridge)
		_bridge = null
	if _capture:
		_capture.teardown()
		_capture = null


func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + RUNTIME_AUTOLOAD):
		remove_autoload_singleton(RUNTIME_AUTOLOAD)


func _process(_delta: float) -> void:
	if _server:
		_server.poll()


## The game-side helper is an autoload so the game tools (screenshot, input, live tree) work.
func _sync_runtime_autoload() -> void:
	var wanted := bool(ProjectSettings.get_setting(SETTING_RUNTIME, true))
	var present := ProjectSettings.has_setting("autoload/" + RUNTIME_AUTOLOAD)
	if wanted and not present:
		add_autoload_singleton(RUNTIME_AUTOLOAD, get_script().resource_path.get_base_dir() + "/runtime/mcp_runtime.gd")
	elif not wanted and present:
		remove_autoload_singleton(RUNTIME_AUTOLOAD)


func _register_setting(name: String, default_value: Variant, type: int) -> void:
	if not ProjectSettings.has_setting(name):
		ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)
	ProjectSettings.add_property_info({"name": name, "type": type})
	ProjectSettings.set_as_basic(name, true)


func _copy_info() -> void:
	if _server == null or _server.port == 0:
		push_warning("[Local MCP] Server is not running.")
		return
	var url: String = _server.url()
	DisplayServer.clipboard_set(url)
	print("[Local MCP] URL copied to clipboard: ", url)
	print("[Local MCP] Claude Code:  claude mcp add --transport http godot ", url)
	print("[Local MCP] JSON config:  {\"mcpServers\": {\"godot\": {\"type\": \"http\", \"url\": \"", url, "\"}}}")
