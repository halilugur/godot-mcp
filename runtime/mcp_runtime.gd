extends Node
## Game half of Local MCP (autoload "LocalMcpRuntime").
## Answers editor requests over Godot's own debugger connection. It opens no sockets and
## removes itself when no debugger is attached, so it does nothing in exported builds.

const Values := preload("../mcp_values.gd")
const PREFIX := "local_mcp"
const SHOT_PATH := "user://local_mcp_screenshot.png"
const COMMON_PROPERTIES := ["position", "global_position", "rotation", "scale", "visible", "velocity", "size", "text", "modulate", "process_mode"]

var _registered := false
var _signal_log := []


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
		"perf":
			result = _cmd_perf(args)
		"find":
			result = _cmd_find(args)
		"pause":
			result = _cmd_pause(args)
		"time_scale":
			result = _cmd_time_scale(args)
		"change_scene":
			result = _cmd_change_scene(args)
		"groups":
			result = _cmd_groups(args)
		"emit":
			result = _cmd_emit(args)
		"ui":
			result = _cmd_ui(args)
		"raycast":
			result = _cmd_raycast(args)
		"watch_signals":
			result = _cmd_watch_signals(args)
		"locale":
			result = _cmd_locale(args)
		"camera":
			result = _cmd_camera(args)
		"spawn":
			result = _cmd_spawn(args)
		"destroy":
			result = _cmd_destroy(args)
		"teleport":
			result = _cmd_teleport(args)
		"drag":
			result = await _cmd_drag(args)
		"physics":
			result = _cmd_physics(args)
		"eval":
			result = _cmd_eval(args)
		"step":
			result = await _cmd_step(args)
		"orphans":
			result = _cmd_orphans(args)
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


func _cmd_perf(_args: Dictionary) -> Variant:
	return {
		"fps": Performance.get_monitor(Performance.TIME_FPS),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_process_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"navigation_process_ms": Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0,
		"memory_static_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"memory_static_max_mb": Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1048576.0,
		"video_memory_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"render_total_objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
		"render_total_primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"render_total_draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"physics_2d_active_objects": int(Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS)),
		"physics_3d_active_objects": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"audio_output_latency_ms": Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY) * 1000.0,
	}


func _cmd_find(args: Dictionary) -> Variant:
	var name_pat := str(args.get("name", ""))
	var type_name := str(args.get("type", ""))
	var group_name := str(args.get("group", ""))
	var limit := clampi(int(args.get("limit", 100)), 1, 1000)
	var matches := []
	_walk_find(get_tree().root, name_pat, type_name, group_name, matches, limit)
	return {"count": matches.size(), "matches": matches}


func _walk_find(node: Node, name_pat: String, type_name: String, group_name: String, out: Array, limit: int) -> void:
	if node == self or out.size() >= limit:
		return
	var ok := true
	if name_pat != "" and not str(node.name).matchn(name_pat):
		ok = false
	if ok and type_name != "" and not node.is_class(type_name):
		ok = false
	if ok and group_name != "" and not node.is_in_group(StringName(group_name)):
		ok = false
	if ok:
		out.append({"path": str(node.get_path()), "name": str(node.name), "type": node.get_class()})
	for c in node.get_children():
		_walk_find(c, name_pat, type_name, group_name, out, limit)


func _cmd_pause(args: Dictionary) -> Variant:
	var tree := get_tree()
	if args.has("paused"):
		tree.paused = bool(args["paused"])
	return {"paused": tree.paused}


func _cmd_time_scale(args: Dictionary) -> Variant:
	Engine.time_scale = maxf(0.0, float(args.get("time_scale", 1.0)))
	return {"time_scale": Engine.time_scale}


func _cmd_change_scene(args: Dictionary) -> Variant:
	var path := str(args.get("path", ""))
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		return _err("change_scene_to_file failed: " + error_string(err))
	return {"changed_to": path}


func _cmd_groups(args: Dictionary) -> Variant:
	var tree := get_tree()
	var g := str(args.get("group", ""))
	if g != "":
		var nodes := []
		for n in tree.get_nodes_in_group(StringName(g)):
			if n != self:
				nodes.append({"path": str(n.get_path()), "name": str(n.name), "type": n.get_class()})
		return {"group": g, "count": nodes.size(), "nodes": nodes}
	var all_groups := {}
	_collect_groups(tree.root, all_groups)
	return {"groups": all_groups}


func _collect_groups(node: Node, out: Dictionary) -> void:
	if node == self:
		return
	for g in node.get_groups():
		var gs := str(g)
		if not gs.begins_with("_"):
			out[gs] = int(out.get(gs, 0)) + 1
	for c in node.get_children():
		_collect_groups(c, out)


func _cmd_emit(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path", ""))
	var sig := StringName(str(args.get("signal_name", "")))
	if not node.has_signal(sig):
		return _err("Node %s has no signal '%s'." % [node.get_path(), sig])
	var raw_args: Variant = args.get("args", [])
	var call_args := [sig]
	if raw_args is Array:
		for a in raw_args:
			var c := Values.coerce(a, TYPE_NIL)
			call_args.append(c[1] if c[0] else a)
	node.callv("emit_signal", call_args)
	return {"emitted": str(sig), "node": str(node.get_path())}


func _cmd_ui(args: Dictionary) -> Variant:
	var include_inv := bool(args.get("include_invisible", false))
	var interactive_only := bool(args.get("interactive_only", false))
	var items := []
	_collect_ui(get_tree().root, include_inv, interactive_only, items)
	return {"count": items.size(), "elements": items}


func _collect_ui(node: Node, include_inv: bool, interactive_only: bool, out: Array) -> void:
	if node == self:
		return
	if node is Control:
		var ctrl := node as Control
		if not include_inv and not ctrl.is_visible_in_tree():
			return
		var is_interactive := (ctrl is BaseButton or ctrl is LineEdit or ctrl is TextEdit or ctrl is Range or ctrl is OptionButton or ctrl is TabBar)
		if not interactive_only or is_interactive:
			var rect := ctrl.get_global_rect()
			var entry := {
				"path": str(ctrl.get_path()),
				"name": str(ctrl.name),
				"type": ctrl.get_class(),
				"visible": ctrl.is_visible_in_tree(),
				"rect": {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y},
				"center": [rect.position.x + rect.size.x * 0.5, rect.position.y + rect.size.y * 0.5],
			}
			var txt: Variant = ctrl.get("text")
			if txt != null and str(txt) != "":
				entry["text"] = str(txt)
			if ctrl is BaseButton:
				entry["disabled"] = (ctrl as BaseButton).disabled
			out.append(entry)
	for c in node.get_children():
		_collect_ui(c, include_inv, interactive_only, out)


func _cmd_raycast(args: Dictionary) -> Variant:
	var c_from := Values.coerce(args.get("from"), TYPE_NIL)
	var c_to := Values.coerce(args.get("to"), TYPE_NIL)
	if not c_from[0] or not c_to[0]:
		return _err("Invalid from/to expression.")
	var from_v: Variant = c_from[1]
	var to_v: Variant = c_to[1]
	var mask := int(args.get("collision_mask", 0xFFFFFFFF))
	var with_areas := bool(args.get("collide_with_areas", true))
	var with_bodies := bool(args.get("collide_with_bodies", true))

	if from_v is Vector2 and to_v is Vector2:
		var space2d := get_viewport().world_2d.direct_space_state
		var q := PhysicsRayQueryParameters2D.create(from_v, to_v, mask)
		q.collide_with_areas = with_areas
		q.collide_with_bodies = with_bodies
		var hit := space2d.intersect_ray(q)
		if hit.is_empty():
			return {"hit": false}
		return {
			"hit": true,
			"position": Values.to_json(hit["position"]),
			"normal": Values.to_json(hit["normal"]),
			"collider": str(hit["collider"].get_path()) if hit["collider"] is Node else str(hit["collider"]),
			"collider_type": hit["collider"].get_class() if hit["collider"] is Object else "",
		}
	elif from_v is Vector3 and to_v is Vector3:
		var space3d := get_viewport().world_3d.direct_space_state
		var q3 := PhysicsRayQueryParameters3D.create(from_v, to_v, mask)
		q3.collide_with_areas = with_areas
		q3.collide_with_bodies = with_bodies
		var hit3 := space3d.intersect_ray(q3)
		if hit3.is_empty():
			return {"hit": false}
		return {
			"hit": true,
			"position": Values.to_json(hit3["position"]),
			"normal": Values.to_json(hit3["normal"]),
			"collider": str(hit3["collider"].get_path()) if hit3["collider"] is Node else str(hit3["collider"]),
			"collider_type": hit3["collider"].get_class() if hit3["collider"] is Object else "",
		}
	return _err("from and to must both be Vector2 or both be Vector3.")


func _on_watched_signal(node_path: String, sig_name: String) -> void:
	_signal_log.append({
		"time_ms": Time.get_ticks_msec(),
		"node": node_path,
		"signal": sig_name,
	})
	if _signal_log.size() > 500:
		_signal_log.pop_front()


func _cmd_watch_signals(args: Dictionary) -> Variant:
	var action := str(args.get("action", "read")).to_lower()
	if action == "clear":
		_signal_log.clear()
		return {"cleared": true}
	if action == "read":
		return {"count": _signal_log.size(), "events": _signal_log.duplicate()}
	if action == "watch":
		var node := _node(args.get("node_path", ""))
		if node == null:
			return _no_node(args.get("node_path", ""))
		var wanted: Variant = args.get("signals", [])
		var wanted_set := {}
		if wanted is Array:
			for w in wanted:
				wanted_set[str(w)] = true
		var attached := []
		var npath := str(node.get_path())
		for sig in node.get_signal_list():
			var sname := str(sig["name"])
			if not wanted_set.is_empty() and not wanted_set.has(sname):
				continue
			if wanted_set.is_empty() and sname in ["tree_entered", "tree_exiting", "tree_exited", "child_entered_tree", "child_exiting_tree", "child_order_changed", "renamed", "property_list_changed", "script_changed"]:
				continue
			var arg_count: int = sig["args"].size()
			var cb := Callable(self, "_on_watched_signal").bind(npath, sname).unbind(arg_count)
			if not node.is_connected(StringName(sname), cb):
				node.connect(StringName(sname), cb)
			attached.append(sname)
		return {"node": npath, "watching": attached}
	return _err("action must be watch, read, or clear.")


func _cmd_locale(args: Dictionary) -> Variant:
	if args.has("locale") and str(args["locale"]) != "":
		TranslationServer.set_locale(str(args["locale"]))
	return {
		"locale": TranslationServer.get_locale(),
		"loaded_locales": Array(TranslationServer.get_loaded_locales()),
	}


func _cmd_camera(_args: Dictionary) -> Variant:
	var vp := get_viewport()
	var out: Dictionary = {"viewport_size": Values.to_json(vp.get_visible_rect().size)}
	var cam2d := vp.get_camera_2d()
	if cam2d != null:
		out["camera_2d"] = {
			"path": str(cam2d.get_path()),
			"global_position": Values.to_json(cam2d.global_position),
			"screen_center": Values.to_json(cam2d.get_screen_center_position()),
			"zoom": Values.to_json(cam2d.zoom),
		}
	var cam3d := vp.get_camera_3d()
	if cam3d != null:
		out["camera_3d"] = {
			"path": str(cam3d.get_path()),
			"global_position": Values.to_json(cam3d.global_position),
			"global_rotation_deg": Values.to_json(cam3d.global_rotation_degrees),
			"fov": cam3d.fov,
		}
	return out


func _cmd_spawn(args: Dictionary) -> Variant:
	var parent := _node(args.get("parent_path", "."))
	if parent == null:
		return _no_node(args.get("parent_path", "."))
	var node: Node = null
	var scene_path := str(args.get("scene_path", ""))
	var type_name := str(args.get("type", ""))
	if scene_path != "":
		if not ResourceLoader.exists(scene_path):
			return _err("Scene not found: " + scene_path)
		var packed := load(scene_path) as PackedScene
		if packed == null:
			return _err("Not a PackedScene: " + scene_path)
		node = packed.instantiate()
	elif type_name != "":
		if not ClassDB.class_exists(type_name) or not ClassDB.is_parent_class(type_name, "Node") or not ClassDB.can_instantiate(type_name):
			return _err("Cannot instantiate Node class: " + type_name)
		node = ClassDB.instantiate(type_name)
	else:
		return _err("Provide 'type' or 'scene_path'.")

	if args.has("name") and str(args["name"]) != "":
		node.name = str(args["name"])
	var props: Variant = args.get("properties", {})
	if props is Dictionary and not props.is_empty():
		var errs := Values.apply_properties(node, props)
		if not errs.is_empty():
			node.free()
			return _err("; ".join(errs))
	parent.add_child(node)
	return {"spawned": str(node.get_path()), "type": node.get_class()}


func _cmd_destroy(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path", ""))
	if node == get_tree().root or node == self:
		return _err("Cannot destroy root or LocalMcpRuntime.")
	var path := str(node.get_path())
	node.queue_free()
	return {"destroyed": path}


func _cmd_teleport(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path", ""))
	var is_3d := node is Node3D
	var c := Values.coerce(args.get("position"), TYPE_VECTOR3 if is_3d else TYPE_VECTOR2)
	if not c[0]:
		return _err("position: " + str(c[1]))
	var prop := "global_position" if bool(args.get("global", true)) else "position"
	node.set(prop, c[1])
	if bool(args.get("zero_velocity", true)) and "velocity" in node:
		node.set("velocity", Vector3.ZERO if is_3d else Vector2.ZERO)
	return {"path": str(node.get_path()), prop: Values.to_json(node.get(prop))}


func _cmd_drag(args: Dictionary) -> Variant:
	var f_arr: Variant = args.get("from", [])
	var t_arr: Variant = args.get("to", [])
	if not (f_arr is Array) or not (t_arr is Array) or f_arr.size() < 2 or t_arr.size() < 2:
		return _err("from and to must be [x, y] arrays.")
	var from_p := Vector2(float(f_arr[0]), float(f_arr[1]))
	var to_p := Vector2(float(t_arr[0]), float(t_arr[1]))
	var btn := clampi(int(args.get("button", 1)), 1, 9)
	var steps := clampi(int(args.get("steps", 10)), 1, 120)
	var step_delay := maxf(0.01, float(args.get("duration", 0.3)) / float(steps))

	var press := InputEventMouseButton.new()
	press.button_index = btn
	press.position = from_p
	press.global_position = from_p
	press.pressed = true
	Input.parse_input_event(press)

	var prev := from_p
	for i in range(1, steps + 1):
		await get_tree().create_timer(step_delay, true, false, true).timeout
		var cur := from_p.lerp(to_p, float(i) / float(steps))
		var mov := InputEventMouseMotion.new()
		mov.position = cur
		mov.global_position = cur
		mov.relative = cur - prev
		mov.button_mask = 1 << (btn - 1)
		Input.parse_input_event(mov)
		prev = cur

	var rel := InputEventMouseButton.new()
	rel.button_index = btn
	rel.position = to_p
	rel.global_position = to_p
	rel.pressed = false
	Input.parse_input_event(rel)
	await get_tree().process_frame
	return {"dragged_from": Values.to_json(from_p), "to": Values.to_json(to_p), "steps": steps}


func _cmd_physics(args: Dictionary) -> Variant:
	var node := _node(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path", ""))
	var info := {"path": str(node.get_path()), "type": node.get_class()}
	if node is CharacterBody2D or node is CharacterBody3D:
		info["velocity"] = Values.to_json(node.get("velocity"))
		info["is_on_floor"] = node.call("is_on_floor")
		info["is_on_wall"] = node.call("is_on_wall")
		info["is_on_ceiling"] = node.call("is_on_ceiling")
		info["slide_collisions"] = node.call("get_slide_collision_count")
	elif node is RigidBody2D or node is RigidBody3D:
		info["linear_velocity"] = Values.to_json(node.get("linear_velocity"))
		info["angular_velocity"] = Values.to_json(node.get("angular_velocity"))
		info["mass"] = node.get("mass")
		info["sleeping"] = node.get("sleeping")
	elif node is Area2D or node is Area3D:
		info["overlapping_bodies"] = node.call("get_overlapping_bodies").size()
		info["overlapping_areas"] = node.call("get_overlapping_areas").size()
	else:
		return _err("%s is %s, not a CharacterBody, RigidBody, or Area." % [node.get_path(), node.get_class()])
	if "collision_layer" in node:
		info["collision_layer"] = node.get("collision_layer")
		info["collision_mask"] = node.get("collision_mask")
	return info


func _cmd_eval(args: Dictionary) -> Variant:
	var expr_str := str(args.get("expression", "")).strip_edges()
	if expr_str == "":
		return _err("expression is empty.")
	var base := _node(args.get("node_path", "."))
	if base == null:
		return _no_node(args.get("node_path", "."))
	var expr := Expression.new()
	var err := expr.parse(expr_str)
	if err != OK:
		return _err("Expression parse error: " + expr.get_error_text())
	var res: Variant = expr.execute([], base)
	if expr.has_execute_failed():
		return _err("Expression execution failed: " + expr.get_error_text())
	return {"result": Values.to_json(res)}


func _cmd_step(args: Dictionary) -> Variant:
	var frames := clampi(int(args.get("frames", 10)), 1, 300)
	var use_phys := bool(args.get("physics", false))
	var start_ms := Time.get_ticks_msec()
	var tree := get_tree()
	for i in frames:
		if use_phys:
			await tree.physics_frame
		else:
			await tree.process_frame
	return {"frames": frames, "physics": use_phys, "elapsed_ms": Time.get_ticks_msec() - start_ms, "fps": Engine.get_frames_per_second()}


func _cmd_orphans(_args: Dictionary) -> Variant:
	return {
		"orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resource_count": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}
