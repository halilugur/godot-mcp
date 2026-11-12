@tool
extends RefCounted
## Play/stop project, logs, breakpoints, test runner, multiplayer, and live game_* runtime tools.

const Values := preload("../mcp_values.gd")

var _host: RefCounted


func register(host: RefCounted) -> void:
	_host = host
	var s := {"type": "string"}
	var string_list := {"type": "array", "items": s}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root."}
	var game_path := {"type": "string", "description": "Node path in the running game: relative to the current scene ('.' is its root), an autoload name, or absolute like /root/Main/Player."}

	_reg("run_project", "Run the game from the editor.", {
		"mode": {"type": "string", "enum": ["main", "current", "custom"], "description": "main scene (default), currently edited scene, or a custom scene"},
		"scene_path": {"type": "string", "description": "Scene for mode=custom"},
	})
	_reg("stop_project", "Stop the running game.")
	_reg("get_output", "Recent log output. source=editor: editor messages and script errors. source=game: the log file of the last game run (prints, errors, stack traces).", {
		"source": {"type": "string", "enum": ["editor", "game"], "description": "Default editor"},
		"lines": {"type": "integer", "description": "Default 100"},
	}, [], true)
	_reg("set_breakpoint", "Set or clear a script breakpoint in an active game debugger session.", {
		"path": {"type": "string", "description": "res:// path to a .gd script"},
		"line": {"type": "integer", "description": "1-based line number"},
		"enabled": {"type": "boolean", "description": "Default true"},
	}, ["path", "line"], false, false)
	_reg("run_tests", "Run project tests headlessly using GUT, gdUnit4, or a custom SceneTree test script and return pass/fail output.", {
		"runner": {"type": "string", "description": "auto, gut, gdunit4, or script. Default auto."},
		"path": {"type": "string", "description": "Optional res:// test directory or script path (e.g. res://tests)"},
	}, [], true, false)
	_reg("setup_multiplayer_sync", "Create a MultiplayerSynchronizer or MultiplayerSpawner configured with properties or spawnable scenes (undoable).", {
		"parent_path": {"type": "string", "description": "Default '.'"},
		"mode": {"type": "string", "description": "synchronizer or spawner. Default synchronizer."},
		"root_path": {"type": "string", "description": "For synchronizer: target node path (default '..')"},
		"properties": {"type": "array", "items": s, "description": "For synchronizer: node properties to replicate (e.g. [\"position\", \"rotation\"])"},
		"spawn_path": {"type": "string", "description": "For spawner: spawn parent path (default '..')"},
		"spawnable_scenes": {"type": "array", "items": s, "description": "For spawner: list of res:// .tscn paths"},
	}, [], false, false)
	_reg("game_get_scene_tree", "Live node tree of the running game, with current scene, pause state and FPS. Requires run_project.", {
		"node_path": {"type": "string", "description": "Subtree root. Default: /root"},
		"max_depth": {"type": "integer", "description": "Default 8"},
	}, [], true)
	_reg("game_get_node_properties", "Live property values of a node in the running game. Default: its script variables and common properties.", {
		"node_path": game_path,
		"properties": string_list,
	}, ["node_path"], true)
	_reg("game_set_node_properties", "Change properties of a node in the running game (not saved to the scene).", {
		"node_path": game_path,
		"properties": {"type": "object"},
	}, ["node_path", "properties"])
	_reg("game_call_method", "Call a method on a node in the running game and return its result.", {
		"node_path": game_path,
		"method": s,
		"args": {"type": "array", "description": "Arguments; Godot expression strings are converted"},
	}, ["node_path", "method"])
	_reg("game_send_input", "Send input to the running game. Events run in order: {\"type\": \"action\", \"action\": \"jump\"}, {\"type\": \"key\", \"key\": \"Space\"}, {\"type\": \"mouse_button\", \"button\": 1, \"position\": [400, 300]}, {\"type\": \"mouse_motion\", \"position\": [10, 10]}. Without \"pressed\" an event is a tap: press, hold for \"hold\" seconds (default 0.1), release. With \"pressed\": true/false only that state is sent. \"wait\" pauses after the event.", {
		"events": {"type": "array", "items": {"type": "object"}},
	}, ["events"])
	_reg("game_screenshot", "PNG screenshot of the running game.", {
		"max_width": {"type": "integer", "description": "Downscale to this width. Default 1280."},
	}, [], true)
	_reg("game_resume", "Continue a game that is stopped in the debugger after a script error or breakpoint.")
	_reg("game_execute_script", "Run GDScript inside the running game. The code is the body of `func run(tree: SceneTree, scene: Node)`; `return` a value to get it back. `await` is allowed (keep it under 15 seconds).", {
		"code": s,
	}, ["code"])
	_reg("game_get_performance_monitors", "Read live Performance monitors (FPS, frame/physics time, draw calls, primitives, video/static memory, objects, orphan nodes, active physics bodies) from the running game.", {}, [], true, false)
	_reg("game_find_nodes", "Find nodes in the running game by name glob pattern, class type, or group.", {
		"name": {"type": "string", "description": "Case-insensitive glob pattern, e.g. \"Enemy*\""},
		"type": {"type": "string", "description": "Class name (matches subclasses too)"},
		"group": s,
		"limit": {"type": "integer", "description": "Default 100"},
	}, [], true, false)
	_reg("game_pause", "Pause or unpause the running game's SceneTree (or query current pause state when paused is omitted).", {
		"paused": {"type": "boolean"},
	}, [], false, false)
	_reg("game_set_time_scale", "Set Engine.time_scale in the running game (e.g. 0.25 for slow-mo, 2.0 for fast-forward, 1.0 for normal).", {
		"time_scale": {"type": "number"},
	}, ["time_scale"], false, false)
	_reg("game_change_scene", "Switch the running game to a different .tscn scene via get_tree().change_scene_to_file().", {
		"path": {"type": "string", "description": "res:// path to a .tscn file"},
	}, ["path"], false, false)
	_reg("game_get_groups", "List nodes in a group in the running game, or list all active user groups if group is omitted.", {
		"group": {"type": "string", "description": "Optional group name"},
	}, [], true, false)
	_reg("game_emit_signal", "Emit a signal on a node in the running game with optional arguments.", {
		"node_path": game_path,
		"signal_name": s,
		"args": {"type": "array", "description": "Optional arguments (JSON or Godot expression strings)"},
	}, ["node_path", "signal_name"], false, false)
	_reg("game_get_ui_elements", "List visible Control UI elements in the running game with their text, class, disabled state, and screen coordinates (rect + center) for clicking via game_send_input.", {
		"include_invisible": {"type": "boolean", "description": "Default false"},
		"interactive_only": {"type": "boolean", "description": "Only BaseButton, LineEdit, TextEdit, Slider, SpinBox, OptionButton, TabBar. Default false."},
	}, [], true, false)
	_reg("game_raycast", "Cast a live 2D or 3D physics ray between 'from' and 'to' in the running game and return hit collider, position, and normal.", {
		"from": {"type": "string", "description": "Vector2 or Vector3 expression, e.g. \"Vector2(0, 0)\" or \"Vector3(0, 1, 0)\""},
		"to": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"collision_mask": {"type": "integer", "description": "Optional bitmask, default all layers (0xFFFFFFFF)"},
		"collide_with_areas": {"type": "boolean", "description": "Default true"},
		"collide_with_bodies": {"type": "boolean", "description": "Default true"},
	}, ["from", "to"], true, false)
	_reg("game_watch_signals", "Watch signals on a node in the running game and read/clear recorded signal emissions.", {
		"action": {"type": "string", "description": "watch, read, or clear. Default read."},
		"node_path": game_path,
		"signals": {"type": "array", "items": s, "description": "For watch: signal names to record (omit to watch all user/common signals on the node)"},
	}, [], false, false)
	_reg("game_set_locale", "Get or change TranslationServer locale in the running game (e.g. 'en', 'tr', 'ja').", {
		"locale": {"type": "string", "description": "Optional locale code. If omitted, returns current and loaded locales."},
	}, [], false, false)
	_reg("game_get_camera_info", "Read the active Camera2D or Camera3D position, zoom/fov, and viewport size in the running game.", {}, [], true, false)
	_reg("game_spawn_node", "Spawn a Node or PackedScene (.tscn) live inside the running game for testing.", {
		"parent_path": {"type": "string", "description": "Parent path in the running game, default '.'"},
		"type": {"type": "string", "description": "Node class name (or use scene_path)"},
		"scene_path": {"type": "string", "description": "res:// path to a .tscn scene"},
		"name": s,
		"properties": {"type": "object", "description": "Initial properties to set on the spawned node"},
	}, [], false, false)
	_reg("game_destroy_node", "Queue-free (destroy) a node in the running game.", {
		"node_path": game_path,
	}, ["node_path"], false, true)
	_reg("game_teleport_node", "Teleport a Node2D/Node3D/Control in the running game to a target position and optionally zero its velocity.", {
		"node_path": game_path,
		"position": {"type": "string", "description": "Vector2 or Vector3 expression"},
		"global": {"type": "boolean", "description": "Use global_position. Default true."},
		"zero_velocity": {"type": "boolean", "description": "Zero 'velocity' property if present. Default true."},
	}, ["node_path", "position"], false, false)
	_reg("game_mouse_drag", "Simulate a smooth mouse drag from 'from' [x, y] to 'to' [x, y] in the running game (great for drag-and-drop UI or camera panning).", {
		"from": {"type": "array", "items": {"type": "number"}, "description": "[x, y] start screen position"},
		"to": {"type": "array", "items": {"type": "number"}, "description": "[x, y] end screen position"},
		"button": {"type": "integer", "description": "Mouse button index, default 1 (left)"},
		"steps": {"type": "integer", "description": "Interpolation steps, default 10"},
		"duration": {"type": "number", "description": "Total duration in seconds, default 0.3"},
	}, ["from", "to"], false, false)
	_reg("game_get_physics_info", "Inspect live physics state of a CharacterBody2D/3D, RigidBody2D/3D, or Area2D/3D in the running game.", {
		"node_path": game_path,
	}, ["node_path"], true, false)
	_reg("game_eval_expression", "Evaluate a single Godot Expression in the running game against an optional base node.", {
		"expression": {"type": "string", "description": "Expression string, e.g. \"get_child_count() * 2\" or \"position.length()\""},
		"node_path": {"type": "string", "description": "Optional context node path, default '.'"},
	}, ["expression"], true, false)
	_reg("game_step_frames", "Advance the running game by N process or physics frames and return elapsed time and FPS.", {
		"frames": {"type": "integer", "description": "Number of frames to wait (1..300), default 10"},
		"physics": {"type": "boolean", "description": "Wait physics frames instead of process frames. Default false."},
	}, [], false, false)
	_reg("game_get_orphan_nodes", "Check orphan node count (memory leak detector) and object counts in the running game.", {}, [], true, false)


func _reg(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_host._register_tool(tname, description, properties, required, read_only, destructive, Callable(self, "_tool_" + tname))


func _tool_run_project(args: Dictionary) -> Variant:
	var mode := str(args.get("mode", "main"))
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	match mode:
		"main":
			if str(ProjectSettings.get_setting("application/run/main_scene", "")) == "":
				return _host._err("No main scene is set. Use mode=current, or set_project_setting application/run/main_scene.")
			EditorInterface.play_main_scene()
		"current":
			var root: Variant = _host._root()
			if root == null or root.scene_file_path == "":
				return _host._err("The edited scene must be saved before it can run.")
			EditorInterface.play_current_scene()
		"custom":
			var path: Variant = _host._res_path(args.get("scene_path", ""))
			if path == "" or not ResourceLoader.exists(path):
				return _host._err("Scene not found: " + str(args.get("scene_path", "")))
			EditorInterface.play_custom_scene(path)
		_:
			return _host._err("mode must be main, current or custom.")
	return {"started": mode, "hint": "Use get_output source=game after a moment to read prints and errors, and stop_project to stop."}


func _tool_stop_project(_args: Dictionary) -> Variant:
	var was_playing := EditorInterface.is_playing_scene()
	if was_playing:
		EditorInterface.stop_playing_scene()
	return {"stopped": was_playing}


func _tool_get_output(args: Dictionary) -> Variant:
	var count := clampi(_host._to_int(args.get("lines"), 100), 1, 2000)
	if str(args.get("source", "editor")) == "game":
		var log_path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
		if not FileAccess.file_exists(log_path):
			return _host._err("No game log at %s yet. Run the project first (file logging must be enabled in Project Settings > Debug > File Logging)." % log_path)
		var lines := FileAccess.get_file_as_string(log_path).split("\n")
		return "\n".join(lines.slice(maxi(lines.size() - count, 0)))
	var tail: PackedStringArray = _host._capture.tail(count)
	return "\n".join(tail) if not tail.is_empty() else "(no output)"


func _tool_set_breakpoint(args: Dictionary) -> Variant:
	if _host._bridge == null:
		return _host._err("Debugger bridge is not available.")
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Script not found: " + str(args.get("path", "")))
	var line := maxi(1, int(args.get("line", 1)))
	var enabled := bool(args.get("enabled", true))
	var applied := 0
	for session in _host._bridge.get_sessions():
		session.set_breakpoint(path, line, enabled)
		applied += 1
	return {"path": path, "line": line, "enabled": enabled, "sessions_updated": applied}


func _tool_run_tests(args: Dictionary) -> Variant:
	var runner := str(args.get("runner", "auto")).to_lower()
	var test_path := str(args.get("path", "res://tests"))
	var godot_bin := OS.get_executable_path()
	var proj_dir := ProjectSettings.globalize_path("res://")

	if runner == "auto":
		if FileAccess.file_exists("res://addons/gut/gut_cmdln.gd"):
			runner = "gut"
		elif FileAccess.file_exists("res://addons/gdUnit4/runtest.gd"):
			runner = "gdunit4"
		elif FileAccess.file_exists(test_path) and test_path.ends_with(".gd"):
			runner = "script"
		else:
			return _host._err("No GUT (addons/gut/gut_cmdln.gd) or gdUnit4 (addons/gdUnit4/runtest.gd) found. Pass runner='script' and path='res://.../test.gd' to run a SceneTree test script.")

	var cmd_args := PackedStringArray(["--headless", "--path", proj_dir])
	match runner:
		"gut":
			cmd_args.append("-s")
			cmd_args.append("addons/gut/gut_cmdln.gd")
			cmd_args.append("-gdir=" + test_path)
			cmd_args.append("-gexit")
		"gdunit4":
			cmd_args.append("-s")
			cmd_args.append("addons/gdUnit4/runtest.gd")
			cmd_args.append("-a")
			cmd_args.append(test_path)
		"script":
			var rp: String = _host._res_path(test_path)
			if rp == "" or not FileAccess.file_exists(rp):
				return _host._err("Test script not found: " + test_path)
			cmd_args.append("--script")
			cmd_args.append(rp)
		_:
			return _host._err("Unknown runner '%s'. Use auto, gut, gdunit4, or script." % runner)

	var output := []
	var exit_code := OS.execute(godot_bin, cmd_args, output, true)
	var text := "\n".join(output)
	if text.length() > 16000:
		text = text.substr(text.length() - 16000)
	return {
		"runner": runner,
		"exit_code": exit_code,
		"passed": exit_code == 0,
		"output": text,
	}


func _tool_setup_multiplayer_sync(args: Dictionary) -> Variant:
	var root: Node = _host._root()
	if root == null: return _host._no_node(".")
	var parent: Node = _host._find(args.get("parent_path", "."))
	if parent == null: return _host._no_node(args.get("parent_path", "."))
	var mode := str(args.get("mode", "synchronizer")).to_lower()

	if mode == "spawner":
		var sp := MultiplayerSpawner.new()
		sp.name = "MultiplayerSpawner"
		sp.spawn_path = NodePath(str(args.get("spawn_path", "..")))
		var scenes: Variant = args.get("spawnable_scenes", [])
		if scenes is Array:
			for sc in scenes:
				sp.add_spawnable_scene(str(sc))
		_host._host._add_child_undo(parent, sp, "MCP: Add MultiplayerSpawner")
		return {"path": _host._path_of(sp), "type": "MultiplayerSpawner"}

	var sync := MultiplayerSynchronizer.new()
	sync.name = "MultiplayerSynchronizer"
	sync.root_path = NodePath(str(args.get("root_path", "..")))
	var cfg := SceneReplicationConfig.new()
	var props: Variant = args.get("properties", [])
	if props is Array:
		for p in props:
			cfg.add_property(NodePath(":" + str(p).trim_prefix(":")))
	sync.replication_config = cfg
	_host._host._add_child_undo(parent, sync, "MCP: Add MultiplayerSynchronizer")
	return {"path": _host._path_of(sync), "type": "MultiplayerSynchronizer", "replicated": cfg.get_properties().size()}


func _tool_game_get_scene_tree(args: Dictionary) -> Variant:
	return _host._game("tree", args)


func _tool_game_get_node_properties(args: Dictionary) -> Variant:
	return _host._game("get", args)


func _tool_game_set_node_properties(args: Dictionary) -> Variant:
	return _host._game("set", args)


func _tool_game_call_method(args: Dictionary) -> Variant:
	return _host._game("call", args)


func _tool_game_send_input(args: Dictionary) -> Variant:
	return _host._game("input", args)


func _tool_game_screenshot(args: Dictionary) -> Variant:
	return _host._game("screenshot", args)


func _tool_game_resume(_args: Dictionary) -> Variant:
	if not EditorInterface.is_playing_scene():
		return _host._err("The game is not running.")
	if _host._bridge == null or not _host._bridge.resume():
		return {"resumed": false, "note": "The game was not stopped in the debugger."}
	return {"resumed": true}


func _tool_game_execute_script(args: Dictionary) -> Variant:
	var code := str(args.get("code", ""))
	if code.strip_edges() == "":
		return _host._err("code is empty.")
	# Compile here first: a parse error inside the running game would stop it in the debugger.
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	var check := GDScript.new()
	check.source_code = "extends RefCounted\n\nfunc run(tree: SceneTree, scene: Node) -> Variant:\n" + body + "\treturn null\n"
	var marker: int = _host._capture.mark()
	if check.reload() != OK:
		var problems: Variant = _host._error_lines(_host._capture.since(marker))
		return _host._err("The code did not compile (line numbers are offset by 3).\n" + ("\n".join(problems) if not problems.is_empty() else "See get_output source=editor."))
	return _host._game("exec", args)


func _tool_game_get_performance_monitors(args: Dictionary) -> Variant:
	return _host._game("perf", args)


func _tool_game_find_nodes(args: Dictionary) -> Variant:
	return _host._game("find", args)


func _tool_game_pause(args: Dictionary) -> Variant:
	return _host._game("pause", args)


func _tool_game_set_time_scale(args: Dictionary) -> Variant:
	return _host._game("time_scale", args)


func _tool_game_change_scene(args: Dictionary) -> Variant:
	var path: String = _host._res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _host._err("Scene not found: " + str(args.get("path", "")))
	return _host._game("change_scene", {"path": path})


func _tool_game_get_groups(args: Dictionary) -> Variant:
	return _host._game("groups", args)


func _tool_game_emit_signal(args: Dictionary) -> Variant:
	return _host._game("emit", args)


func _tool_game_get_ui_elements(args: Dictionary) -> Variant:
	return _host._game("ui", args)


func _tool_game_raycast(args: Dictionary) -> Variant:
	return _host._game("raycast", args)


func _tool_game_watch_signals(args: Dictionary) -> Variant:
	return _host._game("watch_signals", args)


func _tool_game_set_locale(args: Dictionary) -> Variant:
	return _host._game("locale", args)


func _tool_game_get_camera_info(args: Dictionary) -> Variant:
	return _host._game("camera", args)


func _tool_game_spawn_node(args: Dictionary) -> Variant:
	return _host._game("spawn", args)


func _tool_game_destroy_node(args: Dictionary) -> Variant:
	return _host._game("destroy", args)


func _tool_game_teleport_node(args: Dictionary) -> Variant:
	return _host._game("teleport", args)


func _tool_game_mouse_drag(args: Dictionary) -> Variant:
	return _host._game("drag", args)


func _tool_game_get_physics_info(args: Dictionary) -> Variant:
	return _host._game("physics", args)


func _tool_game_eval_expression(args: Dictionary) -> Variant:
	return _host._game("eval", args)


func _tool_game_step_frames(args: Dictionary) -> Variant:
	return _host._game("step", args)


func _tool_game_get_orphan_nodes(args: Dictionary) -> Variant:
	return _host._game("orphans", args)
