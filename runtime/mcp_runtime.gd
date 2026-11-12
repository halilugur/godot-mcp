extends Node
## Game half of Local MCP (autoload "LocalMcpRuntime").
## Answers editor requests over Godot's own debugger connection. It opens no sockets and
## removes itself when no debugger is attached, so it does nothing in exported builds.

const Values := preload("../mcp_values.gd")
const PREFIX := "local_mcp"
const SHOT_PATH := "user://local_mcp_screenshot.png"
const COMMON_PROPERTIES := ["position", "global_position", "rotation", "scale", "visible", "velocity", "size", "text", "modulate", "process_mode"]

var _registered := false


func _ready() -> void:
	if not EngineDebugger.is_active():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	EngineDebugger.register_message_capture(PREFIX, _on_message)
	_registered = true


func _exit_tree() -> void:
	if _registered:
		EngineDebugger.unregister_message_capture(PREFIX)
		_registered = false


func _on_message(message: String, data: Array) -> bool:
	if message.trim_prefix(PREFIX + ":") != "cmd" or data.size() < 3:
		return false
	_dispatch(int(data[0]), str(data[1]), data[2] if data[2] is Dictionary else {})
	return true


func _dispatch(ticket: int, command: String, args: Dictionary) -> void:
	var result: Variant
	match command:
		"tree":
			result = _cmd_tree(args)
		"get":
			result = _cmd_get(args)
		"set":
			result = _cmd_set(args)
		"call":
			result = await _cmd_call(args)
		"input":
			result = await _cmd_input(args)
		"screenshot":
			result = await _cmd_screenshot(args)
		"exec":
			result = await _cmd_exec(args)
		_:
			result = _err("Unknown command: " + command)
	EngineDebugger.send_message(PREFIX + ":reply", [ticket, result])


func _err(message: String) -> Dictionary:
	return {"__error": message}


func _node(path: Variant) -> Node:
	var tree := get_tree()
	var scene := tree.current_scene
	var p := str(path) if path != null else ""
	if p == "" or p == ".":
		return scene if scene != null else tree.root
	if p.begins_with("/"):
		return tree.root.get_node_or_null(NodePath(p))
	if scene != null:
		if p == str(scene.name):
			return scene
		var found := scene.get_node_or_null(NodePath(p))
		if found != null:
			return found
	return tree.root.get_node_or_null(NodePath(p))  # Autoloads and other root children.


func _no_node(path: Variant) -> Dictionary:
	return _err("Node not found in the running game: '%s'. Use game_get_scene_tree. Paths are relative to the current scene, or absolute like /root/Main/Player." % str(path))


func _describe(node: Node, depth: int, max_depth: int) -> Dictionary:
	var info := {"name": str(node.name), "type": node.get_class()}
	var script: Variant = node.get_script()
	if script is Script and script.resource_path != "":
		info["script"] = script.resource_path
	var children := []
	var hidden := 0
	for child in node.get_children():
		if child == self:
			continue
		if depth >= max_depth:
			hidden += 1
		else:
			children.append(_describe(child, depth + 1, max_depth))
	if not children.is_empty():
		info["children"] = children
	if hidden > 0:
		info["children_not_shown"] = hidden
	return info


func _cmd_tree(args: Dictionary) -> Variant:
	var tree := get_tree()
	var start := _node(args["node_path"]) if args.has("node_path") else tree.root
	if start == null:
		return _no_node(args.get("node_path"))
	var scene := tree.current_scene
	return {
		"current_scene": scene.scene_file_path if scene != null else null,
		"current_scene_path": str(scene.get_path()) if scene != null else null,
		"paused": tree.paused,
		"fps": Engine.get_frames_per_second(),
		"viewport_size": Values.to_json(get_viewport().get_visible_rect().size),
		"tree": _describe(start, 0, clampi(int(args.get("max_depth", 8)), 0, 64)),
	}


func _cmd_get(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var props := {}
	var wanted: Variant = args.get("properties")
	if wanted is Array and not wanted.is_empty():
		for name in wanted:
			var key := str(name)
			if key.split(":")[0] in node:
				props[key] = Values.to_json(node.get_indexed(NodePath(key)))
			else:
				props[key] = "<no such property>"
	else:
		for p in node.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
				props[p["name"]] = Values.to_json(node.get(p["name"]))
		for key in COMMON_PROPERTIES:
			if key in node:
				props[key] = Values.to_json(node.get(key))
	return {"path": str(node.get_path()), "type": node.get_class(), "properties": props}


func _cmd_set(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var values: Variant = args.get("properties")
	if not (values is Dictionary) or values.is_empty():
		return _err("properties must be a non-empty object.")
	var errors := Values.apply_properties(node, values)
	var now := {}
	for key in values:
		if str(key).split(":")[0] in node:
			now[str(key)] = Values.to_json(node.get_indexed(NodePath(str(key))))
	if not errors.is_empty():
		return _err("\n".join(errors))
	return {"path": str(node.get_path()), "properties": now}


func _cmd_call(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var method := str(args.get("method", ""))
	if not node.has_method(method):
		return _err("%s has no method '%s'." % [node.get_class(), method])
	var call_args := []
	var raw: Variant = args.get("args", [])
	if raw is Array:
		for item in raw:
			call_args.append(Values.coerce(item, TYPE_NIL)[1])
	var result: Variant = await node.callv(method, call_args)
	return {"result": Values.to_json(result)}


func _vec(value: Variant) -> Vector2:
	var r := Values.coerce(value, TYPE_VECTOR2)
	return r[1] if r[0] and r[1] != null else Vector2.ZERO


func _cmd_input(args: Dictionary) -> Variant:
	var events: Variant = args.get("events", [])
	if not (events is Array) or events.is_empty():
		return _err("events must be a non-empty array.")
	var sent := 0
	for e in events:
		if not (e is Dictionary):
			return _err("Each event must be an object.")
		var tap: bool = not e.has("pressed")
		var pressed: bool = bool(e.get("pressed", true))
		var event: InputEvent
		match str(e.get("type", "")):
			"action":
				var action := str(e.get("action", ""))
				if not InputMap.has_action(action):
					return _err("Unknown input action '%s'. Actions: %s" % [action, ", ".join(_custom_actions())])
				var a := InputEventAction.new()
				a.action = action
				a.strength = float(e.get("strength", 1.0))
				event = a
			"key":
				var code := OS.find_keycode_from_string(str(e.get("key", "")))
				if code == KEY_NONE:
					return _err("Unknown key '%s'. Use names like A, Space, Enter, Escape, Left, Shift." % str(e.get("key", "")))
				var k := InputEventKey.new()
				k.keycode = code
				k.physical_keycode = code
				k.shift_pressed = bool(e.get("shift", false))
				k.ctrl_pressed = bool(e.get("ctrl", false))
				k.alt_pressed = bool(e.get("alt", false))
				event = k
			"mouse_button":
				var b := InputEventMouseButton.new()
				b.button_index = int(e.get("button", 1)) as MouseButton
				b.position = _vec(e.get("position"))
				b.global_position = b.position
				b.double_click = bool(e.get("double_click", false))
				event = b
			"mouse_motion":
				var m := InputEventMouseMotion.new()
				m.position = _vec(e.get("position"))
				m.global_position = m.position
				m.relative = _vec(e.get("relative"))
				event = m
				tap = false
			_:
				return _err("Event type must be action, key, mouse_button or mouse_motion.")
		if not (event is InputEventMouseMotion):
			event.set("pressed", pressed)
		Input.parse_input_event(event)
		sent += 1
		if tap:
			await get_tree().create_timer(maxf(float(e.get("hold", 0.1)), 0.0), true, false, true).timeout
			var release := event.duplicate()
			release.set("pressed", false)
			Input.parse_input_event(release)
		var wait := float(e.get("wait", 0.0))
		if wait > 0.0:
			await get_tree().create_timer(wait, true, false, true).timeout
	await get_tree().process_frame
	return {"events_sent": sent}


func _custom_actions() -> Array:
	var out := []
	for a in InputMap.get_actions():
		if not str(a).begins_with("ui_"):
			out.append(str(a))
	return out


func _cmd_screenshot(args: Dictionary) -> Variant:
	if DisplayServer.get_name() == "headless":
		return _err("The game is running headless; there is nothing to capture.")
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return _err("Could not capture the game viewport.")
	var max_width := clampi(int(args.get("max_width", 1280)), 64, 4096)
	if image.get_width() > max_width:
		image.resize(max_width, int(float(image.get_height()) * max_width / image.get_width()), Image.INTERPOLATE_LANCZOS)
	var err := image.save_png(SHOT_PATH)
	if err != OK:
		return _err("Could not save the screenshot: " + error_string(err))
	return {"__image_path": ProjectSettings.globalize_path(SHOT_PATH)}


func _cmd_exec(args: Dictionary) -> Variant:
	var body := ""
	for line in str(args.get("code", "")).split("\n"):
		body += "\t" + line + "\n"
	var script := GDScript.new()
	script.source_code = "extends RefCounted\n\nfunc run(tree: SceneTree, scene: Node) -> Variant:\n" + body + "\treturn null\n"
	if script.reload() != OK:
		return _err("The code did not compile. See get_output source=game for the parse error (line numbers are offset by 3).")
	var runner: Variant = script.new()
	var result: Variant = await runner.run(get_tree(), get_tree().current_scene)
	return {"result": Values.to_json(result)}
