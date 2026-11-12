@tool
extends RefCounted
## Central MCP tool registry, shared editor/runtime helpers, and modular pack loader.

const Values := preload("mcp_values.gd")
const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "cs", "gdshader", "gdshaderinc", "cfg", "json", "md", "txt", "godot", "csv", "xml", "yml", "yaml", "toml", "ini", "import"]
const MAX_READ_BYTES := 400 * 1024
const SKIP_DIRS := [".godot", ".git", ".import"]

const ProjectTools := preload("tools/project_tools.gd")
const FileTools := preload("tools/file_tools.gd")
const SceneTools := preload("tools/scene_tools.gd")
const NodeTools := preload("tools/node_tools.gd")
const ScriptTools := preload("tools/script_tools.gd")
const EditorTools := preload("tools/editor_tools.gd")
const ResourceTools := preload("tools/resource_tools.gd")
const VisualTools := preload("tools/visual_tools.gd")
const UiTools := preload("tools/ui_tools.gd")
const AnimationTools := preload("tools/animation_tools.gd")
const AudioTools := preload("tools/audio_tools.gd")
const TileTools := preload("tools/tile_tools.gd")
const WorldTools := preload("tools/world_tools.gd")
const PhysicsTools := preload("tools/physics_tools.gd")
const RuntimeTools := preload("tools/runtime_tools.gd")

const CUSTOM_TOOLS_DIR := "res://mcp_tools"
const RUNTIME_AUTOLOAD := "LocalMcpRuntime"
const COMPACT_CORE_TOOLS := [
	"get_project_info", "list_files", "read_file", "write_file", "edit_file",
	"open_scene", "save_scene", "get_scene_tree", "add_node", "set_node_properties",
	"run_project", "stop_project", "get_output", "take_screenshot", "discover_tools",
]
const TOOL_CATEGORIES := {
	"project": [
		"get_project_info", "get_project_settings", "set_project_setting", "get_project_statistics",
		"list_input_actions", "add_input_action", "remove_input_action", "add_standard_input_preset",
		"add_autoload", "remove_autoload", "get_autoload_info", "list_export_presets",
		"export_project", "manage_editor_plugins", "git_status",
	],
	"filesystem": [
		"list_files", "read_file", "write_file", "edit_file", "create_directory", "move_file",
		"delete_file", "search_files", "rescan_filesystem", "set_import_settings",
		"clean_orphan_imports", "get_asset_info", "edit_config_file", "find_broken_references",
	],
	"scene": [
		"open_scene", "create_scene", "save_scene", "reload_scene", "get_open_scenes",
		"get_scene_tree", "get_scene_metrics", "list_scene_dependencies", "check_scene_warnings",
		"save_branch_as_scene", "set_editable_children", "find_resource_usages",
	],
	"node": [
		"add_node", "batch_add_nodes", "delete_node", "move_node", "duplicate_node",
		"replace_node_type", "find_nodes", "get_node_properties", "set_node_properties",
		"batch_set_properties", "set_node_groups", "set_node_unique_name", "connect_signal",
		"batch_connect_signals", "get_node_signals", "setup_timer",
	],
	"script": [
		"create_script", "attach_script", "validate_script", "validate_all_scripts",
		"get_script_symbols", "add_script_member", "rename_symbol_in_project", "lint_gdscript",
		"get_class_info", "search_classes", "search_class_members",
	],
	"editor": [
		"get_selection", "select_nodes", "open_in_editor", "undo", "redo", "get_editor_state",
		"set_editor_screen", "focus_editor_camera", "take_screenshot", "execute_editor_script",
	],
	"resource": [
		"create_resource", "get_resource_properties", "set_resource_properties", "duplicate_resource",
		"create_gradient", "create_noise_texture", "create_curve_resource", "list_translations",
		"set_translation_entries",
	],
	"visual": [
		"create_shader", "get_shader_params", "set_shader_params", "setup_world_environment",
		"create_particle_system", "get_sprite_frames", "set_sprite_frames", "setup_camera",
		"setup_light", "setup_2d_vector_node", "setup_3d_fx_node", "setup_parallax", "setup_subviewport",
	],
	"ui": [
		"create_stylebox", "configure_theme", "set_theme_overrides", "set_ui_anchors_preset",
		"setup_ui_container", "setup_label_settings",
	],
	"animation": [
		"get_animations", "set_animation", "remove_animation", "get_animation_tree",
		"control_animation_tree", "build_animation_state_machine", "setup_blend_space",
	],
	"audio": [
		"list_audio_buses", "configure_audio_bus", "setup_audio_player", "create_audio_randomizer",
	],
	"tilemap_world": [
		"get_tilemap_cells", "set_tilemap_cells", "fill_tilemap_rect", "paint_tilemap_terrain",
		"get_tileset_info", "setup_tileset_source", "get_gridmap_cells", "set_gridmap_cells",
		"create_mesh_library", "create_primitive_mesh", "create_csg_shape", "populate_multimesh",
		"setup_path", "get_skeleton_bones", "add_bone_attachment", "arrange_nodes",
	],
	"physics_nav": [
		"setup_collision_shape", "generate_mesh_collision", "create_physics_joint",
		"setup_raycast", "physics_layers", "setup_navigation_node", "bake_navigation_mesh",
	],
	"runtime": [
		"run_project", "stop_project", "get_output", "set_breakpoint", "run_tests",
		"setup_multiplayer_sync", "game_get_scene_tree", "game_get_node_properties",
		"game_set_node_properties", "game_call_method", "game_send_input", "game_screenshot",
		"game_resume", "game_execute_script", "game_get_performance_monitors", "game_find_nodes",
		"game_pause", "game_set_time_scale", "game_change_scene", "game_get_groups",
		"game_emit_signal", "game_get_ui_elements", "game_raycast", "game_watch_signals",
		"game_set_locale", "game_get_camera_info", "game_spawn_node", "game_destroy_node",
		"game_teleport_node", "game_mouse_drag", "game_get_physics_info", "game_eval_expression",
		"game_step_frames", "game_get_orphan_nodes",
	],
	"toolkit": [
		"user_list_files", "user_read_file", "user_write_file", "user_delete_file",
		"discover_tools", "reload_custom_tools",
	],
}

var _plugin: EditorPlugin
var _capture: RefCounted
var _bridge: EditorDebuggerPlugin
var _defs: Array = []
var _names := {}
var _handlers := {}
var _modules := []
var _custom_names := {}
var _custom_instances := []
var _tool_category_map := {}
var _shots := {}
var _next_shot := -1


func _init(plugin: EditorPlugin, capture: RefCounted) -> void:
	_plugin = plugin
	_capture = capture
	_build_definitions()


func set_bridge(bridge: EditorDebuggerPlugin) -> void:
	_bridge = bridge


func _build_definitions() -> void:
	_defs.clear()
	_names.clear()
	_handlers.clear()
	_tool_category_map.clear()
	for cat in TOOL_CATEGORIES:
		for tname in TOOL_CATEGORIES[cat]:
			_tool_category_map[tname] = cat
	_modules = [
		ProjectTools.new(),
		FileTools.new(),
		SceneTools.new(),
		NodeTools.new(),
		ScriptTools.new(),
		EditorTools.new(),
		ResourceTools.new(),
		VisualTools.new(),
		UiTools.new(),
		AnimationTools.new(),
		AudioTools.new(),
		TileTools.new(),
		WorldTools.new(),
		PhysicsTools.new(),
		RuntimeTools.new(),
	]
	for mod in _modules:
		mod.register(self)
	load_custom_extensions()


func _register_tool(tname: String, description: String, properties := {}, required := [], read_only := false, destructive := false, handler := Callable()) -> void:
	_names[tname] = true
	_defs.append({
		"name": tname,
		"description": description,
		"inputSchema": {"type": "object", "properties": properties, "required": required},
		"annotations": {"readOnlyHint": read_only, "destructiveHint": destructive},
	})
	if handler.is_valid():
		_handlers[tname] = handler


func is_read_only_mode() -> bool:
	var env := OS.get_environment("LOCAL_MCP_READ_ONLY").to_lower()
	if env in ["1", "true", "yes"]:
		return true
	return bool(ProjectSettings.get_setting("local_mcp/read_only", false))


func is_compact_mode() -> bool:
	var env := OS.get_environment("LOCAL_MCP_COMPACT").to_lower()
	if env in ["1", "true", "yes"]:
		return true
	return bool(ProjectSettings.get_setting("local_mcp/compact_mode", false))


func all_tool_definitions() -> Array:
	if not is_read_only_mode():
		return _defs
	var out := []
	for d in _defs:
		if bool(d.get("annotations", {}).get("readOnlyHint", false)):
			out.append(d)
	return out


func list_tools() -> Array:
	var pool := all_tool_definitions()
	if not is_compact_mode():
		return pool
	var out := []
	for d in pool:
		var n := str(d["name"])
		if n in COMPACT_CORE_TOOLS or _custom_names.has(n):
			out.append(d)
	return out


func get_tool_category(tname: String) -> String:
	if _custom_names.has(tname):
		return "custom"
	return str(_tool_category_map.get(tname, "general"))


func get_category_summary() -> Dictionary:
	var counts := {}
	for d in all_tool_definitions():
		var cat := get_tool_category(str(d["name"]))
		counts[cat] = int(counts.get(cat, 0)) + 1
	return counts


func has_tool(tname: String) -> bool:
	return _names.has(tname)


func _is_tool_read_only(tname: String) -> bool:
	for d in _defs:
		if str(d["name"]) == tname:
			return bool(d.get("annotations", {}).get("readOnlyHint", false))
	return false


func call_tool(tname: String, args: Dictionary) -> Dictionary:
	if is_read_only_mode() and not _is_tool_read_only(tname):
		return format_result(_err("Read-only mode is active (local_mcp/read_only). Mutating tool '%s' is disabled." % tname))
	if not _handlers.has(tname):
		return format_result(_err("Unknown tool: " + tname))
	var result: Variant = _handlers[tname].call(args)
	if result is Dictionary and result.has("__pending"):
		return result
	return format_result(result)


func format_result(result: Variant) -> Dictionary:
	if result is Dictionary and result.has("__error"):
		return {"content": [{"type": "text", "text": Values.clean_text(str(result["__error"]))}], "isError": true}
	if result is Dictionary and result.has("__image"):
		return {"content": [{"type": "image", "data": result["__image"], "mimeType": "image/png"}], "isError": false}
	var text: String = result if result is String else JSON.stringify(result, "  ")
	return {"content": [{"type": "text", "text": Values.clean_text(text)}], "isError": false}


func poll_pending(ticket: int) -> Variant:
	if ticket < 0:
		if not _shots.has(ticket):
			return format_result(_err("Nothing is pending."))
		var shot: Dictionary = _shots[ticket]
		shot["frames"] -= 1
		if shot["frames"] > 0:
			return null
		_shots.erase(ticket)
		var cap: Variant = _capture_viewport(shot["target"], shot["max_width"])
		return format_result(cap)
	if _bridge == null:
		return format_result(_err("Debugger bridge is not ready."))
	var answer: Variant = _bridge.take(ticket)
	if answer == null:
		return null
	if answer is Dictionary and answer.has("image_base64"):
		return format_result({"__image": answer["image_base64"]})
	return format_result(answer)


func cancel_pending(ticket: int) -> void:
	if ticket < 0:
		_shots.erase(ticket)
	elif _bridge != null:
		_bridge.cancel(ticket)


func _game(command: String, args: Dictionary) -> Dictionary:
	if not _plugin.get_editor_interface().is_playing_scene():
		return _err("No game is running. Call run_project first.")
	if _bridge == null:
		return _err("Debugger bridge is not active.")
	var ticket: int = _bridge.send_command(command, args)
	if ticket < 0:
		return _err("Game runtime is not connected yet (try again in a moment, or check that LocalMcpRuntime autoload is active).")
	return {"__pending": ticket}


func load_custom_extensions() -> Dictionary:
	for cname in _custom_names.keys():
		_handlers.erase(cname)
		_names.erase(cname)
	for i in range(_defs.size() - 1, -1, -1):
		if _custom_names.has(str(_defs[i]["name"])):
			_defs.remove_at(i)
	_custom_names.clear()
	_custom_instances.clear()

	if not DirAccess.dir_exists_absolute(CUSTOM_TOOLS_DIR):
		return {"loaded": 0, "tools": []}
	var da := DirAccess.open(CUSTOM_TOOLS_DIR)
	if da == null:
		return {"loaded": 0, "tools": []}

	var loaded_tools := []
	var errors := []
	da.list_dir_begin()
	var entry := da.get_next()
	while entry != "":
		if not da.current_is_dir() and entry.ends_with(".gd"):
			var path := CUSTOM_TOOLS_DIR.path_join(entry)
			var scr := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
			if scr == null:
				errors.append("Failed to load: " + path)
			else:
				var inst: Variant = scr.new()
				_custom_instances.append(inst)
				if inst.has_method("get_mcp_tools") and inst.has_method("call_mcp_tool"):
					var defs: Variant = inst.call("get_mcp_tools")
					if defs is Array:
						for td in defs:
							if td is Dictionary and td.has("name"):
								var tname := str(td["name"])
								_custom_names[tname] = true
								_register_tool(
									tname,
									str(td.get("description", "")),
									td.get("properties", {}),
									td.get("required", []),
									bool(td.get("read_only", false)),
									bool(td.get("destructive", false)),
									func(a: Dictionary) -> Variant: return inst.call("call_mcp_tool", tname, a)
								)
								loaded_tools.append(tname)
		entry = da.get_next()
	return {"loaded": loaded_tools.size(), "tools": loaded_tools, "errors": errors}


func _err(message: String) -> Dictionary:
	return {"__error": message}


func _root() -> Node:
	return EditorInterface.get_edited_scene_root()


func _find(path: Variant) -> Node:
	var root := _root()
	if root == null:
		return null
	var p := str(path) if path != null else ""
	if p.begins_with("/root/"):
		p = p.substr(6)
	var root_name := str(root.name)
	if p == "" or p == "." or p == "/" or p == root_name:
		return root
	if p.begins_with(root_name + "/"):
		p = p.substr(root_name.length() + 1)
	return root.get_node_or_null(NodePath(p))


func _path_of(node: Node) -> String:
	var root := _root()
	if root == null or node == root:
		return "."
	return str(root.get_path_to(node))


func _no_node(path: Variant) -> Dictionary:
	if _root() == null:
		return _err("No scene is open in the editor. Use open_scene or create_scene first.")
	return _err("Node not found: '%s'. Use get_scene_tree to see valid paths." % str(path))


func _res_path(path: Variant) -> String:
	# Returns a normalized res:// path, or "" when the path is not inside the project.
	var p := str(path).strip_edges().replace("\\", "/")
	if p == "":
		return ""
	if not p.begins_with("res://"):
		if p.contains("://") or p.begins_with("/"):
			return ""
		p = "res://" + p
	p = p.simplify_path()
	if not p.begins_with("res://") or ".." in p.split("/"):
		return ""
	return p


func _to_int(value: Variant, fallback: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	return fallback


func _instantiate(type_name: String) -> Node:
	if ClassDB.class_exists(type_name):
		if ClassDB.is_parent_class(type_name, "Node") and ClassDB.can_instantiate(type_name):
			return ClassDB.instantiate(type_name)
		return null
	for info in ProjectSettings.get_global_class_list():
		if str(info["class"]) == type_name:
			var script: Variant = load(info["path"])
			if script is Script and script.can_instantiate():
				var obj: Variant = script.new()
				if obj is Node:
					return obj
				if obj is Object and not (obj is RefCounted):
					obj.free()
			elif script is Script:
				# Non-tool scripts cannot run in the editor: build the native base and attach the script.
				var base := str(script.get_instance_base_type())
				if ClassDB.is_parent_class(base, "Node") and ClassDB.can_instantiate(base):
					var node: Node = ClassDB.instantiate(base)
					node.set_script(script)
					return node
	return null


func _owned_nodes(node: Node) -> Array:
	# [node, owner] pairs for node and all descendants, so owners can be restored after re-adding.
	var out := [[node, node.owner]]
	for child in node.get_children():
		out.append_array(_owned_nodes(child))
	return out


func _filesystem_changed(path: String, created: bool) -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs == null:
		return
	if created:
		if not fs.is_scanning():
			fs.scan()
	else:
		fs.update_file(path)


func _scan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null and not fs.is_scanning():
		fs.scan()


func _walk(dir_path: String, recursive: bool, extensions: Array, out: Array, limit: int) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.include_hidden = false
	var base := dir_path if dir_path.ends_with("/") else dir_path + "/"
	var dirs := Array(dir.get_directories())
	var files := Array(dir.get_files())
	dirs.sort()
	files.sort()
	for f in files:
		if out.size() >= limit:
			return
		var ext := str(f).get_extension().to_lower()
		if extensions.is_empty():
			if ext == "import" or ext == "uid":
				continue
		elif not extensions.has(ext):
			continue
		out.append(base + f)
	if recursive:
		for d in dirs:
			if d in SKIP_DIRS:
				continue
			_walk(base + d, true, extensions, out, limit)


func _capture_viewport(target: String, max_width: int) -> Dictionary:
	var viewport: Viewport
	match target:
		"2d":
			viewport = EditorInterface.get_editor_viewport_2d()
		"3d":
			viewport = EditorInterface.get_editor_viewport_3d(0)
		_:
			viewport = EditorInterface.get_base_control().get_viewport()
	var texture := viewport.get_texture() if viewport != null else null
	var image: Image = texture.get_image() if texture != null else null
	if image == null or image.is_empty():
		return _err("Could not capture the viewport.")
	if image.get_width() > max_width:
		image.resize(max_width, int(float(image.get_height()) * max_width / image.get_width()), Image.INTERPOLATE_LANCZOS)
	return {"__image": Marshalls.raw_to_base64(image.save_png_to_buffer())}


func _add_child_undo(parent: Node, child: Node, label: String) -> void:
	var root: Node = _root()
	var ur: EditorUndoRedoManager = _plugin.get_undo_redo()
	ur.create_action(label)
	ur.add_do_method(parent, "add_child", child, true)
	ur.add_do_property(child, "owner", root)
	ur.add_do_reference(child)
	ur.add_undo_method(parent, "remove_child", child)
	ur.commit_action()


func _error_lines(lines: PackedStringArray) -> Array:
	var out := []
	for line in lines:
		var low := line.to_lower()
		if (low.contains("error") or low.contains("warning")) and not out.has(line):
			out.append(line)
	return out


func _compile_script(path: String, new_source: Variant = null) -> Dictionary:
	# Compiles the script at `path` in place and reports what the editor logged.
	var marker: int = _capture.mark()
	var was_cached := ResourceLoader.has_cached(path)
	var script: Variant = load(path)
	if not (script is Script):
		return {"ok": false, "errors": ["Could not load script."] + _error_lines(_capture.since(marker))}
	if was_cached and new_source != null:
		script.source_code = new_source
	var code: int = script.reload(true)
	var messages := _error_lines(_capture.since(marker))
	var errors := []
	var warnings := []
	for m in messages:
		if m.to_lower().contains("warning") and not m.to_lower().contains("error"):
			warnings.append(m)
		else:
			errors.append(m)
	var ok := code == OK and errors.is_empty()
	if code != OK and errors.is_empty():
		errors.append("Script failed to compile (%s). See get_output source=editor." % error_string(code))
	var out := {"ok": ok}
	if not errors.is_empty():
		out["errors"] = errors
	if not warnings.is_empty():
		out["warnings"] = warnings
	return out


# ---------------------------------------------------------------- project and files

func _prepare_properties(node: Object, values: Dictionary) -> Array:
	# Returns [changes, errors]; each change is [key, indexed, new_value, old_value].
	var types := {}
	for p in node.get_property_list():
		types[str(p["name"])] = p["type"]
	var changes := []
	var errors := []
	for key_v in values:
		var key := str(key_v)
		var indexed := key.contains(":")
		var base := key.split(":")[0]
		if not types.has(base):
			var similar := []
			for name in types:
				if name.contains(base) or base.contains(name):
					similar.append(name)
			errors.append("%s: no such property on %s%s" % [key, node.get_class(), (" (similar: %s)" % ", ".join(similar.slice(0, 8))) if not similar.is_empty() else ""])
			continue
		var old: Variant = node.get_indexed(NodePath(key)) if indexed else node.get(key)
		var type: int = typeof(old) if indexed else int(types[key])
		var r := Values.coerce(values[key_v], type)
		if not r[0]:
			errors.append("%s: %s" % [key, r[1]])
			continue
		changes.append([key, indexed, r[1], old])
	return [changes, errors]


func _write_text(path: String, content: String) -> Dictionary:
	var ext := path.get_extension().to_lower()
	if not TEXT_EXTENSIONS.has(ext):
		return _err("Only text files can be written (.%s is not allowed). Allowed: %s" % [ext, ", ".join(TEXT_EXTENSIONS)])
	var created := not FileAccess.file_exists(path)
	var dir_err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		return _err("Cannot create directory: " + error_string(dir_err))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _err("Cannot write %s: %s" % [path, error_string(FileAccess.get_open_error())])
	file.store_string(content)
	file.close()
	_filesystem_changed(path, created)
	var out := {"path": path, "created": created, "bytes": content.to_utf8_buffer().size()}
	if ext == "gd":
		out["script_check"] = _compile_script(path, content)
	var root := _root()
	if (ext == "tscn" or ext == "tres") and not created and root != null and root.scene_file_path == path:
		out["note"] = "This scene is open in the editor; call open_scene again to reload it from disk."
	return out


func _make_input_event(spec: Variant) -> Variant:
	# Returns an InputEvent, or a String with the problem.
	if not (spec is Dictionary):
		return "each event must be an object"
	if spec.has("key"):
		var code := OS.find_keycode_from_string(str(spec["key"]))
		if code == KEY_NONE:
			return "unknown key '%s' (use names like W, Space, Enter, Escape, Left, Shift)" % str(spec["key"])
		var k := InputEventKey.new()
		if bool(spec.get("physical", true)):
			k.physical_keycode = code
		else:
			k.keycode = code
		k.shift_pressed = bool(spec.get("shift", false))
		k.ctrl_pressed = bool(spec.get("ctrl", false))
		k.alt_pressed = bool(spec.get("alt", false))
		k.meta_pressed = bool(spec.get("meta", false))
		k.device = -1
		return k
	if spec.has("mouse_button"):
		var names := {"left": 1, "right": 2, "middle": 3, "wheel_up": 4, "wheel_down": 5}
		var raw: Variant = spec["mouse_button"]
		var index: int = names.get(str(raw).to_lower(), _to_int(raw, 0))
		if index <= 0:
			return "unknown mouse button '%s' (use left, right, middle, wheel_up, wheel_down or a number)" % str(raw)
		var b := InputEventMouseButton.new()
		b.button_index = index as MouseButton
		b.device = -1
		return b
	if spec.has("joypad_button"):
		var j := InputEventJoypadButton.new()
		j.button_index = _to_int(spec["joypad_button"], 0) as JoyButton
		j.device = -1
		return j
	if spec.has("joypad_axis"):
		var m := InputEventJoypadMotion.new()
		m.axis = _to_int(spec["joypad_axis"], 0) as JoyAxis
		m.axis_value = float(spec.get("axis_value", 1.0))
		m.device = -1
		return m
	return "an event needs one of: key, mouse_button, joypad_button, joypad_axis"


func _describe_node(node: Node, root: Node, depth: int, max_depth: int) -> Dictionary:
	var info := {"name": str(node.name), "type": node.get_class()}
	var script: Variant = node.get_script()
	if script is Script and script.resource_path != "":
		info["script"] = script.resource_path
	if node != root and node.scene_file_path != "":
		info["instance_of"] = node.scene_file_path
	var children := []
	var hidden := 0
	for child in node.get_children():
		if child.owner != root:
			continue  # Internals of instanced scenes and editor-only helpers.
		if depth >= max_depth:
			hidden += 1
		else:
			children.append(_describe_node(child, root, depth + 1, max_depth))
	if not children.is_empty():
		info["children"] = children
	if hidden > 0:
		info["children_not_shown"] = hidden
	return info


func _collect_owned_copies(original: Node, copy: Node, root: Node, out: Array) -> void:
	# Pairs the copy's descendants with the original's to find which ones belong to the scene.
	var a := original.get_children()
	var b := copy.get_children()
	for i in mini(a.size(), b.size()):
		if a[i].owner == root:
			out.append(b[i])
			_collect_owned_copies(a[i], b[i], root, out)


func _scene_nodes(node: Node, root: Node, out: Array) -> void:
	out.append(node)
	for child in node.get_children():
		if child.owner == root:
			_scene_nodes(child, root, out)


func _script_methods(script: Script) -> Array:
	var names := []
	for m in script.get_script_method_list():
		names.append(str(m["name"]))
	return names


func _scene_history() -> UndoRedo:
	var root: Variant = _root()
	if root == null:
		return null
	var ur: Variant = _plugin.get_undo_redo()
	return ur.get_history_undo_redo(ur.get_object_history_id(root))


func _estimate_sibling_size(col_node: Node, is_2d: bool) -> Vector3:
	var parent := col_node.get_parent()
	if parent == null:
		return Vector3.ZERO
	for sibling in parent.get_children():
		if sibling == col_node:
			continue
		if is_2d:
			if sibling is Sprite2D and sibling.texture != null:
				var sz: Vector2 = sibling.texture.get_size()
				if sibling.region_enabled:
					sz = sibling.region_rect.size
				sz = Vector2(sz.x / maxf(1, sibling.hframes), sz.y / maxf(1, sibling.vframes)) * sibling.scale.abs()
				return Vector3(sz.x, sz.y, 0)
			if sibling is ColorRect:
				return Vector3(sibling.size.x, sibling.size.y, 0)
		else:
			if sibling is MeshInstance3D and sibling.mesh != null:
				var aabb: AABB = sibling.mesh.get_aabb()
				var s: Vector3 = aabb.size * sibling.scale.abs()
				return s
	return Vector3.ZERO


func _set_owner_recursive(node: Node, root: Node) -> void:
	node.owner = root
	if node.scene_file_path == "":
		for c in node.get_children():
			_set_owner_recursive(c, root)

