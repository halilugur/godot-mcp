@tool
extends RefCounted
## Tool definitions and implementations. Everything runs on the editor main thread.

const TEXT_EXTENSIONS := ["gd", "tscn", "tres", "cs", "gdshader", "gdshaderinc", "cfg", "json", "md", "txt", "godot", "csv", "xml", "yml", "yaml", "toml", "ini", "import"]
const MAX_READ_BYTES := 400 * 1024
const SKIP_DIRS := [".godot", ".git", ".import"]
const Values := preload("mcp_values.gd")

var _plugin: EditorPlugin
var _capture: RefCounted
var _defs: Array = []
var _names := {}
var _shots := {}
var _next_shot := -1


func _init(plugin: EditorPlugin, capture: RefCounted) -> void:
	_plugin = plugin
	_capture = capture
	_build_definitions()


# ---------------------------------------------------------------- registry

func list_tools() -> Array:
	return _defs


func has_tool(name: String) -> bool:
	return _names.has(name)


func call_tool(name: String, args: Dictionary) -> Dictionary:
	var result: Variant = call("_tool_" + name, args)
	if result is Dictionary and result.has("__pending"):
		return result  # Answered later through poll_pending().
	return format_result(result)


func format_result(result: Variant) -> Dictionary:
	if result is Dictionary and result.has("__error"):
		return {"content": [{"type": "text", "text": Values.clean_text(str(result["__error"]))}], "isError": true}
	if result is Dictionary and result.has("__image"):
		return {"content": [{"type": "image", "data": result["__image"], "mimeType": "image/png"}], "isError": false}
	var text: String = result if result is String else JSON.stringify(result, "  ")
	return {"content": [{"type": "text", "text": Values.clean_text(text)}], "isError": false}


## Tools that answer on a later frame return {"__pending": ticket}; the server then polls
## this every frame. Returns null while still waiting. Negative tickets are local screenshots.
func poll_pending(ticket: int) -> Variant:
	if not _shots.has(ticket):
		return format_result(_err("Nothing is pending."))
	var shot: Dictionary = _shots[ticket]
	shot["frames"] -= 1
	if shot["frames"] > 0:
		return null
	_shots.erase(ticket)
	return format_result(_capture_viewport(shot["target"], shot["max_width"]))


func cancel_pending(ticket: int) -> void:
	_shots.erase(ticket)


func _add(name: String, description: String, properties := {}, required := [], read_only := false, destructive := false) -> void:
	_names[name] = true
	_defs.append({
		"name": name,
		"description": description,
		"inputSchema": {"type": "object", "properties": properties, "required": required},
		"annotations": {"readOnlyHint": read_only, "destructiveHint": destructive},
	})


func _build_definitions() -> void:
	var s := {"type": "string"}
	var node_path := {"type": "string", "description": "Node path relative to the edited scene root. '.' is the root, e.g. 'Player/Sprite2D'."}

	_add("get_project_info", "Project name, Godot version, main scene, open scenes, autoloads and run state. Call this first.", {}, [], true)
	_add("list_files", "List project files under a res:// directory.", {
		"dir": {"type": "string", "description": "Directory, default res://"},
		"recursive": {"type": "boolean", "description": "Default true"},
		"extensions": {"type": "array", "items": s, "description": "Only these extensions, e.g. [\"gd\", \"tscn\"]"},
	}, [], true)
	_add("read_file", "Read a text file (script, scene, resource, config) from the project.", {
		"path": {"type": "string", "description": "res:// path"},
		"start_line": {"type": "integer", "description": "1-based first line, default 1"},
		"max_lines": {"type": "integer", "description": "Default: whole file"},
	}, ["path"], true)
	_add("write_file", "Create or overwrite a text file in the project. GDScript files are compiled afterwards and any errors are returned. Do not use this to edit a scene that is open in the editor; use the node tools instead.", {
		"path": {"type": "string", "description": "res:// path"},
		"content": s,
	}, ["path", "content"])
	_add("search_files", "Case-insensitive text search across project text files.", {
		"query": s,
		"dir": {"type": "string", "description": "Default res://"},
		"extensions": {"type": "array", "items": s, "description": "Default: gd, tscn, tres, cs, gdshader, cfg, json, md, txt"},
		"max_results": {"type": "integer", "description": "Default 100"},
	}, ["query"], true)
	_add("validate_script", "Compile a GDScript file and return its errors.", {"path": {"type": "string", "description": "res:// path to a .gd file"}}, ["path"], true)

	_add("open_scene", "Open a scene in the editor and make it the edited scene.", {"path": {"type": "string", "description": "res:// path to a .tscn/.scn"}}, ["path"])
	_add("create_scene", "Create a new scene file with a root node and open it.", {
		"path": {"type": "string", "description": "res:// path ending in .tscn"},
		"root_type": {"type": "string", "description": "Node class for the root, e.g. Node2D, Node3D, Control, CharacterBody2D"},
		"root_name": {"type": "string", "description": "Default: file name"},
	}, ["path", "root_type"])
	_add("save_scene", "Save the edited scene. Pass path to save as a new file.", {"path": {"type": "string", "description": "Optional res:// path for 'save as'"}})
	_add("get_scene_tree", "Node tree of the edited scene: names, types, scripts, instanced scenes.", {
		"node_path": {"type": "string", "description": "Subtree root, default '.'"},
		"max_depth": {"type": "integer", "description": "Default 8"},
	}, [], true)

	_add("get_node_properties", "Properties, script, groups and signal connections of a node.", {
		"node_path": node_path,
		"properties": {"type": "array", "items": s, "description": "Only these properties. Default: all editor-visible properties."},
	}, ["node_path"], true)
	_add("set_node_properties", "Set properties on a node (undoable). Values: JSON for bool/number/string; Godot expression strings for the rest, e.g. \"Vector2(10, 20)\", \"Color(1, 0, 0)\"; res:// paths for resources (use property 'script' to attach a script); null to clear. Sub-properties work as 'position:x'.", {
		"node_path": node_path,
		"properties": {"type": "object", "description": "Property name -> value"},
	}, ["node_path", "properties"])
	_add("add_node", "Add a node to the edited scene (undoable). Give either type (a class name, built-in or class_name) or scene_path (to instance a scene).", {
		"parent_path": {"type": "string", "description": "Parent node path, default '.'"},
		"type": {"type": "string", "description": "Node class, e.g. Sprite2D"},
		"scene_path": {"type": "string", "description": "res:// scene to instance instead of type"},
		"name": s,
		"properties": {"type": "object", "description": "Initial properties, same value rules as set_node_properties"},
		"index": {"type": "integer", "description": "Position among siblings, default last"},
	})
	_add("delete_node", "Delete a node and its children from the edited scene (undoable).", {"node_path": node_path}, ["node_path"])
	_add("move_node", "Rename, reparent and/or reorder a node (undoable).", {
		"node_path": node_path,
		"new_name": s,
		"new_parent_path": {"type": "string", "description": "New parent node path"},
		"index": {"type": "integer", "description": "New position among siblings"},
	}, ["node_path"])
	_add("connect_signal", "Connect (or disconnect) a node's signal to a method on another node; saved with the scene.", {
		"node_path": node_path,
		"signal": s,
		"target_path": {"type": "string", "description": "Node that has the method"},
		"method": s,
		"disconnect": {"type": "boolean", "description": "Remove the connection instead. Default false."},
	}, ["node_path", "signal", "target_path", "method"])

	_add("run_project", "Run the game from the editor.", {
		"mode": {"type": "string", "enum": ["main", "current", "custom"], "description": "main scene (default), currently edited scene, or a custom scene"},
		"scene_path": {"type": "string", "description": "Scene for mode=custom"},
	})
	_add("stop_project", "Stop the running game.")
	_add("get_output", "Recent log output. source=editor: editor messages and script errors. source=game: the log file of the last game run (prints, errors, stack traces).", {
		"source": {"type": "string", "enum": ["editor", "game"], "description": "Default editor"},
		"lines": {"type": "integer", "description": "Default 100"},
	}, [], true)
	_add("take_screenshot", "PNG screenshot of the editor: the 2D viewport, the 3D viewport, or the whole editor window.", {
		"target": {"type": "string", "enum": ["2d", "3d", "editor"], "description": "Default editor"},
		"max_width": {"type": "integer", "description": "Downscale to this width. Default 1280."},
	}, [], true)

	_add("get_class_info", "Properties, methods and signals of a Godot class. Use it instead of guessing API names.", {
		"class_name": s,
		"include_inherited": {"type": "boolean", "description": "Default false"},
	}, ["class_name"], true)
	_add("get_project_settings", "Read project settings by name, or list the names under a prefix.", {
		"names": {"type": "array", "items": s, "description": "e.g. [\"application/run/main_scene\"]"},
		"prefix": {"type": "string", "description": "List settings starting with this, e.g. \"input/\""},
	}, [], true)
	_add("set_project_setting", "Set a project setting and save project.godot. Same value rules as set_node_properties.", {
		"name": s,
		"value": {"description": "New value; null removes an override"},
	}, ["name", "value"])
	_add("execute_editor_script", "Run GDScript inside the editor for anything the other tools do not cover. The code is the body of `func run(plugin: EditorPlugin, scene: Node)`; use `return` to send back a value. EditorInterface is available. No `await`.", {
		"code": {"type": "string", "description": "Function body, e.g. \"return scene.get_child_count()\""},
	}, ["code"])


# ---------------------------------------------------------------- helpers

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

func _tool_get_project_info(_args: Dictionary) -> Variant:
	var root := _root()
	var autoloads := {}
	for prop in ProjectSettings.get_property_list():
		var n := str(prop["name"])
		if n.begins_with("autoload/"):
			autoloads[n.substr(9)] = str(ProjectSettings.get_setting(n)).trim_prefix("*")
	return {
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"godot_version": Engine.get_version_info()["string"],
		"project_dir": ProjectSettings.globalize_path("res://"),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"edited_scene": root.scene_file_path if root != null else null,
		"edited_scene_root": ("%s (%s)" % [root.name, root.get_class()]) if root != null else null,
		"open_scenes": Array(EditorInterface.get_open_scenes()).filter(func(p): return p != ""),
		"autoloads": autoloads,
		"is_playing": EditorInterface.is_playing_scene(),
	}


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


func _extensions_arg(value: Variant) -> Array:
	var out := []
	if value is Array:
		for e in value:
			out.append(str(e).trim_prefix(".").to_lower())
	return out


func _tool_list_files(args: Dictionary) -> Variant:
	var dir := _res_path(args.get("dir", "res://"))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return _err("Directory not found: " + str(args.get("dir", "")))
	var files := []
	_walk(dir, bool(args.get("recursive", true)), _extensions_arg(args.get("extensions")), files, 2000)
	return {"dir": dir, "count": files.size(), "truncated": files.size() >= 2000, "files": files}


func _tool_read_file(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _err("File not found: " + str(args.get("path", "")))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _err("Cannot open %s: %s" % [path, error_string(FileAccess.get_open_error())])
	if file.get_length() > MAX_READ_BYTES and not args.has("max_lines"):
		return _err("File is %d bytes. Read it in parts with start_line and max_lines." % file.get_length())
	var text := file.get_as_text()
	if not args.has("start_line") and not args.has("max_lines"):
		return text
	var lines := text.split("\n")
	var start := maxi(_to_int(args.get("start_line"), 1), 1) - 1
	var count := _to_int(args.get("max_lines"), lines.size())
	return "\n".join(lines.slice(start, start + maxi(count, 0)))


func _tool_write_file(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or path == "res://":
		return _err("Path must be inside the project (res://...).")
	if not (args.get("content") is String):
		return _err("content must be a string.")
	return _write_text(path, args["content"])


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


func _tool_search_files(args: Dictionary) -> Variant:
	var query := str(args.get("query", "")).to_lower()
	if query == "":
		return _err("query is empty.")
	var dir := _res_path(args.get("dir", "res://"))
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return _err("Directory not found: " + str(args.get("dir", "")))
	var extensions := _extensions_arg(args.get("extensions"))
	if extensions.is_empty():
		extensions = ["gd", "tscn", "tres", "cs", "gdshader", "cfg", "json", "md", "txt"]
	var limit := clampi(_to_int(args.get("max_results"), 100), 1, 1000)
	var files := []
	_walk(dir, true, extensions, files, 5000)
	var matches := []
	for path in files:
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 2 * 1024 * 1024:
			continue
		var lines := file.get_as_text().split("\n")
		for i in lines.size():
			if lines[i].to_lower().contains(query):
				matches.append("%s:%d: %s" % [path, i + 1, lines[i].strip_edges().left(200)])
				if matches.size() >= limit:
					return {"count": matches.size(), "truncated": true, "matches": matches}
	return {"count": matches.size(), "truncated": false, "matches": matches}


func _tool_validate_script(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not FileAccess.file_exists(path):
		return _err("File not found: " + str(args.get("path", "")))
	if path.get_extension().to_lower() != "gd":
		return _err("Only .gd files can be validated.")
	var result := _compile_script(path, FileAccess.get_file_as_string(path))
	result["path"] = path
	return result


# ---------------------------------------------------------------- scenes

func _tool_open_scene(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return _err("Scene not found: " + str(args.get("path", "")))
	if path in EditorInterface.get_open_scenes():
		EditorInterface.reload_scene_from_path(path)
	EditorInterface.open_scene_from_path(path)
	var root := _root()
	if root == null or root.scene_file_path != path:
		return _err("The editor did not open %s. Check get_output for errors." % path)
	return {"opened": path, "root": "%s (%s)" % [root.name, root.get_class()]}


func _tool_create_scene(args: Dictionary) -> Variant:
	var path := _res_path(args.get("path", ""))
	if path == "" or not (path.get_extension().to_lower() in ["tscn", "scn"]):
		return _err("path must be a res:// path ending in .tscn")
	if FileAccess.file_exists(path):
		return _err("File already exists: %s. Use open_scene, or pick another path." % path)
	var root := _instantiate(str(args.get("root_type", "")))
	if root == null:
		return _err("'%s' is not a Node class that can be instantiated." % str(args.get("root_type", "")))
	var root_name := str(args.get("root_name", ""))
	root.name = root_name if root_name != "" else path.get_file().get_basename().to_pascal_case()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	if err != OK:
		return _err("Could not save scene: " + error_string(err))
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.update_file(path)
	EditorInterface.open_scene_from_path(path)
	return {"created": path, "opened": _root() != null and _root().scene_file_path == path}


func _tool_save_scene(args: Dictionary) -> Variant:
	var root := _root()
	if root == null:
		return _err("No scene is open.")
	if args.has("path") and str(args["path"]) != "":
		var path := _res_path(args["path"])
		if path == "" or not (path.get_extension().to_lower() in ["tscn", "scn"]):
			return _err("path must be a res:// path ending in .tscn")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		EditorInterface.save_scene_as(path)
		return {"saved": path}
	if root.scene_file_path == "":
		return _err("This scene has never been saved. Pass path.")
	var err := EditorInterface.save_scene()
	if err != OK:
		return _err("Save failed: " + error_string(err))
	return {"saved": root.scene_file_path}


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


func _tool_get_scene_tree(args: Dictionary) -> Variant:
	var root := _root()
	if root == null:
		return _err("No scene is open in the editor. Use open_scene or create_scene first.")
	var start := _find(args.get("node_path", "."))
	if start == null:
		return _no_node(args.get("node_path"))
	return {
		"scene": root.scene_file_path,
		"path": _path_of(start),
		"tree": _describe_node(start, root, 0, clampi(_to_int(args.get("max_depth"), 8), 0, 64)),
	}


# ---------------------------------------------------------------- nodes

func _tool_get_node_properties(args: Dictionary) -> Variant:
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var wanted: Variant = args.get("properties")
	var props := {}
	if wanted is Array and not wanted.is_empty():
		for name in wanted:
			var key := str(name)
			var base := key.split(":")[0]
			if base in node:
				props[key] = Values.to_json(node.get_indexed(NodePath(key)) if key.contains(":") else node.get(key))
			else:
				props[key] = "<no such property>"
	else:
		for p in node.get_property_list():
			if (p["usage"] & PROPERTY_USAGE_EDITOR) == 0:
				continue
			if p["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
				continue
			props[p["name"]] = Values.to_json(node.get(p["name"]))
	var connections := []
	for sig in node.get_signal_list():
		for conn in node.get_signal_connection_list(sig["name"]):
			if (conn["flags"] & CONNECT_PERSIST) == 0:
				continue
			var callable: Callable = conn["callable"]
			var target: Variant = callable.get_object()
			connections.append({
				"signal": str(sig["name"]),
				"target": _path_of(target) if target is Node else str(target),
				"method": str(callable.get_method()),
			})
	var groups := []
	for g in node.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	var out := {"path": _path_of(node), "type": node.get_class(), "properties": props}
	if not groups.is_empty():
		out["groups"] = groups
	if not connections.is_empty():
		out["connections"] = connections
	return out


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


func _tool_set_node_properties(args: Dictionary) -> Variant:
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var values: Variant = args.get("properties")
	if not (values is Dictionary) or values.is_empty():
		return _err("properties must be a non-empty object.")
	var prepared := _prepare_properties(node, values)
	if not prepared[1].is_empty():
		return _err("Nothing was changed.\n" + "\n".join(prepared[1]))
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Set properties on %s" % node.name, UndoRedo.MERGE_DISABLE, node)
	for change in prepared[0]:
		if change[1]:
			ur.add_do_method(node, "set_indexed", NodePath(change[0]), change[2])
			ur.add_undo_method(node, "set_indexed", NodePath(change[0]), change[3])
		else:
			ur.add_do_property(node, change[0], change[2])
			ur.add_undo_property(node, change[0], change[3])
	ur.commit_action()
	var now := {}
	for change in prepared[0]:
		now[change[0]] = Values.to_json(node.get_indexed(NodePath(change[0])) if change[1] else node.get(change[0]))
	return {"path": _path_of(node), "properties": now}


func _tool_add_node(args: Dictionary) -> Variant:
	var root := _root()
	if root == null:
		return _err("No scene is open in the editor. Use open_scene or create_scene first.")
	var parent := _find(args.get("parent_path", "."))
	if parent == null:
		return _no_node(args.get("parent_path"))
	var node: Node
	var scene_path := str(args.get("scene_path", ""))
	if scene_path != "":
		scene_path = _res_path(scene_path)
		if scene_path == "" or not ResourceLoader.exists(scene_path):
			return _err("Scene not found: " + str(args.get("scene_path")))
		if scene_path == root.scene_file_path:
			return _err("A scene cannot instance itself.")
		var packed: Variant = load(scene_path)
		if not (packed is PackedScene):
			return _err("Not a scene: " + scene_path)
		node = packed.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	else:
		var type := str(args.get("type", ""))
		if type == "":
			return _err("Give either type or scene_path.")
		node = _instantiate(type)
		if node == null:
			return _err("'%s' is not a Node class that can be instantiated. Use get_class_info to check names." % type)
	if node == null:
		return _err("Could not create the node.")
	if str(args.get("name", "")) != "":
		node.name = str(args["name"])
	var values: Variant = args.get("properties")
	if values is Dictionary and not values.is_empty():
		var prepared := _prepare_properties(node, values)
		if not prepared[1].is_empty():
			node.free()
			return _err("Node was not added.\n" + "\n".join(prepared[1]))
		for change in prepared[0]:
			if change[1]:
				node.set_indexed(NodePath(change[0]), change[2])
			else:
				node.set(change[0], change[2])
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Add %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", root)
	if args.has("index"):
		ur.add_do_method(parent, "move_child", node, _to_int(args["index"], -1))
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	return {"path": _path_of(node), "name": str(node.name), "type": node.get_class()}


func _tool_delete_node(args: Dictionary) -> Variant:
	var root := _root()
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	if node == root:
		return _err("The scene root cannot be deleted.")
	var parent := node.get_parent()
	var path := _path_of(node)
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Delete %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	ur.add_do_method(parent, "remove_child", node)
	ur.add_undo_method(parent, "add_child", node, true)
	ur.add_undo_method(parent, "move_child", node, node.get_index())
	for pair in _owned_nodes(node):
		if pair[1] != null:
			ur.add_undo_method(pair[0], "set_owner", pair[1])
	ur.add_undo_reference(node)
	ur.commit_action()
	return {"deleted": path}


func _tool_move_node(args: Dictionary) -> Variant:
	var root := _root()
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var old_parent := node.get_parent()
	var new_parent := old_parent
	if args.has("new_parent_path"):
		if node == root:
			return _err("The scene root cannot be reparented.")
		new_parent = _find(args["new_parent_path"])
		if new_parent == null:
			return _no_node(args["new_parent_path"])
		if new_parent == node or node.is_ancestor_of(new_parent):
			return _err("A node cannot be moved into itself or its own children.")
	var new_name := str(args.get("new_name", ""))
	if not args.has("new_parent_path") and new_name == "" and not args.has("index"):
		return _err("Give new_name, new_parent_path and/or index.")
	if args.has("index") and node == root:
		return _err("The scene root has no sibling index.")
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: Move %s" % node.name, UndoRedo.MERGE_DISABLE, root)
	if new_parent != old_parent:
		var owners := _owned_nodes(node)
		ur.add_do_method(old_parent, "remove_child", node)
		ur.add_do_method(new_parent, "add_child", node, true)
		ur.add_undo_method(new_parent, "remove_child", node)
		ur.add_undo_method(old_parent, "add_child", node, true)
		ur.add_undo_method(old_parent, "move_child", node, node.get_index())
		for pair in owners:
			if pair[1] != null:
				ur.add_do_method(pair[0], "set_owner", pair[1])
				ur.add_undo_method(pair[0], "set_owner", pair[1])
	if new_name != "":
		ur.add_do_property(node, "name", new_name)
		ur.add_undo_property(node, "name", str(node.name))
	if args.has("index"):
		ur.add_do_method(new_parent, "move_child", node, _to_int(args["index"], -1))
		if new_parent == old_parent:
			ur.add_undo_method(old_parent, "move_child", node, node.get_index())
	ur.commit_action()
	return {"path": _path_of(node), "name": str(node.name), "index": node.get_index() if node != root else 0}


func _tool_connect_signal(args: Dictionary) -> Variant:
	var node := _find(args.get("node_path", ""))
	if node == null:
		return _no_node(args.get("node_path"))
	var target := _find(args.get("target_path", ""))
	if target == null:
		return _no_node(args.get("target_path"))
	var signal_name := str(args.get("signal", ""))
	var method := str(args.get("method", ""))
	if not node.has_signal(signal_name):
		var names := []
		for sig in node.get_signal_list():
			names.append(str(sig["name"]))
		return _err("%s has no signal '%s'. Signals: %s" % [node.get_class(), signal_name, ", ".join(names)])
	if method == "":
		return _err("method is empty.")
	var callable := Callable(target, method)
	var connected := node.is_connected(signal_name, callable)
	var remove := bool(args.get("disconnect", false))
	if remove and not connected:
		return _err("That connection does not exist.")
	if not remove and connected:
		return {"already_connected": true}
	var ur := _plugin.get_undo_redo()
	ur.create_action("MCP: %s signal %s" % ["Disconnect" if remove else "Connect", signal_name], UndoRedo.MERGE_DISABLE, _root())
	if remove:
		ur.add_do_method(node, "disconnect", signal_name, callable)
		ur.add_undo_method(node, "connect", signal_name, callable, CONNECT_PERSIST)
	else:
		ur.add_do_method(node, "connect", signal_name, callable, CONNECT_PERSIST)
		ur.add_undo_method(node, "disconnect", signal_name, callable)
	ur.commit_action()
	var out := {"signal": signal_name, "from": _path_of(node), "to": _path_of(target), "method": method, "connected": not remove}
	var script: Variant = target.get_script()
	if not remove and not target.has_method(method) and not (script is Script and method in _script_methods(script)):
		out["warning"] = "Target has no method '%s' yet. Add it to the target's script." % method
	return out


func _script_methods(script: Script) -> Array:
	var names := []
	for m in script.get_script_method_list():
		names.append(str(m["name"]))
	return names


# ---------------------------------------------------------------- run and inspect

func _tool_run_project(args: Dictionary) -> Variant:
	var mode := str(args.get("mode", "main"))
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	match mode:
		"main":
			if str(ProjectSettings.get_setting("application/run/main_scene", "")) == "":
				return _err("No main scene is set. Use mode=current, or set_project_setting application/run/main_scene.")
			EditorInterface.play_main_scene()
		"current":
			var root := _root()
			if root == null or root.scene_file_path == "":
				return _err("The edited scene must be saved before it can run.")
			EditorInterface.play_current_scene()
		"custom":
			var path := _res_path(args.get("scene_path", ""))
			if path == "" or not ResourceLoader.exists(path):
				return _err("Scene not found: " + str(args.get("scene_path", "")))
			EditorInterface.play_custom_scene(path)
		_:
			return _err("mode must be main, current or custom.")
	return {"started": mode, "hint": "Use get_output source=game after a moment to read prints and errors, and stop_project to stop."}


func _tool_stop_project(_args: Dictionary) -> Variant:
	var was_playing := EditorInterface.is_playing_scene()
	if was_playing:
		EditorInterface.stop_playing_scene()
	return {"stopped": was_playing}


func _tool_get_output(args: Dictionary) -> Variant:
	var count := clampi(_to_int(args.get("lines"), 100), 1, 2000)
	if str(args.get("source", "editor")) == "game":
		var log_path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
		if not FileAccess.file_exists(log_path):
			return _err("No game log at %s yet. Run the project first (file logging must be enabled in Project Settings > Debug > File Logging)." % log_path)
		var lines := FileAccess.get_file_as_string(log_path).split("\n")
		return "\n".join(lines.slice(maxi(lines.size() - count, 0)))
	var tail: PackedStringArray = _capture.tail(count)
	return "\n".join(tail) if not tail.is_empty() else "(no output)"


func _tool_take_screenshot(args: Dictionary) -> Variant:
	var target := str(args.get("target", "editor"))
	if not (target in ["2d", "3d", "editor"]):
		return _err("target must be 2d, 3d or editor.")
	if DisplayServer.get_name() == "headless":
		return _err("No rendered viewport is available (the editor is running headless).")
	# The 2D/3D viewports only render while their workspace is shown, so switch to it and
	# capture a few frames later.
	if target == "2d":
		EditorInterface.set_main_screen_editor("2D")
	elif target == "3d":
		EditorInterface.set_main_screen_editor("3D")
	var ticket := _next_shot
	_next_shot -= 1
	_shots[ticket] = {"target": target, "frames": 4, "max_width": clampi(_to_int(args.get("max_width"), 1280), 64, 4096)}
	return {"__pending": ticket}


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


func _type_name(info: Dictionary, is_return := false) -> String:
	if info["type"] == TYPE_OBJECT and str(info.get("class_name", "")) != "":
		return str(info["class_name"])
	if info["type"] == TYPE_NIL:
		return "void" if is_return and (info.get("usage", 0) & PROPERTY_USAGE_NIL_IS_VARIANT) == 0 else "Variant"
	return type_string(info["type"])


func _tool_get_class_info(args: Dictionary) -> Variant:
	var cls := str(args.get("class_name", ""))
	if not ClassDB.class_exists(cls):
		for info in ProjectSettings.get_global_class_list():
			if str(info["class"]) == cls:
				return {"class": cls, "script": info["path"], "inherits": str(info["base"]), "hint": "Script class: use read_file on the script, and get_class_info on the base class."}
		return _err("Unknown class: " + cls)
	var own := not bool(args.get("include_inherited", false))
	var properties := []
	for p in ClassDB.class_get_property_list(cls, own):
		if p["usage"] & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP):
			continue
		properties.append("%s: %s" % [p["name"], _type_name(p)])
	var methods := []
	for m in ClassDB.class_get_method_list(cls, own):
		if str(m["name"]).begins_with("_"):
			continue
		var params := []
		for a in m["args"]:
			params.append("%s: %s" % [a["name"], _type_name(a)])
		methods.append("%s(%s) -> %s" % [m["name"], ", ".join(params), _type_name(m["return"], true)])
	var signals := []
	for sig in ClassDB.class_get_signal_list(cls, own):
		var params := []
		for a in sig["args"]:
			params.append("%s: %s" % [a["name"], _type_name(a)])
		signals.append("%s(%s)" % [sig["name"], ", ".join(params)])
	return {
		"class": cls,
		"inherits": str(ClassDB.get_parent_class(cls)),
		"can_instantiate": ClassDB.can_instantiate(cls),
		"properties": properties,
		"methods": methods,
		"signals": signals,
	}


func _tool_get_project_settings(args: Dictionary) -> Variant:
	var out := {}
	var names: Variant = args.get("names")
	if names is Array:
		for n in names:
			out[str(n)] = Values.to_json(ProjectSettings.get_setting(str(n))) if ProjectSettings.has_setting(str(n)) else "<not set>"
	var prefix := str(args.get("prefix", ""))
	if prefix != "":
		for p in ProjectSettings.get_property_list():
			var n := str(p["name"])
			if n.begins_with(prefix) and out.size() < 300:
				out[n] = Values.to_json(ProjectSettings.get_setting(n))
	if out.is_empty():
		return _err("Give names and/or prefix (e.g. prefix \"application/\").")
	return out


func _tool_set_project_setting(args: Dictionary) -> Variant:
	var name := str(args.get("name", ""))
	if name == "" or not name.contains("/"):
		return _err("name must look like \"section/key\", e.g. \"application/run/main_scene\".")
	var value: Variant = args.get("value")
	var type := TYPE_NIL
	if ProjectSettings.has_setting(name):
		type = typeof(ProjectSettings.get_setting(name))
	if type == TYPE_OBJECT:
		type = TYPE_NIL
	var r := Values.coerce(value, type)
	if not r[0]:
		return _err("%s: %s" % [name, r[1]])
	ProjectSettings.set_setting(name, r[1])
	var err := ProjectSettings.save()
	if err != OK:
		return _err("Could not save project.godot: " + error_string(err))
	return {"name": name, "value": Values.to_json(ProjectSettings.get_setting(name)) if ProjectSettings.has_setting(name) else null}


func _tool_execute_editor_script(args: Dictionary) -> Variant:
	var code := str(args.get("code", ""))
	if code.strip_edges() == "":
		return _err("code is empty.")
	var body := ""
	for line in code.split("\n"):
		body += "\t" + line + "\n"
	var script := GDScript.new()
	script.source_code = "@tool\nextends RefCounted\n\nfunc run(plugin: EditorPlugin, scene: Node) -> Variant:\n" + body + "\treturn null\n"
	var marker: int = _capture.mark()
	var err := script.reload()
	if err != OK:
		var problems := _error_lines(_capture.since(marker))
		return _err("The code did not compile (line numbers are offset by 4).\n" + ("\n".join(problems) if not problems.is_empty() else "See get_output source=editor."))
	var runner: Variant = script.new()
	var result: Variant = runner.run(_plugin, _root())
	var out := {}
	if result is Object and result.get_class() == "GDScriptFunctionState":
		out["result"] = "<coroutine: `await` is not supported here; the code kept running in the background>"
	else:
		out["result"] = Values.to_json(result)
	var logged: PackedStringArray = _capture.since(marker)
	if not logged.is_empty():
		out["output"] = "\n".join(logged.slice(maxi(logged.size() - 200, 0)))
	return out
